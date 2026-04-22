import UIKit
import CameraKit
import Vision

final class DebugOverlayView: UIView {
    private var exerciseDefinition: ExerciseDefinition = ExerciseCatalog.defaultExercise
    private var configuration: RepCountingConfiguration = ExerciseCatalog.defaultExercise.defaultTuning
    private var history: [CGFloat] = []
    private var poseDiagnosticsHistory: [PoseFrameDiagnostics] = []
    private var elbowFlexionHistory: [CGFloat] = []
    private var latestOutput: RepCounterOutput?

    private let metricHistoryCapacity = 150
    private let poseHistoryCapacity = 120
    private let elbowHistoryCapacity = 120

    func updateConfiguration(_ configuration: RepCountingConfiguration, exerciseDefinition: ExerciseDefinition) {
        if self.exerciseDefinition.id != exerciseDefinition.id {
            history.removeAll()
            poseDiagnosticsHistory.removeAll()
            elbowFlexionHistory.removeAll()
        }
        self.configuration = configuration
        self.exerciseDefinition = exerciseDefinition
        setNeedsDisplay()
    }

    func update(output: RepCounterOutput, exerciseDefinition: ExerciseDefinition) {
        self.exerciseDefinition = exerciseDefinition
        latestOutput = output

        if let metric = output.currentMetric {
            history.append(metric)
            if history.count > metricHistoryCapacity {
                history.removeFirst()
            }
        }

        poseDiagnosticsHistory.append(output.poseFrame.diagnostics)
        if poseDiagnosticsHistory.count > poseHistoryCapacity {
            poseDiagnosticsHistory.removeFirst()
        }

        if let elbowDegrees = output.exerciseDiagnostics?.scalars["curl.elbowFlexionDegrees"] {
            elbowFlexionHistory.append(CGFloat(elbowDegrees))
            if elbowFlexionHistory.count > elbowHistoryCapacity {
                elbowFlexionHistory.removeFirst()
            }
        }

        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        UIColor.black.withAlphaComponent(0.75).setFill()
        UIRectFill(rect)

        let waveHeight = rect.height * 0.65
        let waveRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: waveHeight)
        let statsRect = CGRect(x: rect.minX, y: rect.minY + waveHeight, width: rect.width, height: rect.height - waveHeight)

