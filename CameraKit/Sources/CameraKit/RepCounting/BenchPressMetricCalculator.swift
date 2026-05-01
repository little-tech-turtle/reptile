import CoreGraphics
import Foundation
import Vision
import simd

public struct BenchPressFlexionMetrics: Sendable {
    public let elbowFlexionDegrees: CGFloat?
    public let shoulderFlexionDegrees: CGFloat?
    public let leftElbowFlexionDegrees: CGFloat?
    public let rightElbowFlexionDegrees: CGFloat?
    public let leftShoulderFlexionDegrees: CGFloat?
    public let rightShoulderFlexionDegrees: CGFloat?
    public let activeSide: CurlActiveSide?

    public init(
        elbowFlexionDegrees: CGFloat?,
        shoulderFlexionDegrees: CGFloat?,
        leftElbowFlexionDegrees: CGFloat?,
        rightElbowFlexionDegrees: CGFloat?,
        leftShoulderFlexionDegrees: CGFloat?,
        rightShoulderFlexionDegrees: CGFloat?,
        activeSide: CurlActiveSide?
    ) {
        self.elbowFlexionDegrees = elbowFlexionDegrees
        self.shoulderFlexionDegrees = shoulderFlexionDegrees
        self.leftElbowFlexionDegrees = leftElbowFlexionDegrees
        self.rightElbowFlexionDegrees = rightElbowFlexionDegrees
        self.leftShoulderFlexionDegrees = leftShoulderFlexionDegrees
        self.rightShoulderFlexionDegrees = rightShoulderFlexionDegrees
        self.activeSide = activeSide
    }
}

public final class BenchPressFlexion3DMetricCalculator: MetricCalculator, ExerciseDiagnosticsProvider {
    private let benchBottomElbowFlexionDegrees: CGFloat
    private let benchBottomShoulderFlexionDegrees: CGFloat
    private let benchLockoutElbowFlexionDegrees: CGFloat
    private let benchLockoutShoulderFlexionDegrees: CGFloat
    private var lockedSide: Side?

    public init(
        benchBottomElbowFlexionDegrees: CGFloat = 45,
        benchBottomShoulderFlexionDegrees: CGFloat = 45,
        benchLockoutElbowFlexionDegrees: CGFloat = 12,
        benchLockoutShoulderFlexionDegrees: CGFloat = 12
    ) {
        self.benchBottomElbowFlexionDegrees = max(
            benchBottomElbowFlexionDegrees,
            benchLockoutElbowFlexionDegrees + 5
        )
        self.benchBottomShoulderFlexionDegrees = max(
            benchBottomShoulderFlexionDegrees,
            benchLockoutShoulderFlexionDegrees + 5
        )
        self.benchLockoutElbowFlexionDegrees = max(0, benchLockoutElbowFlexionDegrees)
        self.benchLockoutShoulderFlexionDegrees = max(0, benchLockoutShoulderFlexionDegrees)
    }

    public func calculate(from frame: PoseFrame) -> CGFloat? {
        guard let metrics = flexionMetrics(from: frame),
              let elbowFlexion = metrics.elbowFlexionDegrees else {
            return nil
        }

        return clamp(normalize(
            value: elbowFlexion,
            lower: benchLockoutElbowFlexionDegrees,
            upper: benchBottomElbowFlexionDegrees
        ))
    }

    public func trackedJoints(from frame: PoseFrame) -> [VNHumanBodyPose3DObservation.JointName] {
        guard let metrics = flexionMetrics(from: frame) else { return [] }

        let points = frame.positions3D
        var joints: [VNHumanBodyPose3DObservation.JointName] = []

        switch metrics.activeSide {
        case .left:
            joints.append(contentsOf: available(in: points, names: [.leftShoulder, .leftElbow, .leftWrist]))
        case .right:
            joints.append(contentsOf: available(in: points, names: [.rightShoulder, .rightElbow, .rightWrist]))
        case .both:
            joints.append(contentsOf: available(in: points, names: [.leftShoulder, .leftElbow, .leftWrist, .rightShoulder, .rightElbow, .rightWrist]))
        case nil:
            break
        }

        return unique(joints)
    }

