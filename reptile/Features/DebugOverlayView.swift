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

    func updateConfiguration(_ configuration: RepCountingConfiguration) {
        descendEntryThreshold = configuration.squatDescendEntryThreshold
        bottomThreshold = configuration.downThreshold
        standLockoutThreshold = configuration.squatStandLockoutThreshold
        minAmplitude = configuration.minAmplitude
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
        let text = "metric: \(metricStr)   state: \(stateName)   tracked: \(trackedJointName)   joints: \(jointCount)   reps: \(repCount)   amp: \(String(format: "%.2f", minAmplitude))"
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.white,
            .font: UIFont.systemFont(ofSize: 13, weight: .regular),
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        let origin = CGPoint(
            x: rect.minX + (rect.width - size.width) / 2,
            y: rect.minY + (rect.height - size.height) / 2
        )
        str.draw(at: origin)
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
