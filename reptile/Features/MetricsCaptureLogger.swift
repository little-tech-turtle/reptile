import CameraKit
import CoreMedia
import Foundation

final class MetricsCaptureLogger {
    static let schemaVersion = 1

    struct StartResult {
        let url: URL
        let sessionID: String
    }

    private enum RecordType: String, Codable {
        case sessionStart = "session_start"
        case frame
        case sessionEnd = "session_end"
    }

    private struct SessionStartRecord: Codable {
        let schemaVersion: Int
        let recordType: RecordType
        let sessionID: String
        let exercise: String
        let startedAt: String
        let appBundleID: String
        let appVersion: String
        let appBuild: String
        let deviceModel: String
        let osVersion: String
    }

    private struct FrameRecord: Codable {
        let schemaVersion: Int
        let recordType: RecordType
        let sessionID: String
        let tSec: Double
        let exercise: String
        let repCount: Int
        let state: String
        let metric: Double?
        let statusHint: String?
        let joints2DCount: Int
        let trackedJointCount: Int
        let raw3D: Int
        let stabilized3D: Int
        let dropped3D: Int
        let held3D: Int
        let clamped3D: Int
        let confidence: Double?
        let diagnostics: [String: DiagnosticValue]
    }

    private struct SessionEndRecord: Codable {
        let schemaVersion: Int
        let recordType: RecordType
        let sessionID: String
        let exercise: String
        let endedAt: String
        let durationSec: Double
        let frameCount: Int
        let finalRepCount: Int
        let exportReason: String
    }

