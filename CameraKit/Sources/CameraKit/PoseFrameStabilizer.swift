import CoreGraphics
import Vision
import simd

public struct PoseStabilizationConfiguration: Sendable {
    public let emaAlpha2D: CGFloat
    public let emaAlpha3D: CGFloat
    public let maxHoldFrames2D: Int
    public let maxHoldFrames3D: Int
    public let max2DJump: CGFloat
    public let max3DJump: Float

    public init(
        emaAlpha2D: CGFloat = 0.85,
        emaAlpha3D: CGFloat = 1.0,
        maxHoldFrames2D: Int = 1,
        maxHoldFrames3D: Int = 0,
        max2DJump: CGFloat = 0.9,
        max3DJump: Float = 2.0
    ) {
        self.emaAlpha2D = min(1, max(0, emaAlpha2D))
        self.emaAlpha3D = min(1, max(0, emaAlpha3D))
        self.maxHoldFrames2D = max(0, maxHoldFrames2D)
        self.maxHoldFrames3D = max(0, maxHoldFrames3D)
        self.max2DJump = max(0.0001, max2DJump)
        self.max3DJump = max(0.0001, max3DJump)
    }
}

struct PoseStabilizerOutput: Sendable {
    let joints: [VNHumanBodyPose3DObservation.JointName: NormalizedPoint]
    let positions3D: [VNHumanBodyPose3DObservation.JointName: SIMD3<Float>]
    let diagnostics: PoseFrameDiagnostics
}

public struct PoseFrameStabilizer: Sendable {
    private struct Joint2DState: Sendable {
        var point: NormalizedPoint
        var missingFrames: Int
    }

    private struct Joint3DState: Sendable {
        var point: SIMD3<Float>
        var missingFrames: Int
    }

    private let configuration: PoseStabilizationConfiguration
    private var state2D: [VNHumanBodyPose3DObservation.JointName: Joint2DState] = [:]
    private var state3D: [VNHumanBodyPose3DObservation.JointName: Joint3DState] = [:]

    public init(configuration: PoseStabilizationConfiguration = PoseStabilizationConfiguration()) {
        self.configuration = configuration
    }

