import Foundation
import CoreGraphics
import Vision

/// Protocol for extracting movement metrics from a pose frame
public protocol MetricCalculator {
    func calculate(from frame: PoseFrame) -> CGFloat?
    func trackedJoints(from frame: PoseFrame) -> [VNHumanBodyPose3DObservation.JointName]
}

public extension MetricCalculator {
    func trackedJoints(from frame: PoseFrame) -> [VNHumanBodyPose3DObservation.JointName] {
        []
    }
}

/// Calculates distance from floor (bottom of screen) using best available joint
public struct DistanceFromFloorCalculator: MetricCalculator {
    public init() {}

    public func calculate(from frame: PoseFrame) -> CGFloat? {
        guard let selection = selectBestJoint(from: frame.joints) else { return nil }
        // PoseSpaceMapper swaps axes; vertical movement lives on `x` in this space.
        // Distance from floor should increase when moving up.
        return 1.0 - selection.point.x
    }

    public func trackedJoints(from frame: PoseFrame) -> [VNHumanBodyPose3DObservation.JointName] {
        selectBestJoint(from: frame.joints)?.jointNames ?? []
    }

    private struct JointSelection {
        let point: NormalizedPoint
        let jointNames: [VNHumanBodyPose3DObservation.JointName]
    }

    /// Selects best available joint with fallback strategy
    private func selectBestJoint(from joints: [VNHumanBodyPose3DObservation.JointName: NormalizedPoint]) -> JointSelection? {
        // Try root first (center of body - most stable)
        if let root = joints[.root] {
            return JointSelection(point: root, jointNames: [.root])
        }

        // Try average of hips (lower body exercises)
        if let leftHip = joints[.leftHip], let rightHip = joints[.rightHip] {
            return JointSelection(
                point: NormalizedPoint(
                    x: (leftHip.x + rightHip.x) / 2,
                    y: (leftHip.y + rightHip.y) / 2
                ),
                jointNames: [.leftHip, .rightHip]
            )
        }

        // Try single hip
        if let leftHip = joints[.leftHip] {
            return JointSelection(point: leftHip, jointNames: [.leftHip])
        }
        if let rightHip = joints[.rightHip] {
            return JointSelection(point: rightHip, jointNames: [.rightHip])
        }

        // Try average of shoulders (upper body exercises)
        if let leftShoulder = joints[.leftShoulder], let rightShoulder = joints[.rightShoulder] {
            return JointSelection(
                point: NormalizedPoint(
                    x: (leftShoulder.x + rightShoulder.x) / 2,
                    y: (leftShoulder.y + rightShoulder.y) / 2
                ),
                jointNames: [.leftShoulder, .rightShoulder]
            )
        }

        // Try single shoulder
        if let leftShoulder = joints[.leftShoulder] {
            return JointSelection(point: leftShoulder, jointNames: [.leftShoulder])
        }
        if let rightShoulder = joints[.rightShoulder] {
            return JointSelection(point: rightShoulder, jointNames: [.rightShoulder])
        }

        // Try average of wrists (arm-only exercises)
        if let leftWrist = joints[.leftWrist], let rightWrist = joints[.rightWrist] {
            return JointSelection(
                point: NormalizedPoint(
                    x: (leftWrist.x + rightWrist.x) / 2,
                    y: (leftWrist.y + rightWrist.y) / 2
                ),
                jointNames: [.leftWrist, .rightWrist]
            )
        }

        if let leftWrist = joints[.leftWrist] {
            return JointSelection(point: leftWrist, jointNames: [.leftWrist])
        }
        if let rightWrist = joints[.rightWrist] {
            return JointSelection(point: rightWrist, jointNames: [.rightWrist])
        }

        // Last resort: any available joint
        guard let fallback = joints.first else { return nil }
        return JointSelection(point: fallback.value, jointNames: [fallback.key])
    }
}

/// Tracks the joint with strongest sustained motion along the global dominant axis.
///
/// This is exercise-agnostic: for each frame, it estimates the dominant motion axis
/// from recent joint deltas, then selects the joint with the highest projected
/// movement energy along that axis. Hysteresis avoids rapid joint flapping.
public final class AdaptiveDominantAxisCalculator: MetricCalculator {
    private struct Axis {
        var x: CGFloat
        var y: CGFloat