    private enum DiagnosticValue: Codable {
        case number(Double)
        case text(String)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(Double.self) {
                self = .number(number)
                return
            }
            self = .text(try container.decode(String.self))
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .number(let value):
                try container.encode(value)
            case .text(let value):
                try container.encode(value)
            }
        }
    }

    private struct ActiveSessionState: Codable {
        let sessionID: String
        let exercise: String
        let filePath: String
        let startedAtISO8601: String
        let startedAtSeconds: Double
        let frameCount: Int
        let finalRepCount: Int
    }

    private static let activeSessionDefaultsKey = "metrics.capture.active-session.v1"

    private let fileManager: FileManager
    private let userDefaults: UserDefaults
    private let encoder: JSONEncoder
    private let iso8601Formatter: ISO8601DateFormatter
    private let maxFilesPerExercise: Int

    private var activeSession: ActiveSessionState?
    private var fileHandle: FileHandle?

    var isCapturing: Bool { activeSession != nil }

    init(
        fileManager: FileManager = .default,
        userDefaults: UserDefaults = .standard,
        maxFilesPerExercise: Int = 10
    ) {
        self.fileManager = fileManager
        self.userDefaults = userDefaults
        self.maxFilesPerExercise = max(1, maxFilesPerExercise)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.iso8601Formatter = formatter
    }

    func recoverInterruptedSessionIfNeeded() {
        guard let data = userDefaults.data(forKey: Self.activeSessionDefaultsKey),
              let stale = try? JSONDecoder().decode(ActiveSessionState.self, from: data) else {
            return
        }

        let url = URL(fileURLWithPath: stale.filePath)
        guard fileManager.fileExists(atPath: url.path),
              let handle = try? FileHandle(forWritingTo: url) else {
            userDefaults.removeObject(forKey: Self.activeSessionDefaultsKey)
            return
        }

        defer { try? handle.close() }
        _ = try? handle.seekToEnd()

        let end = SessionEndRecord(
            schemaVersion: Self.schemaVersion,
            recordType: .sessionEnd,
            sessionID: stale.sessionID,
            exercise: stale.exercise,
            endedAt: iso8601Formatter.string(from: Date()),
            durationSec: Date().timeIntervalSince1970 - stale.startedAtSeconds,
            frameCount: stale.frameCount,
            finalRepCount: stale.finalRepCount,
            exportReason: "interrupted"
        )
        write(end, to: handle)
        userDefaults.removeObject(forKey: Self.activeSessionDefaultsKey)
    }

    func startCapture(exercise: String) throws -> StartResult {
        if isCapturing {
            throw CaptureError.alreadyCapturing
        }

        let capturesDirectory = try ensureCapturesDirectory()
        let timestamp = Self.filenameTimestampFormatter.string(from: Date())
        let fileName = "\(exercise)-\(timestamp)-v\(Self.schemaVersion).ndjson"
        let url = capturesDirectory.appendingPathComponent(fileName)
        fileManager.createFile(atPath: url.path, contents: nil)

        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()

        let sessionID = UUID().uuidString.lowercased()
        let now = Date()
        let start = SessionStartRecord(
            schemaVersion: Self.schemaVersion,
            recordType: .sessionStart,
            sessionID: sessionID,
            exercise: exercise,
            startedAt: iso8601Formatter.string(from: now),
            appBundleID: Bundle.main.bundleIdentifier ?? "unknown",
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            deviceModel: ProcessInfo.processInfo.hostName,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString
        )
        write(start, to: handle)

        let state = ActiveSessionState(
            sessionID: sessionID,
            exercise: exercise,
            filePath: url.path,
            startedAtISO8601: start.startedAt,
            startedAtSeconds: now.timeIntervalSince1970,
            frameCount: 0,
            finalRepCount: 0
        )
        self.activeSession = state
        self.fileHandle = handle
        persistActiveSession(state)

        pruneCaptures(for: exercise, in: capturesDirectory)
        return StartResult(url: url, sessionID: sessionID)
    }

    @discardableResult
    func stopCapture(exportReason: String = "manual") throws -> URL {
        guard let session = activeSession, let handle = fileHandle else {
            throw CaptureError.notCapturing
        }

        let now = Date()
        let end = SessionEndRecord(
            schemaVersion: Self.schemaVersion,
            recordType: .sessionEnd,
            sessionID: session.sessionID,
            exercise: session.exercise,
            endedAt: iso8601Formatter.string(from: now),
            durationSec: now.timeIntervalSince1970 - session.startedAtSeconds,
            frameCount: session.frameCount,
            finalRepCount: session.finalRepCount,
            exportReason: exportReason
        )
        write(end, to: handle)
        try handle.close()

        let path = session.filePath
        activeSession = nil
        fileHandle = nil
        userDefaults.removeObject(forKey: Self.activeSessionDefaultsKey)
        return URL(fileURLWithPath: path)
    }

    func record(_ output: RepCounterOutput) {
        guard var session = activeSession, let handle = fileHandle else { return }

        var diagnostics: [String: DiagnosticValue] = [:]
        for (key, value) in output.exerciseDiagnostics?.scalars ?? [:] {
            diagnostics[key] = .number(value)
        }
        for (key, value) in output.exerciseDiagnostics?.labels ?? [:] {
            diagnostics[key] = .text(value)
        }

        let poseDiagnostics = output.poseFrame.diagnostics
        let frame = FrameRecord(
            schemaVersion: Self.schemaVersion,
            recordType: .frame,
            sessionID: session.sessionID,
            tSec: CMTimeGetSeconds(output.poseFrame.timestamp),
            exercise: output.exerciseProfileID,
            repCount: output.repCount,
            state: output.state.rawValue,
            metric: output.currentMetric.map(Double.init),
            statusHint: output.statusHint,
            joints2DCount: output.poseFrame.joints.count,
            trackedJointCount: output.trackedJoints.count,
            raw3D: poseDiagnostics.raw3DJointCount,
            stabilized3D: poseDiagnostics.stabilized3DJointCount,
            dropped3D: poseDiagnostics.dropped3DJointCount,
            held3D: poseDiagnostics.held3DJointCount,
            clamped3D: poseDiagnostics.clamped3DJointCount,
            confidence: poseDiagnostics.observationConfidence.map(Double.init),
            diagnostics: diagnostics
        )
        write(frame, to: handle)

        session = ActiveSessionState(
            sessionID: session.sessionID,
            exercise: session.exercise,
            filePath: session.filePath,
            startedAtISO8601: session.startedAtISO8601,
            startedAtSeconds: session.startedAtSeconds,
            frameCount: session.frameCount + 1,
            finalRepCount: output.repCount
        )
        activeSession = session
        persistActiveSession(session)
    }

    private func write<T: Encodable>(_ record: T, to handle: FileHandle) {
        guard let data = try? encoder.encode(record),
              let newline = "\n".data(using: .utf8) else { return }
        handle.write(data)
        handle.write(newline)
    }

    private func persistActiveSession(_ state: ActiveSessionState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        userDefaults.set(data, forKey: Self.activeSessionDefaultsKey)
    }

    private func ensureCapturesDirectory() throws -> URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let captures = documents.appendingPathComponent("Captures", isDirectory: true)
        if !fileManager.fileExists(atPath: captures.path) {
            try fileManager.createDirectory(at: captures, withIntermediateDirectories: true)
        }
        return captures
    }

    private func pruneCaptures(for exercise: String, in capturesDirectory: URL) {
        guard let files = try? fileManager.contentsOfDirectory(
            at: capturesDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let matching = files
            .filter { $0.lastPathComponent.hasPrefix("\(exercise)-") && $0.pathExtension == "ndjson" }
            .sorted { lhs, rhs in
                let leftDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rightDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return leftDate > rightDate
            }

        guard matching.count > maxFilesPerExercise else { return }
        for url in matching.dropFirst(maxFilesPerExercise) {
            try? fileManager.removeItem(at: url)
        }
    }

    enum CaptureError: Error {
        case alreadyCapturing
        case notCapturing
    }

    private static let filenameTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