    public func flexionMetrics(from frame: PoseFrame) -> BenchPressFlexionMetrics? {
        let points = frame.positions3D

        let leftElbow = elbowFlexion(for: .left, points: points)
        let rightElbow = elbowFlexion(for: .right, points: points)
        let leftShoulder = shoulderFlexion(for: .left, points: points)
        let rightShoulder = shoulderFlexion(for: .right, points: points)

        let selection = selectActiveSide(left: leftElbow, right: rightElbow)

        guard leftElbow != nil || rightElbow != nil || leftShoulder != nil || rightShoulder != nil else {
            return nil
        }

        return BenchPressFlexionMetrics(
            elbowFlexionDegrees: selection.elbowFlexion,
            shoulderFlexionDegrees: average(leftShoulder, rightShoulder),
            leftElbowFlexionDegrees: leftElbow,
            rightElbowFlexionDegrees: rightElbow,
            leftShoulderFlexionDegrees: leftShoulder,
            rightShoulderFlexionDegrees: rightShoulder,
            activeSide: selection.active
        )
    }

    public func diagnostics(from frame: PoseFrame) -> ExerciseDiagnostics? {
        guard let metrics = flexionMetrics(from: frame) else { return nil }

        var scalars: [String: Double] = [:]
        if let value = metrics.elbowFlexionDegrees {
            scalars["bench.elbowFlexionDegrees"] = Double(value)
        }
        if let value = metrics.shoulderFlexionDegrees {
            scalars["bench.shoulderFlexionDegrees"] = Double(value)
        }
        if let value = metrics.leftElbowFlexionDegrees {
            scalars["bench.leftElbowFlexionDegrees"] = Double(value)
        }
        if let value = metrics.rightElbowFlexionDegrees {
            scalars["bench.rightElbowFlexionDegrees"] = Double(value)
        }
        if let value = metrics.leftShoulderFlexionDegrees {
            scalars["bench.leftShoulderFlexionDegrees"] = Double(value)
        }
        if let value = metrics.rightShoulderFlexionDegrees {
            scalars["bench.rightShoulderFlexionDegrees"] = Double(value)
        }

        var labels: [String: String] = [:]
        if let activeSide = metrics.activeSide?.rawValue {
            labels["bench.activeSide"] = activeSide
        }

        return ExerciseDiagnostics(scalars: scalars, labels: labels)
    }

    private enum Side {
        case left
        case right
    }

    private struct SideSelection {
        let active: CurlActiveSide?
        let elbowFlexion: CGFloat?
    }

    private func selectActiveSide(left: CGFloat?, right: CGFloat?) -> SideSelection {
        if let lockedSide {
            let lockedValue = value(for: lockedSide, left: left, right: right)
            if let lockedValue, lockedValue > benchLockoutElbowFlexionDegrees {
                return SideSelection(active: activeSide(for: lockedSide), elbowFlexion: lockedValue)
            }
            self.lockedSide = nil
        }

        switch (left, right) {
        case let (l?, r?):
            if l == r {
                return SideSelection(active: .both, elbowFlexion: (l + r) / 2)
            }
            if l > r {
                if l >= benchLockoutElbowFlexionDegrees + 1 { lockedSide = .left }
                return SideSelection(active: .left, elbowFlexion: l)
            }
            if r >= benchLockoutElbowFlexionDegrees + 1 { lockedSide = .right }
            return SideSelection(active: .right, elbowFlexion: r)
        case let (l?, nil):
            if l >= benchLockoutElbowFlexionDegrees + 1 { lockedSide = .left }
            return SideSelection(active: .left, elbowFlexion: l)
        case let (nil, r?):
            if r >= benchLockoutElbowFlexionDegrees + 1 { lockedSide = .right }
            return SideSelection(active: .right, elbowFlexion: r)
        default:
            return SideSelection(active: nil, elbowFlexion: nil)
        }
    }

    private func value(for side: Side, left: CGFloat?, right: CGFloat?) -> CGFloat? {
        switch side {
        case .left:
            return left
        case .right:
            return right
        }
    }

    private func activeSide(for side: Side) -> CurlActiveSide {
        switch side {
        case .left:
            return .left
        case .right:
            return .right
        }
    }

    private func elbowFlexion(
        for side: Side,
        points: [VNHumanBodyPose3DObservation.JointName: SIMD3<Float>]
    ) -> CGFloat? {
        let joints = armJoints(side)
        guard let shoulder = points[joints.shoulder],
              let elbow = points[joints.elbow],
              let wrist = points[joints.wrist],
              let angle = jointAngle(a: shoulder, vertex: elbow, b: wrist) else {
            return nil
        }

        return clampDegrees(180 - angle)
    }

