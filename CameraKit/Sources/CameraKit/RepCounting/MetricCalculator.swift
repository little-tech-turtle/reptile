import Foundation
import Vision

/// Protocol for extracting movement metrics from pose joints
public protocol MetricCalculator {
    func calculate(from joints: [VNHumanBodyPose3DObservation.JointName: NormalizedPoint]) -> CGFloat?
}

/// Calculates distance from floor (bottom of screen) using best available joint
public struct DistanceFromFloorCalculator: MetricCalculator {
    public init() {}

    public func calculate(from joints: [VNHumanBodyPose3DObservation.JointName: NormalizedPoint]) -> CGFloat? {
        guard let point = selectBestJoint(from: joints) else { return nil }
        // Distance from floor (y=1.0 is bottom, y=0.0 is top)
        return 1.0 - point.y
    }

    /// Selects best available joint with fallback strategy
    private func selectBestJoint(from joints: [VNHumanBodyPose3DObservation.JointName: NormalizedPoint]) -> NormalizedPoint? {
        // Try root first (center of body - most stable)
        if let root = joints[.root] { return root }

        // Try average of hips (lower body exercises)
        if let leftHip = joints[.leftHip], let rightHip = joints[.rightHip] {
            return NormalizedPoint(
                x: (leftHip.x + rightHip.x) / 2,
                y: (leftHip.y + rightHip.y) / 2
            )
        }

        // Try single hip
        if let hip = joints[.leftHip] ?? joints[.rightHip] { return hip }

        // Try average of shoulders (upper body exercises)
        if let leftShoulder = joints[.leftShoulder], let rightShoulder = joints[.rightShoulder] {
            return NormalizedPoint(
                x: (leftShoulder.x + rightShoulder.x) / 2,
                y: (leftShoulder.y + rightShoulder.y) / 2
            )
        }

        // Try single shoulder
        if let shoulder = joints[.leftShoulder] ?? joints[.rightShoulder] { return shoulder }

        // Try average of wrists (arm-only exercises)
        if let leftWrist = joints[.leftWrist], let rightWrist = joints[.rightWrist] {
            return NormalizedPoint(
                x: (leftWrist.x + rightWrist.x) / 2,
                y: (leftWrist.y + rightWrist.y) / 2
            )
        }

        // Last resort: any available joint
        return joints.values.first
    }
}
