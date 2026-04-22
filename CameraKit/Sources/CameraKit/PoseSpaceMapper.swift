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

public struct PoseFrameDiagnostics: Sendable {
    public let observationConfidence: Float?
    public let expected2DJointCount: Int
    public let expected3DJointCount: Int
    public let raw2DJointCount: Int
    public let raw3DJointCount: Int
    public let stabilized2DJointCount: Int
    public let stabilized3DJointCount: Int
    public let dropped2DJointCount: Int
    public let dropped3DJointCount: Int
    public let held2DJointCount: Int
    public let held3DJointCount: Int
    public let clamped2DJointCount: Int
    public let clamped3DJointCount: Int

    public init(
        observationConfidence: Float? = nil,
        expected2DJointCount: Int = 0,
        expected3DJointCount: Int = 0,
        raw2DJointCount: Int = 0,
        raw3DJointCount: Int = 0,
        stabilized2DJointCount: Int = 0,
        stabilized3DJointCount: Int = 0,
        dropped2DJointCount: Int = 0,
        dropped3DJointCount: Int = 0,
        held2DJointCount: Int = 0,
        held3DJointCount: Int = 0,
        clamped2DJointCount: Int = 0,
        clamped3DJointCount: Int = 0
    ) {
        self.observationConfidence = observationConfidence
        self.expected2DJointCount = expected2DJointCount
        self.expected3DJointCount = expected3DJointCount
        self.raw2DJointCount = raw2DJointCount
        self.raw3DJointCount = raw3DJointCount
        self.stabilized2DJointCount = stabilized2DJointCount
        self.stabilized3DJointCount = stabilized3DJointCount
        self.dropped2DJointCount = dropped2DJointCount
        self.dropped3DJointCount = dropped3DJointCount
        self.held2DJointCount = held2DJointCount
        self.held3DJointCount = held3DJointCount
        self.clamped2DJointCount = clamped2DJointCount
        self.clamped3DJointCount = clamped3DJointCount
    }

    public static let empty = PoseFrameDiagnostics()
}

public struct PoseFrame: Sendable {
    public let timestamp: CMTime
    public let joints: [VNHumanBodyPose3DObservation.JointName: NormalizedPoint]
    public let positions3D: [VNHumanBodyPose3DObservation.JointName: SIMD3<Float>]
    public let diagnostics: PoseFrameDiagnostics

    public init(
        timestamp: CMTime,
        joints: [VNHumanBodyPose3DObservation.JointName: NormalizedPoint],
        positions3D: [VNHumanBodyPose3DObservation.JointName: SIMD3<Float>] = [:],
        diagnostics: PoseFrameDiagnostics = .empty
    ) {
        self.timestamp = timestamp
        self.joints = joints
        self.positions3D = positions3D
        self.diagnostics = diagnostics
    }
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

    public static func extract3DPositions(
        from obs: VNHumanBodyPose3DObservation
    ) -> [VNHumanBodyPose3DObservation.JointName: SIMD3<Float>] {
        var out: [VNHumanBodyPose3DObservation.JointName: SIMD3<Float>] = [:]
        out.reserveCapacity(obs.availableJointNames.count)

        for joint in obs.availableJointNames {
            guard let p = try? obs.recognizedPoint(joint) else { continue }
            let col3 = p.position.columns.3
            out[joint] = SIMD3<Float>(col3.x, col3.y, col3.z)
        }
        return out
    }
}
