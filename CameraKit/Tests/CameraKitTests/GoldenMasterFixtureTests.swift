import Foundation
import Testing

struct GoldenMasterFixtureTests {
    private struct SessionStart: Decodable {
        let schemaVersion: Int
        let recordType: String
        let sessionID: String
        let exercise: String
    }

    private struct SessionEnd: Decodable {
        let schemaVersion: Int
        let recordType: String
        let sessionID: String
        let exercise: String
    }

    private struct Frame: Decodable {
        let schemaVersion: Int
        let recordType: String
        let sessionID: String
        let exercise: String
        let diagnostics: [String: DiagnosticValue]?
    }

    private enum DiagnosticValue: Decodable {
        case number(Double)
        case text(String)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(Double.self) {
                self = .number(number)
            } else {
                self = .text(try container.decode(String.self))
            }
        }
    }

    @Test func goldenFixtures_haveValidSessionEnvelope() throws {
        let fixtureURLs = try fixtureFiles()
        if fixtureURLs.isEmpty {
            return
        }

        for url in fixtureURLs {
            let text = try String(contentsOf: url, encoding: .utf8)
            let lines = text.split(separator: "\n").map(String.init)
            #expect(!lines.isEmpty)

            let start = try JSONDecoder().decode(SessionStart.self, from: Data(lines[0].utf8))
            #expect(start.recordType == "session_start")
            #expect(start.schemaVersion == 1)

            let end = try JSONDecoder().decode(SessionEnd.self, from: Data(lines[lines.count - 1].utf8))
            #expect(end.recordType == "session_end")
            #expect(end.schemaVersion == 1)
            #expect(start.sessionID == end.sessionID)
            #expect(start.exercise == end.exercise)

            var unknownDiagnostics = Set<String>()
            for line in lines.dropFirst().dropLast() {
                let frame = try JSONDecoder().decode(Frame.self, from: Data(line.utf8))
                #expect(frame.recordType == "frame")
                #expect(frame.schemaVersion == 1)
                #expect(frame.sessionID == start.sessionID)
                #expect(frame.exercise == start.exercise)

                for key in frame.diagnostics?.keys ?? [] {
                    if !knownDiagnosticKeys.contains(key) {
                        unknownDiagnostics.insert(key)
                    }
                }
            }

            if !unknownDiagnostics.isEmpty {
                Issue.record("Unknown diagnostics keys in \(url.lastPathComponent): \(unknownDiagnostics.sorted().joined(separator: ", "))")
            }
        }
    }

    private func fixtureFiles() throws -> [URL] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)

        guard FileManager.default.fileExists(atPath: root.path) else {
            return []
        }

        let urls = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        return urls.filter { $0.pathExtension == "ndjson" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private let knownDiagnosticKeys: Set<String> = [
        "squat.kneeFlexionDegrees",
        "squat.hipFlexionDegrees",
        "squat.leftKneeFlexionDegrees",
        "squat.rightKneeFlexionDegrees",
        "squat.leftHipFlexionDegrees",
        "squat.rightHipFlexionDegrees",
        "curl.elbowFlexionDegrees",
        "curl.leftElbowFlexionDegrees",
        "curl.rightElbowFlexionDegrees",
        "curl.activeSide",
        "bench.elbowFlexionDegrees",
        "bench.leftElbowFlexionDegrees",
        "bench.rightElbowFlexionDegrees",
        "bench.activeSide",
    ]
}