        static let vertical = Axis(x: 1, y: 0)
    }

    private let energySmoothing: CGFloat
    private let covarianceSmoothing: CGFloat
    private let switchMargin: CGFloat
    private let switchConfirmationFrames: Int
    private let metricWindowSize: Int
    private let minNormalizationRange: CGFloat
    private let orthogonalPenalty: CGFloat
    private let minScoreGain: CGFloat
    private let energyDecay: CGFloat

    private var previousPoints: [VNHumanBodyPose3DObservation.JointName: NormalizedPoint] = [:]
    private var jointScores: [VNHumanBodyPose3DObservation.JointName: CGFloat] = [:]

    private var selectedJoint: VNHumanBodyPose3DObservation.JointName?
    private var pendingJoint: VNHumanBodyPose3DObservation.JointName?
    private var pendingJointFrames: Int = 0

    private var dominantAxis: Axis = .vertical
    private var covarianceXX: CGFloat = 0
    private var covarianceXY: CGFloat = 0
    private var covarianceYY: CGFloat = 0

    private var projectionWindow: [CGFloat] = []
    private var lastMetric: CGFloat = 0.5

    public init(
        energySmoothing: CGFloat = 0.35,
        covarianceSmoothing: CGFloat = 0.25,
        switchMargin: CGFloat = 1.20,
        switchConfirmationFrames: Int = 4,
        metricWindowSize: Int = 90,
        minNormalizationRange: CGFloat = 0.08,
        orthogonalPenalty: CGFloat = 0.35,
        minScoreGain: CGFloat = 0.01,
        energyDecay: CGFloat = 0.97
    ) {
        self.energySmoothing = energySmoothing
        self.covarianceSmoothing = covarianceSmoothing
        self.switchMargin = switchMargin
        self.switchConfirmationFrames = max(1, switchConfirmationFrames)
        self.metricWindowSize = max(15, metricWindowSize)
        self.minNormalizationRange = max(0.01, minNormalizationRange)
        self.orthogonalPenalty = max(0, orthogonalPenalty)
        self.minScoreGain = max(0, minScoreGain)
        self.energyDecay = min(max(0, energyDecay), 1)
    }

    public func calculate(from frame: PoseFrame) -> CGFloat? {
        let joints = frame.joints
        guard !joints.isEmpty else { return nil }

        let deltas = frameDeltas(from: joints)
        previousPoints = joints

        updateDominantAxis(with: deltas)
        updateJointScores(with: deltas)
        updateSelection(using: joints)

        guard let selectedJoint, let point = joints[selectedJoint] else { return nil }

        let projection = point.x * dominantAxis.x + point.y * dominantAxis.y
        projectionWindow.append(projection)
        if projectionWindow.count > metricWindowSize {
            projectionWindow.removeFirst()
        }

        guard let minProjection = projectionWindow.min(),
              let maxProjection = projectionWindow.max() else {
            return nil
        }

        let range = maxProjection - minProjection
        guard range >= minNormalizationRange else {
            return lastMetric
        }

        let normalized = (projection - minProjection) / range
        let clamped = min(1, max(0, normalized))
        lastMetric = clamped
        return clamped
    }

    public func trackedJoints(from frame: PoseFrame) -> [VNHumanBodyPose3DObservation.JointName] {
        guard let selectedJoint, frame.joints[selectedJoint] != nil else { return [] }
        return [selectedJoint]
    }

    private func frameDeltas(
        from joints: [VNHumanBodyPose3DObservation.JointName: NormalizedPoint]
    ) -> [VNHumanBodyPose3DObservation.JointName: (dx: CGFloat, dy: CGFloat)] {
        var deltas: [VNHumanBodyPose3DObservation.JointName: (dx: CGFloat, dy: CGFloat)] = [:]
        deltas.reserveCapacity(joints.count)

        for (joint, point) in joints {
            guard let previous = previousPoints[joint] else { continue }
            deltas[joint] = (dx: point.x - previous.x, dy: point.y - previous.y)
        }

        return deltas
    }

