import Combine
import CoreGraphics
import CoreMedia
import Foundation
import Testing
@testable import CameraKit
import Vision

struct ExerciseRegressionContractsTests {
    @Test func squatRegression_contractStableWhenCurlThresholdsChange() async throws {
        let baseline = makeSquatRegressionConfiguration()
        var curlTweaked = baseline
        curlTweaked.curlTopFlexionDegrees = 150
        curlTweaked.curlLockoutFlexionDegrees = 5

        let baselineCount = try await runSquatCycles(configuration: baseline, cycleCount: 2)
        let tweakedCount = try await runSquatCycles(configuration: curlTweaked, cycleCount: 2)

        #expect(baselineCount == 2)
        #expect(tweakedCount == baselineCount)
    }

    @Test func curlRegression_contractStableWhenSquatThresholdsChange() async throws {
        let baseline = makeCurlRegressionConfiguration()
        var squatTweaked = baseline
        squatTweaked.squatDescendEntryThreshold = 0.35
        squatTweaked.squatStandLockoutThreshold = 0.02
        squatTweaked.squatKneeBottomFlexionDegrees = 120
        squatTweaked.squatHipBottomFlexionDegrees = 95
        squatTweaked.squatKneeLockoutFlexionDegrees = 35
        squatTweaked.squatHipLockoutFlexionDegrees = 40
        squatTweaked.squatMaxSideAsymmetryDegrees = 10

        let baselineCount = try await runCurlCycles(configuration: baseline, cycleCount: 2)
        let tweakedCount = try await runCurlCycles(configuration: squatTweaked, cycleCount: 2)

        #expect(baselineCount == 2)
        #expect(tweakedCount == baselineCount)
    }

    @Test func switchingProfiles_keepsSquatAndCurlContractsWithDistinctConfigurations() async throws {
        let squatConfig = makeSquatRegressionConfiguration()
        let curlConfig = makeCurlRegressionConfiguration()
        let publisher = RepCounterPublisher(configuration: squatConfig, exerciseProfile: SquatExerciseProfile())

        let box = OutputBox()
        let cancellable = publisher.repCounts.sink { box.update($0) }

        ingestSquatCycle(into: publisher, startSeconds: 0.0)
        try await Task.sleep(nanoseconds: 450_000_000)
        var snapshot = box.snapshot()
        #expect(snapshot.profileID == "squat")
        #expect(snapshot.count == 1)

        publisher.setExerciseProfile(BicepCurlExerciseProfile(), configuration: curlConfig)
        ingestCurlCycle(into: publisher, startSeconds: 2.0)
        try await Task.sleep(nanoseconds: 450_000_000)
        snapshot = box.snapshot()
        #expect(snapshot.profileID == "bicepCurl")
        #expect(snapshot.count == 1)

        publisher.setExerciseProfile(SquatExerciseProfile(), configuration: squatConfig)
        ingestSquatCycle(into: publisher, startSeconds: 4.0)
        try await Task.sleep(nanoseconds: 450_000_000)
        snapshot = box.snapshot()
        #expect(snapshot.profileID == "squat")
        #expect(snapshot.count == 1)

        _ = cancellable
    }
}

private final class OutputBox: @unchecked Sendable {
    private let lock = NSLock()
    private var lastRepCount: Int = 0
    private var lastProfileID: String = ""

    func update(_ output: RepCounterOutput) {
        lock.lock()
        lastRepCount = output.repCount
        lastProfileID = output.exerciseProfileID
        lock.unlock()
    }

    func snapshot() -> (count: Int, profileID: String) {
        lock.lock()
        defer { lock.unlock() }
        return (lastRepCount, lastProfileID)
    }
}

private func makeSquatRegressionConfiguration() -> RepCountingConfiguration {
    RepCountingConfiguration(
        armingThreshold: 0.5,
        minPeakHeight: 0.08,
        minValleyDepth: 0.08,
        peakWindowSize: 5,
        minTimeBetweenReps: 0.6,
        minAmplitude: 0.55,
        upThreshold: 0.20,
        downThreshold: 0.82,
        squatDescendEntryThreshold: 0.18,
        squatStandLockoutThreshold: 0.10,
        squatKneeBottomFlexionDegrees: 72,
        squatHipBottomFlexionDegrees: 52,
        squatKneeLockoutFlexionDegrees: 18,
        squatHipLockoutFlexionDegrees: 20,
        squatMaxSideAsymmetryDegrees: 25,
        inactivityResetSeconds: 3.0,
        activityDeltaThreshold: 0.015,
        spikeMaxDelta: 1.0,
        emaAlpha: 1.0
    )
}

