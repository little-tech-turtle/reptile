//
//  DebugOverlayView.swift
//  reptile
//

import UIKit
import CameraKit
import Vision

final class DebugOverlayView: UIView {
    private var history: [CGFloat] = []
    private var currentMetric: CGFloat? = nil
    private var repCount: Int = 0
    private var stateName: String = "--"
    private var jointCount: Int = 0
    private var trackedJointName: String = "--"
    private var descendEntryThreshold: CGFloat = 0.12
    private var bottomThreshold: CGFloat = 0.62
    private var standLockoutThreshold: CGFloat = 0.10
    private var minAmplitude: CGFloat = 0.18
    private var kneeBottomFlexionDegrees: CGFloat = 80
    private var hipBottomFlexionDegrees: CGFloat = 60
    private var kneeLockoutFlexionDegrees: CGFloat = 18
    private var hipLockoutFlexionDegrees: CGFloat = 20
    private var currentKneeFlexionDegrees: CGFloat?
    private var currentHipFlexionDegrees: CGFloat?
    private var leftKneeFlexionDegrees: CGFloat?
    private var rightKneeFlexionDegrees: CGFloat?
    private var leftHipFlexionDegrees: CGFloat?
    private var rightHipFlexionDegrees: CGFloat?

    func updateConfiguration(_ configuration: RepCountingConfiguration) {
        descendEntryThreshold = configuration.squatDescendEntryThreshold
        bottomThreshold = configuration.downThreshold
        standLockoutThreshold = configuration.squatStandLockoutThreshold
        minAmplitude = configuration.minAmplitude
        kneeBottomFlexionDegrees = configuration.squatKneeBottomFlexionDegrees
        hipBottomFlexionDegrees = configuration.squatHipBottomFlexionDegrees
        kneeLockoutFlexionDegrees = configuration.squatKneeLockoutFlexionDegrees
        hipLockoutFlexionDegrees = configuration.squatHipLockoutFlexionDegrees
        setNeedsDisplay()
    }

    func update(output: RepCounterOutput) {
        if let m = output.currentMetric {
            currentMetric = m
            history.append(m)
            if history.count > 150 { history.removeFirst() }
        }
        repCount = output.repCount
        stateName = output.state.rawValue
        jointCount = output.poseFrame.joints.count
        trackedJointName = formatTrackedJoints(output.trackedJoints)
        currentKneeFlexionDegrees = output.squatFlexionMetrics?.kneeFlexionDegrees
        currentHipFlexionDegrees = output.squatFlexionMetrics?.hipFlexionDegrees
        leftKneeFlexionDegrees = output.squatFlexionMetrics?.leftKneeFlexionDegrees
        rightKneeFlexionDegrees = output.squatFlexionMetrics?.rightKneeFlexionDegrees
        leftHipFlexionDegrees = output.squatFlexionMetrics?.leftHipFlexionDegrees
        rightHipFlexionDegrees = output.squatFlexionMetrics?.rightHipFlexionDegrees
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        // 1. Background
        UIColor.black.withAlphaComponent(0.75).setFill()
        UIRectFill(rect)

        let waveHeight = rect.height * 0.65
        let waveRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: waveHeight)
        let statsRect = CGRect(x: rect.minX, y: rect.minY + waveHeight, width: rect.width, height: rect.height - waveHeight)

        // 2. Waveform area
        drawThresholds(in: waveRect, ctx: ctx)
        drawWaveform(in: waveRect)

        // 3. Stats row
        drawStats(in: statsRect)
    }

    private func yPosition(for value: CGFloat, in rect: CGRect) -> CGFloat {
        // value 0.0 → bottom of rect, 1.0 → top of rect
        let clamped = max(0, min(1, value))
        return rect.maxY - clamped * rect.height
    }

    private func drawThresholds(in rect: CGRect, ctx: CGContext) {
        let thresholds: [(value: CGFloat, color: UIColor, label: String)] = [
            (standLockoutThreshold, .systemGreen, "lockout"),
            (descendEntryThreshold, .systemOrange, "entry"),
            (bottomThreshold, .systemRed, "bottom"),
        ]

        let dash: [CGFloat] = [6, 4]
        let labelFont = UIFont.systemFont(ofSize: 10, weight: .medium)
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: labelFont,
        ]

        for threshold in thresholds {
            let y = yPosition(for: threshold.value, in: rect)

            ctx.saveGState()
            ctx.setStrokeColor(threshold.color.cgColor)
            ctx.setLineWidth(1)
            ctx.setLineDash(phase: 0, lengths: dash)
            ctx.move(to: CGPoint(x: rect.minX, y: y))
            ctx.addLine(to: CGPoint(x: rect.maxX - 36, y: y))
            ctx.strokePath()
            ctx.restoreGState()

            let labelAttrsColored = labelAttrs.merging([.foregroundColor: threshold.color]) { $1 }
            let labelStr = NSAttributedString(string: threshold.label, attributes: labelAttrsColored)
            let labelSize = labelStr.size()
            let labelOrigin = CGPoint(x: rect.maxX - labelSize.width - 2, y: y - labelSize.height - 1)
            labelStr.draw(at: labelOrigin)
        }
    }

    private func drawWaveform(in rect: CGRect) {
        guard history.count >= 2 else { return }

        let path = UIBezierPath()
        path.lineWidth = 1.5

        let columnWidth = rect.width / CGFloat(max(history.count - 1, 1))

        for (i, value) in history.enumerated() {
            let x = rect.minX + CGFloat(i) * columnWidth
            let y = yPosition(for: value, in: rect)
            let point = CGPoint(x: x, y: y)
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        UIColor.white.setStroke()
        path.stroke()

        // Dot at most recent point
        if let last = history.last {
            let x = rect.minX + CGFloat(history.count - 1) * columnWidth
            let y = yPosition(for: last, in: rect)
            let r: CGFloat = 4
            let dotRect = CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)
            let dot = UIBezierPath(ovalIn: dotRect)
            UIColor.white.setFill()
            dot.fill()
        }
    }

    private func drawStats(in rect: CGRect) {
        let metricStr = currentMetric.map { String(format: "%.2f", $0) } ?? "--"
        let kneeCurrent = currentKneeFlexionDegrees.map { String(format: "%.0f", $0) } ?? "--"
        let hipCurrent = currentHipFlexionDegrees.map { String(format: "%.0f", $0) } ?? "--"
        let kneePair = "L\(formatOptionalDegrees(leftKneeFlexionDegrees))/R\(formatOptionalDegrees(rightKneeFlexionDegrees))"
        let hipPair = "L\(formatOptionalDegrees(leftHipFlexionDegrees))/R\(formatOptionalDegrees(rightHipFlexionDegrees))"
        let text = "metric: \(metricStr)   state: \(stateName)   reps: \(repCount)   tracked: \(trackedJointName)   joints: \(jointCount)\n" +
                   "knee: \(kneeCurrent)° (\(kneePair))  hip: \(hipCurrent)° (\(hipPair))\n" +
                   "bottom>= knee \(String(format: "%.0f", kneeBottomFlexionDegrees))° / hip \(String(format: "%.0f", hipBottomFlexionDegrees))°   lockout<= knee \(String(format: "%.0f", kneeLockoutFlexionDegrees))° / hip \(String(format: "%.0f", hipLockoutFlexionDegrees))°   amp: \(String(format: "%.2f", minAmplitude))"
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

    private func formatOptionalDegrees(_ value: CGFloat?) -> String {
        value.map { String(format: "%.0f°", $0) } ?? "--"
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