    private func updateDominantAxis(
        with deltas: [VNHumanBodyPose3DObservation.JointName: (dx: CGFloat, dy: CGFloat)]
    ) {
        guard !deltas.isEmpty else { return }

        var frameXX: CGFloat = 0
        var frameXY: CGFloat = 0
        var frameYY: CGFloat = 0

        for delta in deltas.values {
            frameXX += delta.dx * delta.dx
            frameXY += delta.dx * delta.dy
            frameYY += delta.dy * delta.dy
        }

        covarianceXX = covarianceSmoothing * frameXX + (1 - covarianceSmoothing) * covarianceXX
        covarianceXY = covarianceSmoothing * frameXY + (1 - covarianceSmoothing) * covarianceXY
        covarianceYY = covarianceSmoothing * frameYY + (1 - covarianceSmoothing) * covarianceYY

        let candidate = principalAxis(xx: covarianceXX, xy: covarianceXY, yy: covarianceYY)
        let aligned = alignAxis(candidate, to: dominantAxis)
        dominantAxis = aligned
    }

    private func updateJointScores(
        with deltas: [VNHumanBodyPose3DObservation.JointName: (dx: CGFloat, dy: CGFloat)]
    ) {
        for key in jointScores.keys {
            jointScores[key] = (jointScores[key] ?? 0) * energyDecay
        }

        for (joint, delta) in deltas {
            let projected = abs(delta.dx * dominantAxis.x + delta.dy * dominantAxis.y)
            let orthogonal = abs(-delta.dx * dominantAxis.y + delta.dy * dominantAxis.x)
            let signal = max(0, projected - orthogonalPenalty * orthogonal)

            let previousScore = jointScores[joint] ?? signal
            jointScores[joint] = energySmoothing * signal + (1 - energySmoothing) * previousScore
        }
    }

    private func updateSelection(
        using joints: [VNHumanBodyPose3DObservation.JointName: NormalizedPoint]
    ) {
        guard let bestJoint = bestJoint(in: joints.keys) else {
            selectedJoint = nil
            pendingJoint = nil
            pendingJointFrames = 0
            projectionWindow.removeAll()
            return
        }

        guard let currentJoint = selectedJoint,
              joints[currentJoint] != nil else {
            setSelectedJoint(bestJoint)
            return
        }

        guard bestJoint != currentJoint else {
            pendingJoint = nil
            pendingJointFrames = 0
            return
        }

        let currentScore = jointScores[currentJoint] ?? 0
        let challengerScore = jointScores[bestJoint] ?? 0
        let switchThreshold = max(currentScore * switchMargin, currentScore + minScoreGain)

        guard challengerScore > switchThreshold else {
            pendingJoint = nil
            pendingJointFrames = 0
            return
        }

        if pendingJoint == bestJoint {
            pendingJointFrames += 1
        } else {
            pendingJoint = bestJoint
            pendingJointFrames = 1
        }

        if pendingJointFrames >= switchConfirmationFrames {
            setSelectedJoint(bestJoint)
        }
    }

    private func setSelectedJoint(_ joint: VNHumanBodyPose3DObservation.JointName) {
        selectedJoint = joint
        pendingJoint = nil
        pendingJointFrames = 0
        projectionWindow.removeAll()
    }

    private func bestJoint(
        in joints: Dictionary<VNHumanBodyPose3DObservation.JointName, NormalizedPoint>.Keys
    ) -> VNHumanBodyPose3DObservation.JointName? {
        joints.max { lhs, rhs in
            (jointScores[lhs] ?? 0) < (jointScores[rhs] ?? 0)
        }
    }

    private func principalAxis(xx: CGFloat, xy: CGFloat, yy: CGFloat) -> Axis {
        let trace = xx + yy
        let discriminant = sqrt(max(0, (xx - yy) * (xx - yy) + 4 * xy * xy))
        let lambda = 0.5 * (trace + discriminant)

        let vx = lambda - yy
        let vy = xy
        return normalizedAxis(x: vx, y: vy) ?? .vertical
    }

    private func alignAxis(_ candidate: Axis, to reference: Axis) -> Axis {
        let dot = candidate.x * reference.x + candidate.y * reference.y
        if dot >= 0 {
            return candidate
        }
        return Axis(x: -candidate.x, y: -candidate.y)
    }