private func makeCurlRegressionConfiguration() -> RepCountingConfiguration {
    RepCountingConfiguration(
        armingThreshold: 0.5,
        minPeakHeight: 0.08,
        minValleyDepth: 0.08,
        peakWindowSize: 5,
        minTimeBetweenReps: 0.5,
        minAmplitude: 0.25,
        upThreshold: 0.60,
        downThreshold: 0.35,
        squatDescendEntryThreshold: 0.18,
        squatStandLockoutThreshold: 0.10,
        squatKneeBottomFlexionDegrees: 80,
        squatHipBottomFlexionDegrees: 60,
        squatKneeLockoutFlexionDegrees: 18,
        squatHipLockoutFlexionDegrees: 20,
        squatMaxSideAsymmetryDegrees: 25,
        curlTopFlexionDegrees: 128,
        curlLockoutFlexionDegrees: 34,
        inactivityResetSeconds: 3.0,
        activityDeltaThreshold: 0.015,
        spikeMaxDelta: 1.0,
        emaAlpha: 1.0
    )
}

private func runSquatCycles(
    configuration: RepCountingConfiguration,
    cycleCount: Int
) async throws -> Int {
    let publisher = RepCounterPublisher(configuration: configuration, exerciseProfile: SquatExerciseProfile())
    let box = OutputBox()
    let cancellable = publisher.repCounts.sink { box.update($0) }

    for i in 0..<cycleCount {
        ingestSquatCycle(into: publisher, startSeconds: Double(i) * 1.6)
    }

    try await Task.sleep(nanoseconds: 550_000_000)
    _ = cancellable
    return box.snapshot().count
}

private func runCurlCycles(
    configuration: RepCountingConfiguration,
    cycleCount: Int
) async throws -> Int {
    let publisher = RepCounterPublisher(configuration: configuration, exerciseProfile: BicepCurlExerciseProfile())
    let box = OutputBox()
    let cancellable = publisher.repCounts.sink { box.update($0) }

    for i in 0..<cycleCount {
        ingestCurlCycle(into: publisher, startSeconds: Double(i) * 1.5)
    }

    try await Task.sleep(nanoseconds: 550_000_000)
    _ = cancellable
    return box.snapshot().count
}

private func ingestSquatCycle(into publisher: RepCounterPublisher, startSeconds: Double) {
    let depths: [CGFloat] = [0.00, 0.08, 0.22, 0.45, 0.68, 0.88, 0.96, 0.80, 0.56, 0.32, 0.12, 0.03]

    for (i, depth) in depths.enumerated() {
        let timestamp = CMTime(seconds: startSeconds + Double(i) * 0.1, preferredTimescale: 600)
        let positions3D = squat3DJointFlexionPositions(
            kneeFlexionDegrees: 10 + 95 * depth,
            hipFlexionDegrees: 10 + 75 * depth
        )

        publisher.ingest(PoseFrame(
            timestamp: timestamp,
            joints: [:],
            positions3D: positions3D
        ))
    }
}

private func ingestCurlCycle(into publisher: RepCounterPublisher, startSeconds: Double) {
    let flexions: [CGFloat] = [34, 46, 66, 88, 110, 128, 108, 84, 62, 46, 34]

    for (i, flexion) in flexions.enumerated() {
        let timestamp = CMTime(seconds: startSeconds + Double(i) * 0.1, preferredTimescale: 600)
        let positions3D = bicepCurl3DJointPositions(
            leftElbowFlexionDegrees: flexion,
            rightElbowFlexionDegrees: max(34, flexion - 8)
        )

        publisher.ingest(PoseFrame(
            timestamp: timestamp,
            joints: [:],
            positions3D: positions3D
        ))
    }
}

