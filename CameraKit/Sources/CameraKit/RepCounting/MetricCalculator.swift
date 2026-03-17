import Foundation
import Vision

/// Protocol for extracting movement metrics from pose joints
public protocol MetricCalculator {
    func calculate(from joints: [VNHumanBodyPose3DObservation.JointName: NormalizedPoint]) -> CGFloat?
    func trackedJoints(from joints: [VNHumanBodyPose3DObservation.JointName: NormalizedPoint]) -> [VNHumanBodyPose3DObservation.JointName]
}

public extension MetricCalculator {
    func trackedJoints(from joints: [VNHumanBodyPose3DObservation.JointName: NormalizedPoint]) -> [VNHumanBodyPose3DObservation.JointName] {
        []
    }
}

/// Calculates distance from floor (bottom of screen) using best available joint
public struct DistanceFromFloorCalculator: MetricCalculator {
    public init() {}

    public func calculate(from joints: [VNHumanBodyPose3DObservation.JointName: NormalizedPoint]) -> CGFloat? {
        guard let selection = selectBestJoint(from: joints) else { return nil }
        // PoseSpaceMapper swaps axes; vertical movement lives on `x` in this space.
        // Distance from floor should increase when moving up.
        return 1.0 - selection.point.x
    }

    public func trackedJoints(from joints: [VNHumanBodyPose3DObservation.JointName: NormalizedPoint]) -> [VNHumanBodyPose3DObservation.JointName] {
        selectBestJoint(from: joints)?.jointNames ?? []
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

    public func calculate(from joints: [VNHumanBodyPose3DObservation.JointName: NormalizedPoint]) -> CGFloat? {
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

    public func trackedJoints(from joints: [VNHumanBodyPose3DObservation.JointName: NormalizedPoint]) -> [VNHumanBodyPose3DObservation.JointName] {
        guard let selectedJoint, joints[selectedJoint] != nil else { return [] }
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