    mutating func stabilize(
        joints: [VNHumanBodyPose3DObservation.JointName: NormalizedPoint],
        positions3D: [VNHumanBodyPose3DObservation.JointName: SIMD3<Float>],
        observationConfidence: Float?
    ) -> PoseStabilizerOutput {
        let expected2DJointCount = state2D.count
        let expected3DJointCount = state3D.count

        let raw2DKeys = Set(joints.keys)
        let raw3DKeys = Set(positions3D.keys)
        let dropped2DJointCount = Set(state2D.keys).subtracting(raw2DKeys).count
        let dropped3DJointCount = Set(state3D.keys).subtracting(raw3DKeys).count

        var stabilized2D: [VNHumanBodyPose3DObservation.JointName: NormalizedPoint] = [:]
        stabilized2D.reserveCapacity(max(expected2DJointCount, joints.count))
        var stabilized3D: [VNHumanBodyPose3DObservation.JointName: SIMD3<Float>] = [:]
        stabilized3D.reserveCapacity(max(expected3DJointCount, positions3D.count))

        var held2DJointCount = 0
        var held3DJointCount = 0
        var clamped2DJointCount = 0
        var clamped3DJointCount = 0

        for joint in Set(state2D.keys).union(raw2DKeys) {
            if let raw = joints[joint] {
                if var existing = state2D[joint] {
                    var candidate = raw
                    if pointDistance(existing.point, raw) > configuration.max2DJump {
                        candidate = clampPointStep(
                            previous: existing.point,
                            next: raw,
                            maxStep: configuration.max2DJump
                        )
                        clamped2DJointCount += 1
                    }

                    let filtered = blend2D(
                        previous: existing.point,
                        current: candidate,
                        alpha: configuration.emaAlpha2D
                    )

                    existing.point = filtered
                    existing.missingFrames = 0
                    state2D[joint] = existing
                    stabilized2D[joint] = filtered
                } else {
                    state2D[joint] = Joint2DState(point: raw, missingFrames: 0)
                    stabilized2D[joint] = raw
                }
            } else if var existing = state2D[joint] {
                if existing.missingFrames < configuration.maxHoldFrames2D {
                    existing.missingFrames += 1
                    state2D[joint] = existing
                    stabilized2D[joint] = existing.point
                    held2DJointCount += 1
                } else {
                    state2D.removeValue(forKey: joint)
                }
            }
        }

        for joint in Set(state3D.keys).union(raw3DKeys) {
            if let raw = positions3D[joint] {
                if var existing = state3D[joint] {
                    var candidate = raw
                    if pointDistance(existing.point, raw) > configuration.max3DJump {
                        candidate = clampPointStep(
                            previous: existing.point,
                            next: raw,
                            maxStep: configuration.max3DJump
                        )
                        clamped3DJointCount += 1
                    }

                    let filtered = blend3D(
                        previous: existing.point,
                        current: candidate,
                        alpha: Float(configuration.emaAlpha3D)
                    )

                    existing.point = filtered
                    existing.missingFrames = 0
                    state3D[joint] = existing
                    stabilized3D[joint] = filtered
                } else {
                    state3D[joint] = Joint3DState(point: raw, missingFrames: 0)
                    stabilized3D[joint] = raw
                }
            } else if var existing = state3D[joint] {
                if existing.missingFrames < configuration.maxHoldFrames3D {
                    existing.missingFrames += 1
                    state3D[joint] = existing
                    stabilized3D[joint] = existing.point
                    held3DJointCount += 1
                } else {
                    state3D.removeValue(forKey: joint)
                }
            }
        }

        return PoseStabilizerOutput(
            joints: stabilized2D,
            positions3D: stabilized3D,
            diagnostics: PoseFrameDiagnostics(
                observationConfidence: observationConfidence,
                expected2DJointCount: expected2DJointCount,
                expected3DJointCount: expected3DJointCount,
                raw2DJointCount: joints.count,
                raw3DJointCount: positions3D.count,
                stabilized2DJointCount: stabilized2D.count,
                stabilized3DJointCount: stabilized3D.count,
                dropped2DJointCount: dropped2DJointCount,
                dropped3DJointCount: dropped3DJointCount,
                held2DJointCount: held2DJointCount,
                held3DJointCount: held3DJointCount,
                clamped2DJointCount: clamped2DJointCount,
                clamped3DJointCount: clamped3DJointCount
            )
        )
    }

    private func blend2D(
        previous: NormalizedPoint,
        current: NormalizedPoint,
        alpha: CGFloat
    ) -> NormalizedPoint {
        NormalizedPoint(
            x: previous.x + (current.x - previous.x) * alpha,
            y: previous.y + (current.y - previous.y) * alpha
        )
    }

    private func blend3D(
        previous: SIMD3<Float>,
        current: SIMD3<Float>,
        alpha: Float
    ) -> SIMD3<Float> {
        previous + (current - previous) * alpha
    }

    private func pointDistance(_ a: NormalizedPoint, _ b: NormalizedPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        return sqrt(dx * dx + dy * dy)
    }

    private func pointDistance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        simd_length(b - a)
    }

    private func clampPointStep(
        previous: NormalizedPoint,
        next: NormalizedPoint,
        maxStep: CGFloat
    ) -> NormalizedPoint {
        let dx = next.x - previous.x
        let dy = next.y - previous.y
        let distance = sqrt(dx * dx + dy * dy)
        guard distance > maxStep, distance > 0 else { return next }

        let scale = maxStep / distance
        return NormalizedPoint(
            x: previous.x + dx * scale,
            y: previous.y + dy * scale
        )
    }

    private func clampPointStep(
        previous: SIMD3<Float>,
        next: SIMD3<Float>,
        maxStep: Float
    ) -> SIMD3<Float> {
        let delta = next - previous
        let distance = simd_length(delta)
        guard distance > maxStep, distance > 0 else { return next }

        return previous + delta * (maxStep / distance)
    }
}
