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
        curlTweaked.curl.topFlexionDegrees = 150
        curlTweaked.curl.lockoutFlexionDegrees = 5

        let baselineCount = try await runSquatCycles(configuration: baseline, cycleCount: 2)
        let tweakedCount = try await runSquatCycles(configuration: curlTweaked, cycleCount: 2)

        #expect(baselineCount == 2)
        #expect(tweakedCount == baselineCount)
    }

    @Test func curlRegression_contractStableWhenSquatThresholdsChange() async throws {
        let baseline = makeCurlRegressionConfiguration()
        var squatTweaked = baseline
        squatTweaked.squat.descendEntryThreshold = 0.35
        squatTweaked.squat.standLockoutThreshold = 0.02
        squatTweaked.squat.kneeBottomFlexionDegrees = 120
        squatTweaked.squat.hipBottomFlexionDegrees = 95
        squatTweaked.squat.kneeLockoutFlexionDegrees = 35
        squatTweaked.squat.hipLockoutFlexionDegrees = 40
        squatTweaked.squat.maxSideAsymmetryDegrees = 10

        let baselineCount = try await runCurlCycles(configuration: baseline, cycleCount: 2)
        let tweakedCount = try await runCurlCycles(configuration: squatTweaked, cycleCount: 2)

        #expect(baselineCount == 2)
        #expect(tweakedCount == baselineCount)
    }

    @Test func benchRegression_contractStableWhenSquatAndCurlThresholdsChange() async throws {
        let baseline = makeBenchRegressionConfiguration()
        var nonBenchTweaked = baseline
        nonBenchTweaked.squat.descendEntryThreshold = 0.35
        nonBenchTweaked.squat.standLockoutThreshold = 0.02
        nonBenchTweaked.squat.kneeBottomFlexionDegrees = 120
        nonBenchTweaked.squat.hipBottomFlexionDegrees = 95
        nonBenchTweaked.squat.kneeLockoutFlexionDegrees = 35
        nonBenchTweaked.squat.hipLockoutFlexionDegrees = 40
        nonBenchTweaked.squat.maxSideAsymmetryDegrees = 10
        nonBenchTweaked.curl.topFlexionDegrees = 150
        nonBenchTweaked.curl.lockoutFlexionDegrees = 5

        let baselineCount = try await runBenchCycles(configuration: baseline, cycleCount: 2)
        let tweakedCount = try await runBenchCycles(configuration: nonBenchTweaked, cycleCount: 2)

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

    @Test func switchingProfiles_keepsSquatCurlAndBenchContractsWithDistinctConfigurations() async throws {
        let squatConfig = makeSquatRegressionConfiguration()
        let curlConfig = makeCurlRegressionConfiguration()
        let benchConfig = makeBenchRegressionConfiguration()
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

        publisher.setExerciseProfile(BenchPressExerciseProfile(), configuration: benchConfig)
        ingestBenchCycle(into: publisher, startSeconds: 4.0)
        try await Task.sleep(nanoseconds: 450_000_000)
        snapshot = box.snapshot()
        #expect(snapshot.profileID == "benchPress")
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
    var config = RepCountingConfiguration.squatDefault
    config.filters = .init(spikeMaxDelta: 1.0, emaAlpha: 1.0)
    return config
}

private func makeCurlRegressionConfiguration() -> RepCountingConfiguration {
    var config = RepCountingConfiguration.bicepCurlDefault
    config.filters = .init(spikeMaxDelta: 1.0, emaAlpha: 1.0)
    return config
}

private func makeBenchRegressionConfiguration() -> RepCountingConfiguration {
    var config = RepCountingConfiguration.benchPressDefault
    config.filters = .init(spikeMaxDelta: 1.0, emaAlpha: 1.0)
    return config
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

private func runBenchCycles(
    configuration: RepCountingConfiguration,
    cycleCount: Int
) async throws -> Int {
    let publisher = RepCounterPublisher(configuration: configuration, exerciseProfile: BenchPressExerciseProfile())
    let box = OutputBox()
    let cancellable = publisher.repCounts.sink { box.update($0) }

    for i in 0..<cycleCount {
        ingestBenchCycle(into: publisher, startSeconds: Double(i) * 1.6)
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

private func ingestBenchCycle(into publisher: RepCounterPublisher, startSeconds: Double) {
    let cycle: [(elbow: CGFloat, shoulder: CGFloat)] = [
        (10, 10),
        (18, 12),
        (30, 15),
        (44, 18),
        (48, 18),
        (36, 22),
        (22, 34),
        (14, 46),
        (12, 48),
        (12, 28),
        (10, 14),
        (10, 10),
    ]

    for (i, frame) in cycle.enumerated() {
        let timestamp = CMTime(seconds: startSeconds + Double(i) * 0.1, preferredTimescale: 600)
        let positions3D = benchPress3DJointPositions(
            leftElbowFlexionDegrees: frame.elbow,
            rightElbowFlexionDegrees: max(10, frame.elbow - 4),
            leftShoulderFlexionDegrees: frame.shoulder,
            rightShoulderFlexionDegrees: max(10, frame.shoulder - 4)
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

private func benchPress3DJointPositions(
    leftElbowFlexionDegrees: CGFloat,
    rightElbowFlexionDegrees: CGFloat,
    leftShoulderFlexionDegrees: CGFloat,
    rightShoulderFlexionDegrees: CGFloat,
    cameraZ: Float = 2.0
) -> [VNHumanBodyPose3DObservation.JointName: SIMD3<Float>] {
    func radians(_ degrees: CGFloat) -> CGFloat {
        degrees * .pi / 180
    }

    func side(
        xOffset: Float,
        elbowFlexionDegrees: CGFloat,
        shoulderFlexionDegrees: CGFloat,
        inwardDirection: CGFloat
    ) -> (shoulder: SIMD3<Float>, elbow: SIMD3<Float>, wrist: SIMD3<Float>, hip: SIMD3<Float>) {
        let upperArmLength: CGFloat = 0.30
        let forearmLength: CGFloat = 0.28

        let shoulder = CGPoint(x: 0, y: 0.35)
        let hip = CGPoint(x: 0, y: -0.10)

        let shoulderFlexion = max(0, min(150, shoulderFlexionDegrees))
        let upperArmAngle = radians(-90 + inwardDirection * shoulderFlexion)
        let elbow = CGPoint(
            x: shoulder.x + cos(upperArmAngle) * upperArmLength,
            y: shoulder.y + sin(upperArmAngle) * upperArmLength
        )

        let elbowFlexion = max(0, min(150, elbowFlexionDegrees))
        let forearmAngle = upperArmAngle + inwardDirection * radians(elbowFlexion)
        let wrist = CGPoint(
            x: elbow.x + cos(forearmAngle) * forearmLength,
            y: elbow.y + sin(forearmAngle) * forearmLength
        )

        return (
            shoulder: SIMD3(x: xOffset + Float(shoulder.x), y: Float(shoulder.y), z: cameraZ),
            elbow: SIMD3(x: xOffset + Float(elbow.x), y: Float(elbow.y), z: cameraZ),
            wrist: SIMD3(x: xOffset + Float(wrist.x), y: Float(wrist.y), z: cameraZ),
            hip: SIMD3(x: xOffset + Float(hip.x), y: Float(hip.y), z: cameraZ)
        )
    }

    let left = side(
        xOffset: -0.24,
        elbowFlexionDegrees: leftElbowFlexionDegrees,
        shoulderFlexionDegrees: leftShoulderFlexionDegrees,
        inwardDirection: 1
    )
    let right = side(
        xOffset: 0.24,
        elbowFlexionDegrees: rightElbowFlexionDegrees,
        shoulderFlexionDegrees: rightShoulderFlexionDegrees,
        inwardDirection: -1
    )

    return [
        .leftShoulder: left.shoulder,
        .leftElbow: left.elbow,
        .leftWrist: left.wrist,
        .leftHip: left.hip,
        .rightShoulder: right.shoulder,
        .rightElbow: right.elbow,
        .rightWrist: right.wrist,
        .rightHip: right.hip,
        .spine: SIMD3(x: 0, y: 0.20, z: cameraZ),
        .root: SIMD3(x: 0, y: -0.05, z: cameraZ),
    ]
}