    private func normalizedAxis(x: CGFloat, y: CGFloat) -> Axis? {
        let magnitude = sqrt(x * x + y * y)
        guard magnitude > 0.0001 else { return nil }
        return Axis(x: x / magnitude, y: y / magnitude)
    }
}

/// Squat-specific depth metric using coordinated lower-body joints.
///
/// Metric is normalized to roughly `0` (standing) ... `1` (deep squat).
/// It combines hip depth with knee flexion when enough joints are available.
public final class SquatDepthMetricCalculator: MetricCalculator {
    private let standingDepthReference: CGFloat
    private let bottomDepthReference: CGFloat
    private let hipWeight: CGFloat
    private let kneeWeight: CGFloat
    private let maxHipSymmetryDelta: CGFloat

    private var rawHipDepthWindow: [CGFloat] = []
    private let windowCapacity = 300
    private let minNormalizationRange: CGFloat = 0.08

    public init(
        standingDepthReference: CGFloat = 0.52,
        bottomDepthReference: CGFloat = 0.74,
        hipWeight: CGFloat = 0.72,
        kneeWeight: CGFloat = 0.28,
        maxHipSymmetryDelta: CGFloat = 0.14
    ) {
        self.standingDepthReference = standingDepthReference
        self.bottomDepthReference = max(bottomDepthReference, standingDepthReference + 0.05)
        self.hipWeight = max(0, min(1, hipWeight))
        self.kneeWeight = max(0, min(1, kneeWeight))
        self.maxHipSymmetryDelta = max(0, maxHipSymmetryDelta)
    }

    public func calculate(from frame: PoseFrame) -> CGFloat? {
        let joints = frame.joints
        guard let body = bodyPoints(from: joints) else { return nil }

        if let leftHip = joints[.leftHip],
           let rightHip = joints[.rightHip],
           abs(leftHip.x - rightHip.x) > maxHipSymmetryDelta {
            return nil
        }

        rawHipDepthWindow.append(body.hipDepth)
        if rawHipDepthWindow.count > windowCapacity { rawHipDepthWindow.removeFirst() }

        let windowMin = rawHipDepthWindow.min() ?? standingDepthReference
        let windowMax = rawHipDepthWindow.max() ?? bottomDepthReference
        let range = windowMax - windowMin

        let refMin: CGFloat
        let refMax: CGFloat
        if range >= minNormalizationRange {
            refMin = windowMin
            refMax = windowMax
        } else {
            refMin = standingDepthReference
            refMax = bottomDepthReference
        }

        let hipDepth = normalize(value: body.hipDepth, lower: refMin, upper: refMax)

        if let kneeDepth = body.kneeDepth {
            let weighted = hipWeight * hipDepth + kneeWeight * kneeDepth
            return clamp(weighted)
        }

        return clamp(hipDepth)
    }

    public func trackedJoints(
        from frame: PoseFrame
    ) -> [VNHumanBodyPose3DObservation.JointName] {
        guard let body = bodyPoints(from: frame.joints) else { return [] }
        return body.tracked
    }

    private struct BodyPoints {
        let hipDepth: CGFloat
        let kneeDepth: CGFloat?
        let tracked: [VNHumanBodyPose3DObservation.JointName]
    }

    private func bodyPoints(
        from joints: [VNHumanBodyPose3DObservation.JointName: NormalizedPoint]
    ) -> BodyPoints? {
        guard let shoulder = average(
            joints[.leftShoulder],
            joints[.rightShoulder],
            fallback: joints[.spine] ?? joints[.root]
        ) else {
            return nil
        }

        guard let hip = average(joints[.leftHip], joints[.rightHip], fallback: joints[.root]) else {
            return nil
        }

        // Use real ankles if available; fall back to a knee-based estimate when
        // ankles are out of frame (common when camera is at chest/table height).
        // shoulder→ankle ≈ 1.5 × shoulder→knee by body proportion.
        let ankle: NormalizedPoint
        if let detected = average(joints[.leftAnkle], joints[.rightAnkle], fallback: nil) {
            ankle = detected
        } else if let knee = average(joints[.leftKnee], joints[.rightKnee], fallback: nil) {
            let kneeDistance = knee.x - shoulder.x
            ankle = NormalizedPoint(x: shoulder.x + kneeDistance * 1.5, y: knee.y)
        } else {
            return nil
        }

        let scale = ankle.x - shoulder.x
        guard scale > 0.05 else { return nil }

        let hipDepth = (hip.x - shoulder.x) / scale
        let kneeDepth = blendedKneeDepth(from: joints)

        var tracked: [VNHumanBodyPose3DObservation.JointName] = []
        tracked.append(contentsOf: available(in: joints, names: [.leftShoulder, .rightShoulder, .spine, .root]))
        tracked.append(contentsOf: available(in: joints, names: [.leftHip, .rightHip]))
        tracked.append(contentsOf: available(in: joints, names: [.leftKnee, .rightKnee]))
        tracked.append(contentsOf: available(in: joints, names: [.leftAnkle, .rightAnkle]))

        return BodyPoints(hipDepth: hipDepth, kneeDepth: kneeDepth, tracked: tracked)
    }