        drawThresholds(in: waveRect, ctx: ctx)
        drawWaveform(in: waveRect)
        drawStats(in: statsRect)
    }

    private func yPosition(for value: CGFloat, in rect: CGRect) -> CGFloat {
        let clamped = max(0, min(1, value))
        return rect.maxY - clamped * rect.height
    }

    private func drawThresholds(in rect: CGRect, ctx: CGContext) {
        let thresholds = exerciseDefinition.thresholdDefinitions
        let dash: [CGFloat] = [6, 4]
        let labelFont = UIFont.systemFont(ofSize: 10, weight: .medium)
        let labelAttrs: [NSAttributedString.Key: Any] = [.font: labelFont]

        for threshold in thresholds {
            let y = yPosition(for: threshold.value(configuration), in: rect)

            ctx.saveGState()
            ctx.setStrokeColor(threshold.color.cgColor)
            ctx.setLineWidth(1)
            ctx.setLineDash(phase: 0, lengths: dash)
            ctx.move(to: CGPoint(x: rect.minX, y: y))
            ctx.addLine(to: CGPoint(x: rect.maxX - 36, y: y))
            ctx.strokePath()
            ctx.restoreGState()

            let attrs = labelAttrs.merging([.foregroundColor: threshold.color]) { $1 }
            let label = NSAttributedString(string: threshold.label, attributes: attrs)
            let labelSize = label.size()
            let labelOrigin = CGPoint(x: rect.maxX - labelSize.width - 2, y: y - labelSize.height - 1)
            label.draw(at: labelOrigin)
        }
    }

    private func drawWaveform(in rect: CGRect) {
        guard history.count >= 2 else { return }

        let path = UIBezierPath()
        path.lineWidth = 1.5
        let columnWidth = rect.width / CGFloat(max(history.count - 1, 1))

        for (index, value) in history.enumerated() {
            let x = rect.minX + CGFloat(index) * columnWidth
            let y = yPosition(for: value, in: rect)
            let point = CGPoint(x: x, y: y)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        UIColor.white.setStroke()
        path.stroke()

        if let last = history.last {
            let x = rect.minX + CGFloat(history.count - 1) * columnWidth
            let y = yPosition(for: last, in: rect)
            let dotRect = CGRect(x: x - 4, y: y - 4, width: 8, height: 8)
            let dot = UIBezierPath(ovalIn: dotRect)
            UIColor.white.setFill()
            dot.fill()
        }
    }

    private func drawStats(in rect: CGRect) {
        let metric = latestOutput?.currentMetric.map { String(format: "%.2f", $0) } ?? "--"
        let state = latestOutput?.state.rawValue ?? "--"
        let reps = latestOutput?.repCount ?? 0
        let joints = latestOutput?.poseFrame.joints.count ?? 0
        let tracked = formatTrackedJoints(latestOutput?.trackedJoints ?? [])

        var lines: [String] = [
            "exercise: \(exerciseDefinition.id)   metric: \(metric)   state: \(state)   reps: \(reps)   tracked: \(tracked)   joints: \(joints)"
        ]

        if let poseLine = latestPoseDiagnosticsLine() {
            lines.append(poseLine)
        }

        if let rollingLine = rollingPoseDiagnosticsLine() {
            lines.append(rollingLine)
        }

        lines.append(elbowJitterLine())

        if let output = latestOutput {
            lines.append(contentsOf: exerciseDefinition.diagnosticsText(output, configuration))
        }

        let text = lines.joined(separator: "\n")
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.white,
            .font: UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
        ]

        let str = NSAttributedString(string: text, attributes: attrs)
        let maxBounds = CGSize(width: rect.width - 20, height: rect.height - 6)
        let size = str.boundingRect(with: maxBounds, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).size
        let origin = CGPoint(
            x: rect.minX + (rect.width - size.width) / 2,
            y: rect.minY + (rect.height - size.height) / 2
        )
        str.draw(with: CGRect(origin: origin, size: maxBounds), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
    }

    private func latestPoseDiagnosticsLine() -> String? {
        guard let d = poseDiagnosticsHistory.last else { return nil }
        let confidence = d.observationConfidence.map { String(format: "%.2f", $0) } ?? "--"
        return "pose3D raw:\(d.raw3DJointCount) stab:\(d.stabilized3DJointCount) drop:\(d.dropped3DJointCount) hold:\(d.held3DJointCount) clamp:\(d.clamped3DJointCount) conf:\(confidence)"
    }

    private func rollingPoseDiagnosticsLine() -> String? {
        guard !poseDiagnosticsHistory.isEmpty else { return nil }

        let expected = poseDiagnosticsHistory.reduce(0) { $0 + $1.expected3DJointCount }
        let raw = poseDiagnosticsHistory.reduce(0) { $0 + $1.raw3DJointCount }
        let dropped = poseDiagnosticsHistory.reduce(0) { $0 + $1.dropped3DJointCount }
        let held = poseDiagnosticsHistory.reduce(0) { $0 + $1.held3DJointCount }
        let clamped = poseDiagnosticsHistory.reduce(0) { $0 + $1.clamped3DJointCount }

        let dropRate = expected > 0 ? (Double(dropped) / Double(expected)) * 100 : 0
        let holdRecoveryRate = dropped > 0 ? (Double(held) / Double(dropped)) * 100 : 0
        let clampRate = raw > 0 ? (Double(clamped) / Double(raw)) * 100 : 0

        return String(
            format: "pose window(%d): drop %.1f%%   hold %.1f%%   clamp %.1f%%",
            poseDiagnosticsHistory.count,
            dropRate,
            holdRecoveryRate,
            clampRate
        )
    }

    private func elbowJitterLine() -> String {
        guard elbowFlexionHistory.count >= 2 else {
            return "elbow jitter(σ): --"
        }

        let sigma = standardDeviation(elbowFlexionHistory)
        return String(format: "elbow jitter(σ): %.2f°", sigma)
    }

    private func standardDeviation(_ values: [CGFloat]) -> CGFloat {
        guard !values.isEmpty else { return 0 }
        let count = CGFloat(values.count)
        let mean = values.reduce(0, +) / count
        let variance = values.reduce(0) { partial, value in
            let delta = value - mean
            return partial + delta * delta
        } / count
        return sqrt(max(0, variance))
    }

    private func formatTrackedJoints(_ joints: [VNHumanBodyPose3DObservation.JointName]) -> String {
        guard !joints.isEmpty else { return "--" }
        let names = joints.map(shortName(for:)).sorted()
        return names.joined(separator: "+")
    }

    private func shortName(for joint: VNHumanBodyPose3DObservation.JointName) -> String {
        switch joint {
        case .root: return "root"
        case .spine: return "spine"
        case .leftHip: return "lHip"
        case .rightHip: return "rHip"
        case .leftShoulder: return "lShldr"
        case .rightShoulder: return "rShldr"
        case .leftKnee: return "lKnee"
        case .rightKnee: return "rKnee"
        case .leftAnkle: return "lAnkle"
        case .rightAnkle: return "rAnkle"
        case .leftWrist: return "lWrist"
        case .rightWrist: return "rWrist"
        case .leftElbow: return "lElbow"
        case .rightElbow: return "rElbow"
        default: return String(describing: joint.rawValue)
        }
    }
}