    private func shoulderFlexion(
        for side: Side,
        points: [VNHumanBodyPose3DObservation.JointName: SIMD3<Float>]
    ) -> CGFloat? {
        let joints = armJoints(side)
        guard let shoulder = points[joints.shoulder],
              let elbow = points[joints.elbow] else {
            return nil
        }

        if let torsoAnchor = points[joints.hip] ?? points[.spine] ?? points[.root],
           let angle = jointAngle(a: torsoAnchor, vertex: shoulder, b: elbow) {
            return clampDegrees(angle)
        }

        if let oppositeShoulder = points[oppositeShoulderName(for: side)],
           let inferred = shoulderFlexionFromShoulderLine(
               shoulder: shoulder,
               elbow: elbow,
               oppositeShoulder: oppositeShoulder
           ) {
            return inferred
        }

        return nil
    }

    private func armJoints(
        _ side: Side
    ) -> (
        shoulder: VNHumanBodyPose3DObservation.JointName,
        elbow: VNHumanBodyPose3DObservation.JointName,
        wrist: VNHumanBodyPose3DObservation.JointName,
        hip: VNHumanBodyPose3DObservation.JointName
    ) {
        switch side {
        case .left:
            return (.leftShoulder, .leftElbow, .leftWrist, .leftHip)
        case .right:
            return (.rightShoulder, .rightElbow, .rightWrist, .rightHip)
        }
    }

    private func oppositeShoulderName(for side: Side) -> VNHumanBodyPose3DObservation.JointName {
        switch side {
        case .left:
            return .rightShoulder
        case .right:
            return .leftShoulder
        }
    }

    private func shoulderFlexionFromShoulderLine(
        shoulder: SIMD3<Float>,
        elbow: SIMD3<Float>,
        oppositeShoulder: SIMD3<Float>
    ) -> CGFloat? {
        let bodyLine = SIMD3<Float>(
            oppositeShoulder.x - shoulder.x,
            oppositeShoulder.y - shoulder.y,
            oppositeShoulder.z - shoulder.z
        )
        let upperArm = SIMD3<Float>(
            elbow.x - shoulder.x,
            elbow.y - shoulder.y,
            elbow.z - shoulder.z
        )

        let bodyLength = simd_length(bodyLine)
        let upperArmLength = simd_length(upperArm)
        guard bodyLength > 0.0001, upperArmLength > 0.0001 else { return nil }

        let dot = simd_dot(bodyLine, upperArm)
        let cosTheta = max(-1 as Float, min(1 as Float, dot / (bodyLength * upperArmLength)))
        let angle = CGFloat(acos(cosTheta) * 180 / .pi)

        return clampDegrees(abs(90 - angle))
    }

    private func jointAngle(a: SIMD3<Float>, vertex: SIMD3<Float>, b: SIMD3<Float>) -> CGFloat? {
        let va = SIMD3<Float>(a.x - vertex.x, a.y - vertex.y, a.z - vertex.z)
        let vb = SIMD3<Float>(b.x - vertex.x, b.y - vertex.y, b.z - vertex.z)

        let ma = simd_length(va)
        let mb = simd_length(vb)
        guard ma > 0.0001, mb > 0.0001 else { return nil }

        let dot = simd_dot(va, vb)
        let cosTheta = max(-1 as Float, min(1 as Float, dot / (ma * mb)))
        let radians = acos(cosTheta)
        return CGFloat(radians * 180 / .pi)
    }

    private func normalize(value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        let range = max(upper - lower, 0.0001)
        return (value - lower) / range
    }

    private func average(_ lhs: CGFloat?, _ rhs: CGFloat?) -> CGFloat? {
        switch (lhs, rhs) {
        case let (left?, right?):
            return (left + right) / 2
        case let (left?, nil):
            return left
        case let (nil, right?):
            return right
        default:
            return nil
        }
    }

    private func available(
        in points: [VNHumanBodyPose3DObservation.JointName: SIMD3<Float>],
        names: [VNHumanBodyPose3DObservation.JointName]
    ) -> [VNHumanBodyPose3DObservation.JointName] {
        names.filter { points[$0] != nil }
    }

    private func unique(
        _ joints: [VNHumanBodyPose3DObservation.JointName]
    ) -> [VNHumanBodyPose3DObservation.JointName] {
        var seen = Set<VNHumanBodyPose3DObservation.JointName>()
        return joints.filter { seen.insert($0).inserted }
    }

    private func clamp(_ value: CGFloat) -> CGFloat {
        min(1, max(0, value))
    }

    private func clampDegrees(_ value: CGFloat) -> CGFloat {
        min(180, max(0, value))
    }
}