    private func blendedKneeDepth(
        from joints: [VNHumanBodyPose3DObservation.JointName: NormalizedPoint]
    ) -> CGFloat? {
        var depths: [CGFloat] = []
        depths.reserveCapacity(2)

        if let d = kneeDepth(hip: joints[.leftHip], knee: joints[.leftKnee], ankle: joints[.leftAnkle]) {
            depths.append(d)
        }
        if let d = kneeDepth(hip: joints[.rightHip], knee: joints[.rightKnee], ankle: joints[.rightAnkle]) {
            depths.append(d)
        }

        guard !depths.isEmpty else { return nil }
        return depths.reduce(0, +) / CGFloat(depths.count)
    }

    private func kneeDepth(
        hip: NormalizedPoint?,
        knee: NormalizedPoint?,
        ankle: NormalizedPoint?
    ) -> CGFloat? {
        guard let hip, let knee, let ankle else { return nil }
        guard let angle = kneeAngle(hip: hip, knee: knee, ankle: ankle) else { return nil }

        // Standing knees are near ~170-180 deg, deep squat is typically near ~90-100 deg.
        let standingAngle: CGFloat = 170
        let deepAngle: CGFloat = 95
        return normalize(value: standingAngle - angle, lower: 0, upper: standingAngle - deepAngle)
    }

    private func kneeAngle(hip: NormalizedPoint, knee: NormalizedPoint, ankle: NormalizedPoint) -> CGFloat? {
        let thigh = CGVector(dx: hip.x - knee.x, dy: hip.y - knee.y)
        let shin = CGVector(dx: ankle.x - knee.x, dy: ankle.y - knee.y)

        let thighLength = sqrt(thigh.dx * thigh.dx + thigh.dy * thigh.dy)
        let shinLength = sqrt(shin.dx * shin.dx + shin.dy * shin.dy)
        guard thighLength > 0.0001, shinLength > 0.0001 else { return nil }

        let dot = thigh.dx * shin.dx + thigh.dy * shin.dy
        let cosine = max(-1, min(1, dot / (thighLength * shinLength)))
        return acos(cosine) * 180 / .pi
    }

    private func average(
        _ first: NormalizedPoint?,
        _ second: NormalizedPoint?,
        fallback: NormalizedPoint?
    ) -> NormalizedPoint? {
        if let first, let second {
            return NormalizedPoint(
                x: (first.x + second.x) / 2,
                y: (first.y + second.y) / 2
            )
        }

        if let first {
            return first
        }
        if let second {
            return second
        }
        return fallback
    }

    private func available(
        in joints: [VNHumanBodyPose3DObservation.JointName: NormalizedPoint],
        names: [VNHumanBodyPose3DObservation.JointName]
    ) -> [VNHumanBodyPose3DObservation.JointName] {
        names.filter { joints[$0] != nil }
    }

    private func normalize(value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        let range = max(upper - lower, 0.0001)
        return (value - lower) / range
    }

    private func clamp(_ value: CGFloat) -> CGFloat {
        min(1, max(0, value))
    }
}

