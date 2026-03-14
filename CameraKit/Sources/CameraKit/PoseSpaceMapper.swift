//
//  PoseSpaceMapper.swift
//  CameraKit
//
//  Created by TechTurtle on 01/02/2026.
//

import Vision
import CoreGraphics
import AVFoundation

public struct NormalizedPoint: Sendable, Hashable {
    public let x: CGFloat
    public let y: CGFloat
}

public struct PoseFrame: Sendable {
    public let timestamp: CMTime
    public let joints: [VNHumanBodyPose3DObservation.JointName: NormalizedPoint]
}

public enum PoseSpaceMapper {
    public static func normalizedPosePoint(from visionPoint: CGPoint) -> NormalizedPoint {
        NormalizedPoint(x: 1 - visionPoint.y, y: 1 - visionPoint.x)
    }

    public static func extractNormalizedJoints(from obs: VNHumanBodyPose3DObservation) ->
    [VNHumanBodyPose3DObservation.JointName: NormalizedPoint] {
        var out: [VNHumanBodyPose3DObservation.JointName: NormalizedPoint] = [:]
        out.reserveCapacity(obs.availableJointNames.count)

        for joint in obs.availableJointNames {
            guard let p = try? obs.pointInImage(joint) else { continue }
            let np = normalizedPosePoint(from: p.location)
            guard (0...1).contains(np.x) && (0...1).contains(np.y) else { continue }
            out[joint] = np
        }
        return out
    }
}
