import Foundation
import CameraKit
import CoreGraphics
import CoreMedia

final class MetricsCaptureLogger {
    private var lines: [String] = []
    private let capacity: Int

    init(capacity: Int = 6000) {
        self.capacity = max(100, capacity)
        lines.append(Self.header)
    }

    func record(_ output: RepCounterOutput) {
        let d = output.poseFrame.diagnostics
        let scalars = output.exerciseDiagnostics?.scalars ?? [:]
        let labels = output.exerciseDiagnostics?.labels ?? [:]

        let row = [
            format(output.poseFrame.timestamp),
            output.exerciseProfileID,
            String(output.repCount),
            output.state.rawValue,
            format(output.currentMetric),
            output.statusHint ?? "",
            String(output.poseFrame.joints.count),
            String(output.trackedJoints.count),
            String(d.raw3DJointCount),
            String(d.stabilized3DJointCount),
            String(d.dropped3DJointCount),
            String(d.held3DJointCount),
            String(d.clamped3DJointCount),
            format(d.observationConfidence),
            format(scalars["squat.kneeFlexionDegrees"]),
            format(scalars["squat.hipFlexionDegrees"]),
            format(scalars["curl.elbowFlexionDegrees"]),
            format(scalars["bench.elbowFlexionDegrees"]),
            labels["curl.activeSide"] ?? labels["bench.activeSide"] ?? "",
        ]
        lines.append(csvEscape(row))
        if lines.count > capacity {
            lines.removeSubrange(1..<(lines.count - capacity + 1))
        }
    }

    private func format(_ time: CMTime) -> String {
        String(format: "%.6f", CMTimeGetSeconds(time))
    }

    func exportToTempFile() throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("reptile-metrics-\(stamp).csv")
        let text = lines.joined(separator: "\n") + "\n"
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static let header = [
        "t_sec",
        "exercise",
        "rep_count",
        "state",
        "metric",
        "status_hint",
        "joints_2d_count",
        "tracked_joint_count",
        "raw3d",
        "stabilized3d",
        "dropped3d",
        "held3d",
        "clamped3d",
        "confidence",
        "squat_knee_deg",
        "squat_hip_deg",
        "curl_elbow_deg",
        "bench_elbow_deg",
        "active_side",
    ].joined(separator: ",")

    private func format(_ value: Double?) -> String {
        guard let value else { return "" }
        return String(format: "%.6f", value)
    }

    private func format(_ value: CGFloat?) -> String {
        guard let value else { return "" }
        return String(format: "%.6f", Double(value))
    }

    private func csvEscape(_ fields: [String]) -> String {
        fields.map { field in
            if field.contains(",") || field.contains("\"") || field.contains("\n") {
                return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }
            return field
        }.joined(separator: ",")
    }
}
