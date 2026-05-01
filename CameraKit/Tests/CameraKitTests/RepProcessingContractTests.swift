import Testing
import CoreMedia
import Foundation
import Combine
@testable import CameraKit
import Vision

private let contractVersion = repProcessingContractVersion

private struct ContractSnapshot: Equatable {
    let repCount: Int
    let state: RepCounterState
    let currentMetric: CGFloat?
    let detectionQuality: DetectionQuality
    let trackedJoints: Set<VNHumanBodyPose3DObservation.JointName>
    let statusHint: String?
    let diagnosticsScalars: [String: Double]
    let diagnosticsLabels: [String: String]
}

private func makeFrame(
    positions3D: [VNHumanBodyPose3DObservation.JointName: SIMD3<Float>],
    seconds: Double
) -> PoseFrame {
    PoseFrame(
        timestamp: CMTime(seconds: seconds, preferredTimescale: 600),
        joints: [:],
        positions3D: positions3D
    )
}

private func squat3DJointFlexionPositions(
    kneeFlexionDegrees: CGFloat,
    hipFlexionDegrees: CGFloat,
    cameraZ: Float = 2.0
) -> [VNHumanBodyPose3DObservation.JointName: SIMD3<Float>] {
    func radians(_ degrees: CGFloat) -> CGFloat { degrees * .pi / 180 }

    let thighLength: CGFloat = 0.45
    let shinLength: CGFloat = 0.45
    let torsoLength: CGFloat = 0.55

    let hip = CGPoint(x: -0.18, y: -0.05)
    let knee = CGPoint(x: hip.x, y: hip.y - thighLength)
    let hipAngle = radians(180 - max(0, min(150, hipFlexionDegrees)))
    let shoulder = CGPoint(
        x: hip.x + sin(hipAngle) * torsoLength,
        y: hip.y - cos(hipAngle) * torsoLength
    )
    let kneeAngle = radians(180 - max(0, min(150, kneeFlexionDegrees)))
    let ankle = CGPoint(
        x: knee.x + sin(kneeAngle) * shinLength,
        y: knee.y + cos(kneeAngle) * shinLength
    )

    return [
        .leftShoulder: SIMD3(x: Float(shoulder.x), y: Float(shoulder.y), z: cameraZ),
        .leftHip: SIMD3(x: Float(hip.x), y: Float(hip.y), z: cameraZ),
        .leftKnee: SIMD3(x: Float(knee.x), y: Float(knee.y), z: cameraZ),
        .leftAnkle: SIMD3(x: Float(ankle.x), y: Float(ankle.y), z: cameraZ),
        .rightShoulder: SIMD3(x: 0.18, y: Float(shoulder.y), z: cameraZ),
        .rightHip: SIMD3(x: 0.18, y: Float(hip.y), z: cameraZ),
        .rightKnee: SIMD3(x: 0.18, y: Float(knee.y), z: cameraZ),
        .rightAnkle: SIMD3(x: 0.18, y: Float(ankle.y), z: cameraZ),
        .spine: SIMD3(x: 0, y: 0.25, z: cameraZ),
        .root: SIMD3(x: 0, y: -0.10, z: cameraZ),
    ]
}

private func buildPublisher(
    config: RepCountingConfiguration,
    profile: any ExerciseProfile,
    enableSquatStrategy: Bool
) -> RepCounterPublisher {
    RepCounterPublisher(
        metricCalculator: profile.makeMetricCalculator(configuration: config),
        peakDetector: profile.makePeakDetector(configuration: config),
        repCounter: profile.makeRepCounter(configuration: config),
        metricFilters: profile.makeMetricFilters(configuration: config),
        armingThreshold: config.common.armingThreshold,
        exerciseProfileID: profile.id,
        metricCalculatorFactory: { profile.makeMetricCalculator(configuration: $0) },
        peakDetectorFactory: { profile.makePeakDetector(configuration: $0) },
        repCounterFactory: { profile.makeRepCounter(configuration: $0) },
        metricFilterFactory: { profile.makeMetricFilters(configuration: $0) },
        enableSquatStrategy: enableSquatStrategy
    )
}

private func snapshot(_ output: RepCounterOutput) -> ContractSnapshot {
    ContractSnapshot(
        repCount: output.repCount,
        state: output.state,
        currentMetric: output.currentMetric,
        detectionQuality: output.detectionQuality,
        trackedJoints: Set(output.trackedJoints),
        statusHint: output.statusHint,
        diagnosticsScalars: output.exerciseDiagnostics?.scalars ?? [:],
        diagnosticsLabels: output.exerciseDiagnostics?.labels ?? [:]
    )
}

@Test func squat_contract_v1_strategy_matches_legacy() async throws {
    #expect(contractVersion == 1)

    let config = RepCountingConfiguration.squatDefault
    let profile = SquatExerciseProfile()

    let legacy = buildPublisher(config: config, profile: profile, enableSquatStrategy: false)
    let strategy = buildPublisher(config: config, profile: profile, enableSquatStrategy: true)

    final class OutputBox: @unchecked Sendable {
        var legacyOutputs: [ContractSnapshot] = []
        var strategyOutputs: [ContractSnapshot] = []
    }
    let box = OutputBox()

    let c1 = legacy.repCounts.sink { box.legacyOutputs.append(snapshot($0)) }
    let c2 = strategy.repCounts.sink { box.strategyOutputs.append(snapshot($0)) }

    let sequence: [(knee: CGFloat, hip: CGFloat)] = [
        (18, 20), (24, 24), (36, 30), (50, 38), (68, 48), (80, 58),
        (72, 52), (58, 42), (42, 34), (28, 24), (18, 20),
    ]

    for (index, frame) in sequence.enumerated() {
        let t = Double(index) * 0.1
        let pose = makeFrame(
            positions3D: squat3DJointFlexionPositions(
                kneeFlexionDegrees: frame.knee,
                hipFlexionDegrees: frame.hip
            ),
            seconds: t
        )
        legacy.ingest(pose)
        strategy.ingest(pose)
    }

    try await Task.sleep(nanoseconds: 400_000_000)
    _ = c1
    _ = c2

    #expect(box.legacyOutputs.count == box.strategyOutputs.count)
    for i in box.legacyOutputs.indices {
        let l = box.legacyOutputs[i]
        let r = box.strategyOutputs[i]
        #expect(l.repCount == r.repCount)
        #expect(l.state == r.state)
        if let lm = l.currentMetric, let rm = r.currentMetric {
            #expect(abs(lm - rm) <= 0.000001)
        } else {
            #expect(l.currentMetric == nil && r.currentMetric == nil)
        }
        #expect(l.detectionQuality == r.detectionQuality)
        #expect(l.trackedJoints == r.trackedJoints)
        #expect(l.statusHint == r.statusHint)
        #expect(l.diagnosticsScalars == r.diagnosticsScalars)
        #expect(l.diagnosticsLabels == r.diagnosticsLabels)
    }
}