private func squat3DJointFlexionPositions(
    kneeFlexionDegrees: CGFloat,
    hipFlexionDegrees: CGFloat,
    cameraZ: Float = 2.0
) -> [VNHumanBodyPose3DObservation.JointName: SIMD3<Float>] {
    func radians(_ degrees: CGFloat) -> CGFloat {
        degrees * .pi / 180
    }

    func side(
        xOffset: Float,
        kneeFlexion: CGFloat,
        hipFlexion: CGFloat
    ) -> (shoulder: SIMD3<Float>, hip: SIMD3<Float>, knee: SIMD3<Float>, ankle: SIMD3<Float>) {
        let thighLength: CGFloat = 0.45
        let shinLength: CGFloat = 0.45
        let torsoLength: CGFloat = 0.55

        let hip = CGPoint(x: 0, y: -0.05)
        let thighTilt = radians(min(35, max(0, kneeFlexion * 0.35)))
        let knee = CGPoint(
            x: hip.x + sin(thighTilt) * thighLength,
            y: hip.y - cos(thighTilt) * thighLength
        )

        let backToHip = CGPoint(x: hip.x - knee.x, y: hip.y - knee.y)
        let backToHipAngle = atan2(backToHip.y, backToHip.x)
        let shinAngle = backToHipAngle + (.pi - radians(kneeFlexion))
        let ankle = CGPoint(
            x: knee.x + cos(shinAngle) * shinLength,
            y: knee.y + sin(shinAngle) * shinLength
        )

        let torsoTilt = radians(hipFlexion)
        let shoulder = CGPoint(
            x: hip.x + sin(torsoTilt) * torsoLength,
            y: hip.y + cos(torsoTilt) * torsoLength
        )

        return (
            shoulder: SIMD3(x: xOffset + Float(shoulder.x), y: Float(shoulder.y), z: cameraZ),
            hip: SIMD3(x: xOffset + Float(hip.x), y: Float(hip.y), z: cameraZ),
            knee: SIMD3(x: xOffset + Float(knee.x), y: Float(knee.y), z: cameraZ),
            ankle: SIMD3(x: xOffset + Float(ankle.x), y: Float(ankle.y), z: cameraZ)
        )
    }

    let left = side(xOffset: -0.18, kneeFlexion: kneeFlexionDegrees, hipFlexion: hipFlexionDegrees)
    let right = side(xOffset: 0.18, kneeFlexion: kneeFlexionDegrees, hipFlexion: hipFlexionDegrees)

    return [
        .leftShoulder: left.shoulder,
        .leftHip: left.hip,
        .leftKnee: left.knee,
        .leftAnkle: left.ankle,
        .rightShoulder: right.shoulder,
        .rightHip: right.hip,
        .rightKnee: right.knee,
        .rightAnkle: right.ankle,
        .spine: SIMD3(x: 0, y: 0.25, z: cameraZ),
        .root: SIMD3(x: 0, y: -0.10, z: cameraZ),
    ]
}

private func bicepCurl3DJointPositions(
    leftElbowFlexionDegrees: CGFloat,
    rightElbowFlexionDegrees: CGFloat,
    cameraZ: Float = 2.0
) -> [VNHumanBodyPose3DObservation.JointName: SIMD3<Float>] {
    func radians(_ degrees: CGFloat) -> CGFloat {
        degrees * .pi / 180
    }

    func side(
        xOffset: Float,
        elbowFlexionDegrees: CGFloat,
        inwardDirection: CGFloat
    ) -> (shoulder: SIMD3<Float>, elbow: SIMD3<Float>, wrist: SIMD3<Float>) {
        let upperArmLength: CGFloat = 0.30
        let forearmLength: CGFloat = 0.28

        let shoulder = CGPoint(x: 0, y: 0.35)
        let elbow = CGPoint(x: shoulder.x, y: shoulder.y - upperArmLength)

        let flexion = max(0, min(150, elbowFlexionDegrees))
        let forearmAngle = radians(-90 + inwardDirection * flexion)
        let wrist = CGPoint(
            x: elbow.x + cos(forearmAngle) * forearmLength,
            y: elbow.y + sin(forearmAngle) * forearmLength
        )

        return (
            shoulder: SIMD3(x: xOffset + Float(shoulder.x), y: Float(shoulder.y), z: cameraZ),
            elbow: SIMD3(x: xOffset + Float(elbow.x), y: Float(elbow.y), z: cameraZ),
            wrist: SIMD3(x: xOffset + Float(wrist.x), y: Float(wrist.y), z: cameraZ)
        )
    }

    let left = side(xOffset: -0.24, elbowFlexionDegrees: leftElbowFlexionDegrees, inwardDirection: 1)
    let right = side(xOffset: 0.24, elbowFlexionDegrees: rightElbowFlexionDegrees, inwardDirection: -1)

    return [
        .leftShoulder: left.shoulder,
        .leftElbow: left.elbow,
        .leftWrist: left.wrist,
        .rightShoulder: right.shoulder,
        .rightElbow: right.elbow,
        .rightWrist: right.wrist,
        .spine: SIMD3(x: 0, y: 0.20, z: cameraZ),
        .root: SIMD3(x: 0, y: -0.05, z: cameraZ),
    ]
}