/// Squat depth metric using true 3D camera-space joint positions.
///
/// Computes `(shoulder.y - hip.y) / (shoulder.y - ankle.y)` in camera-space
/// metres (Vision Y-axis = up in portrait mode). This ratio is invariant to the
/// user's distance from the camera — it measures actual body geometry, not the
/// 2D projection.
///
/// The raw ratio is adaptively normalised to `0` (standing) … `1` (deep squat)
/// using a sliding window of observed values, so the output range matches the
/// conventions expected by `SquatPhaseRepCounter`.
public final class SquatDepth3DMetricCalculator: MetricCalculator {
    private let standingReference: Float
    private let deepSquatReference: Float
    private let minScaleMeters: Float
    private let minNormalizationRange: CGFloat

    private var rawMetricWindow: [CGFloat] = []
    private let windowCapacity = 300

    public init(
        standingReference: Float = 0.40,
        deepSquatReference: Float = 0.75,
        minScaleMeters: Float = 0.20,
        minNormalizationRange: CGFloat = 0.08
    ) {
        self.standingReference = standingReference
        self.deepSquatReference = deepSquatReference
        self.minScaleMeters = minScaleMeters
        self.minNormalizationRange = minNormalizationRange
    }

    public func calculate(from frame: PoseFrame) -> CGFloat? {
        let p = frame.positions3D
        guard
            let shoulderY = averageY(p[.leftShoulder], p[.rightShoulder], fallback: p[.spine] ?? p[.root]),
            let hipY      = averageY(p[.leftHip],      p[.rightHip],      fallback: p[.root]),
            let ankleY    = resolvedAnkleY(from: p)
        else { return nil }

        let scale = shoulderY - ankleY
        guard scale > minScaleMeters else { return nil }

        let rawMetric = CGFloat((shoulderY - hipY) / scale)

        rawMetricWindow.append(rawMetric)
        if rawMetricWindow.count > windowCapacity { rawMetricWindow.removeFirst() }

        let windowMin = rawMetricWindow.min() ?? CGFloat(standingReference)
        let windowMax = rawMetricWindow.max() ?? CGFloat(deepSquatReference)
        let range = windowMax - windowMin

        let refMin: CGFloat
        let refMax: CGFloat
        if range >= minNormalizationRange {
            refMin = windowMin
            refMax = windowMax
        } else {
            refMin = CGFloat(standingReference)
            refMax = CGFloat(deepSquatReference)
        }

        let normalized = (rawMetric - refMin) / max(refMax - refMin, 0.0001)
        return min(1, max(0, normalized))
    }

    public func trackedJoints(from frame: PoseFrame) -> [VNHumanBodyPose3DObservation.JointName] {
        let p = frame.positions3D
        var tracked: [VNHumanBodyPose3DObservation.JointName] = []
        tracked.append(contentsOf: available(in: p, names: [.leftShoulder, .rightShoulder, .spine, .root]))
        tracked.append(contentsOf: available(in: p, names: [.leftHip, .rightHip]))
        tracked.append(contentsOf: available(in: p, names: [.leftKnee, .rightKnee]))
        tracked.append(contentsOf: available(in: p, names: [.leftAnkle, .rightAnkle]))
        return tracked
    }

    private func averageY(
        _ a: SIMD3<Float>?,
        _ b: SIMD3<Float>?,
        fallback: SIMD3<Float>?
    ) -> Float? {
        if let a, let b { return (a.y + b.y) / 2 }
        return (a ?? b ?? fallback).map { $0.y }
    }

    /// Returns the Y position of the ankles. When ankles are out of frame,
    /// estimates using 1.5× the hip-to-knee segment length below the hip.
    private func resolvedAnkleY(
        from p: [VNHumanBodyPose3DObservation.JointName: SIMD3<Float>]
    ) -> Float? {
        if let detected = averageY(p[.leftAnkle], p[.rightAnkle], fallback: nil) {
            return detected
        }
        guard
            let hipY  = averageY(p[.leftHip],  p[.rightHip],  fallback: p[.root]),
            let kneeY = averageY(p[.leftKnee], p[.rightKnee], fallback: nil)
        else { return nil }
        return hipY - (hipY - kneeY) * 1.5
    }

    private func available(
        in p: [VNHumanBodyPose3DObservation.JointName: SIMD3<Float>],
        names: [VNHumanBodyPose3DObservation.JointName]
    ) -> [VNHumanBodyPose3DObservation.JointName] {
        names.filter { p[$0] != nil }
    }
}
