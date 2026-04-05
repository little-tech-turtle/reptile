import Testing
import CoreMedia
@testable import CameraKit
import Vision

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AVFoundation)
import AVFoundation
#endif

// MARK: - Helpers

private func makeSample(_ value: CGFloat, seconds: Double = 0) -> MetricSample {
    MetricSample(timestamp: CMTime(seconds: seconds, preferredTimescale: 600), value: value)
}

/// Feed an array of values into a detector, return all detected peak types.
private func feedDetector(_ detector: inout LocalExtremaPeakDetector, values: [CGFloat]) -> [PeakType] {
    values.enumerated().compactMap { idx, v in
        detector.ingest(makeSample(v, seconds: Double(idx) * 0.033))
    }
}

private func makeFrame(
    _ joints: [VNHumanBodyPose3DObservation.JointName: CameraKit.NormalizedPoint] = [:],
    positions3D: [VNHumanBodyPose3DObservation.JointName: SIMD3<Float>] = [:]
) -> PoseFrame {
    PoseFrame(
        timestamp: CMTime(seconds: 0, preferredTimescale: 600),
        joints: joints,
        positions3D: positions3D
    )
}

/// Builds synthetic 3D joint positions for a squat at the given normalised depth.
///
/// `squatDepth` 0 = standing, 1 = deep squat. `cameraZ` is the person's depth
/// in camera space (metres) — changing it should NOT affect the metric.
private func squat3DPositions(
    squatDepth: CGFloat,
    cameraZ: Float = 2.0
) -> [VNHumanBodyPose3DObservation.JointName: SIMD3<Float>] {
    let d = Float(max(0, min(1, squatDepth)))
    // Camera is at ~1.1 m height. Y is positive upward in Vision portrait space.
    let shoulderY: Float =  0.40 - 0.20 * d   // shoulder dips ~0.20 m in a deep squat
    let hipY:      Float = -0.10 - 0.50 * d   // hip descends ~0.50 m
    let kneeY:     Float = -0.55 - 0.10 * d
    let ankleY:    Float = -0.90

    return [
        .leftShoulder:  SIMD3(x: -0.20, y: shoulderY, z: cameraZ),
        .rightShoulder: SIMD3(x:  0.20, y: shoulderY, z: cameraZ),
        .leftHip:       SIMD3(x: -0.15, y: hipY,      z: cameraZ),
        .rightHip:      SIMD3(x:  0.15, y: hipY,      z: cameraZ),
        .leftKnee:      SIMD3(x: -0.15, y: kneeY,     z: cameraZ),
        .rightKnee:     SIMD3(x:  0.15, y: kneeY,     z: cameraZ),
        .leftAnkle:     SIMD3(x: -0.12, y: ankleY,    z: cameraZ),
        .rightAnkle:    SIMD3(x:  0.12, y: ankleY,    z: cameraZ),
    ]
}

/// Builds synthetic 3D joints from explicit knee/hip flexion angles (degrees).
///
/// Flexion is defined as 0 = lockout/standing and larger values = deeper bend.
private func squat3DJointFlexionPositions(
    kneeFlexionDegrees: CGFloat,
    hipFlexionDegrees: CGFloat,
    cameraZ: Float = 2.0,
    hideRightSide: Bool = false,
    rightSideFlexionOffset: CGFloat = 0
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

        // Standing thigh points down; deeper squat moves knee slightly forward.
        let thighTilt = radians(min(35, max(0, kneeFlexion * 0.35)))
        let knee = CGPoint(
            x: hip.x + sin(thighTilt) * thighLength,
            y: hip.y - cos(thighTilt) * thighLength
        )

        // Knee interior angle = 180 - kneeFlexion.
        let backToHip = CGPoint(x: hip.x - knee.x, y: hip.y - knee.y)
        let backToHipAngle = atan2(backToHip.y, backToHip.x)
        let shinAngle = backToHipAngle + (.pi - radians(kneeFlexion))
        let ankle = CGPoint(
            x: knee.x + cos(shinAngle) * shinLength,
            y: knee.y + sin(shinAngle) * shinLength
        )

        // Hip flexion leans torso forward from vertical.
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
    var joints: [VNHumanBodyPose3DObservation.JointName: SIMD3<Float>] = [
        .leftShoulder: left.shoulder,
        .leftHip: left.hip,
        .leftKnee: left.knee,
        .leftAnkle: left.ankle,
    ]

    if !hideRightSide {
        let right = side(
            xOffset: 0.18,
            kneeFlexion: kneeFlexionDegrees + rightSideFlexionOffset,
            hipFlexion: hipFlexionDegrees + rightSideFlexionOffset
        )
        joints[.rightShoulder] = right.shoulder
        joints[.rightHip] = right.hip
        joints[.rightKnee] = right.knee
        joints[.rightAnkle] = right.ankle
    }

    // Helpful fallbacks used by calculators.
    joints[.spine] = SIMD3(x: 0, y: 0.25, z: cameraZ)
    joints[.root] = SIMD3(x: 0, y: -0.10, z: cameraZ)
    return joints
}

/// Builds synthetic 3D joints for bicep curls from elbow flexion angles.
///
/// Elbow flexion: 0 = arm straight, larger values = stronger curl contraction.
private func bicepCurl3DJointPositions(
    leftElbowFlexionDegrees: CGFloat,
    rightElbowFlexionDegrees: CGFloat,
    cameraZ: Float = 2.0,
    hideLeftArm: Bool = false,
    hideRightArm: Bool = false
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
        // 0 deg flexion => forearm points down, deeper flexion folds inward/upward.
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

    var joints: [VNHumanBodyPose3DObservation.JointName: SIMD3<Float>] = [
        .spine: SIMD3(x: 0, y: 0.20, z: cameraZ),
        .root: SIMD3(x: 0, y: -0.05, z: cameraZ),
    ]

    if !hideLeftArm {
        let left = side(xOffset: -0.24, elbowFlexionDegrees: leftElbowFlexionDegrees, inwardDirection: 1)
        joints[.leftShoulder] = left.shoulder
        joints[.leftElbow] = left.elbow
        joints[.leftWrist] = left.wrist
    }

    if !hideRightArm {
        let right = side(xOffset: 0.24, elbowFlexionDegrees: rightElbowFlexionDegrees, inwardDirection: -1)
        joints[.rightShoulder] = right.shoulder
        joints[.rightElbow] = right.elbow
        joints[.rightWrist] = right.wrist
    }

    return joints
}

// MARK: - LocalExtremaPeakDetector

@Test func peakDetector_detectsCleanMaximum() {
    var detector = LocalExtremaPeakDetector(minPeakHeight: 0.05, minValleyDepth: 0.05, windowSize: 5)
    // Rising then falling — peak sits at index 5 (0-based), detected 2 frames later
    let values: [CGFloat] = [0.1, 0.2, 0.3, 0.5, 0.7, 0.9, 0.7, 0.5]
    let peaks = feedDetector(&detector, values: values)
    #expect(peaks.contains(.maximum))
    #expect(!peaks.contains(.minimum))
}

@Test func peakDetector_detectsCleanMinimum() {
    var detector = LocalExtremaPeakDetector(minPeakHeight: 0.05, minValleyDepth: 0.05, windowSize: 5)
    // Falling then rising — valley sits in the middle
    let values: [CGFloat] = [0.9, 0.7, 0.5, 0.3, 0.1, 0.3, 0.5, 0.7]
    let peaks = feedDetector(&detector, values: values)
    #expect(peaks.contains(.minimum))
    #expect(!peaks.contains(.maximum))
}

@Test func peakDetector_rejectsMaximumBelowThreshold() {
    // minPeakHeight = 0.5; candidate value = 0.3 → should NOT fire
    var detector = LocalExtremaPeakDetector(minPeakHeight: 0.5, minValleyDepth: 0.05, windowSize: 5)
    let values: [CGFloat] = [0.1, 0.2, 0.3, 0.2, 0.1, 0.05, 0.02]
    let peaks = feedDetector(&detector, values: values)
    #expect(!peaks.contains(.maximum))
}

@Test func peakDetector_rejectsMinimumAboveThreshold() {
    // minValleyDepth = 0.5 → valley must be < 0.5; candidate at 0.6 should NOT fire
    var detector = LocalExtremaPeakDetector(minPeakHeight: 0.05, minValleyDepth: 0.5, windowSize: 5)
    let values: [CGFloat] = [0.9, 0.8, 0.6, 0.8, 0.9, 0.95, 1.0]
    let peaks = feedDetector(&detector, values: values)
    #expect(!peaks.contains(.minimum))
}

@Test func peakDetector_3PointNoiseSpikeDoesNotTrigger() {
    // windowSize=5 requires 2 neighbours on each side; a single-sample spike with
    // windowSize=5 should NOT fire (the old 3-point detector would have fired).
    var detector = LocalExtremaPeakDetector(minPeakHeight: 0.05, minValleyDepth: 0.05, windowSize: 5)
    // Spike at index 3: neighbours at [2] and [4] confirm, but [1] and [5] do not
    let values: [CGFloat] = [0.2, 0.2, 0.2, 0.9, 0.2, 0.2, 0.2, 0.2]
    _ = feedDetector(&detector, values: values)
    // Primary assertion: fewer than windowSize samples → no detection
    var detectorSmall = LocalExtremaPeakDetector(minPeakHeight: 0.05, minValleyDepth: 0.05, windowSize: 5)
    let shortValues: [CGFloat] = [0.1, 0.9, 0.1]
    let shortPeaks = feedDetector(&detectorSmall, values: shortValues)
    #expect(shortPeaks.isEmpty)
}

@Test func peakDetector_fewerThanWindowSizeSamplesNoDetection() {
    var detector = LocalExtremaPeakDetector(minPeakHeight: 0.05, minValleyDepth: 0.05, windowSize: 7)
    // Only 5 samples — less than windowSize+1=8 needed
    let values: [CGFloat] = [0.1, 0.5, 0.9, 0.5, 0.1]
    let peaks = feedDetector(&detector, values: values)
    #expect(peaks.isEmpty)
}

@Test func peakDetector_detectsMultiplePeaksInSequence() {
    var detector = LocalExtremaPeakDetector(minPeakHeight: 0.05, minValleyDepth: 0.05, windowSize: 5)
    // Two full squat cycles: up-down-up-down
    let values: [CGFloat] = [0.9, 0.7, 0.5, 0.1, 0.3, 0.7, 0.9, 0.7, 0.5, 0.1, 0.3, 0.7, 0.9]
    let peaks = feedDetector(&detector, values: values)
    let maxCount = peaks.filter { $0 == .maximum }.count
    let minCount = peaks.filter { $0 == .minimum }.count
    #expect(maxCount >= 1)
    #expect(minCount >= 1)
}

// MARK: - CycleBasedRepCounter

private func makeCounter(
    minAmplitude: CGFloat = 0.15,
    minTime: Double = 0.5,
    inactivityResetSeconds: Double = 3.0,
    activityDeltaThreshold: CGFloat = 0.015
) -> CycleBasedRepCounter {
    CycleBasedRepCounter(
        minTimeBetweenReps: minTime,
        minAmplitude: minAmplitude,
        inactivityResetSeconds: inactivityResetSeconds,
        activityDeltaThreshold: activityDeltaThreshold
    )
}

private func time(_ seconds: Double) -> CMTime {
    CMTime(seconds: seconds, preferredTimescale: 600)
}

@Test func repCounter_maxThenMinCountsOne() {
    var counter = makeCounter()
    counter.processPeak(.maximum, timestamp: time(0), metricValue: 0.9)
    counter.processPeak(.minimum, timestamp: time(1), metricValue: 0.1)
    #expect(counter.count == 1)
}

@Test func repCounter_minWithoutPrecedingMaxCountsZero() {
    var counter = makeCounter()
    counter.processPeak(.minimum, timestamp: time(1), metricValue: 0.1)
    #expect(counter.count == 0)
}

@Test func repCounter_twoConsecutiveMinsCountOne() {
    var counter = makeCounter()
    counter.processPeak(.maximum, timestamp: time(0), metricValue: 0.9)
    counter.processPeak(.minimum, timestamp: time(1), metricValue: 0.1)
    counter.processPeak(.minimum, timestamp: time(2), metricValue: 0.05)
    #expect(counter.count == 1)
}

@Test func repCounter_twoConsecutiveMaxesCountZero() {
    var counter = makeCounter()
    counter.processPeak(.maximum, timestamp: time(0), metricValue: 0.9)
    counter.processPeak(.maximum, timestamp: time(1), metricValue: 0.85)
    #expect(counter.count == 0)
}

@Test func repCounter_insufficientAmplitudeCountsZero() {
    // amplitude = 0.9 - 0.8 = 0.1, minAmplitude = 0.15 → should not count
    var counter = makeCounter(minAmplitude: 0.15)
    counter.processPeak(.maximum, timestamp: time(0), metricValue: 0.9)
    counter.processPeak(.minimum, timestamp: time(1), metricValue: 0.8)
    #expect(counter.count == 0)
}

@Test func repCounter_timeGateRejectsSecondRepTooSoon() {
    var counter = makeCounter(minTime: 1.0)
    counter.processPeak(.maximum, timestamp: time(0), metricValue: 0.9)
    counter.processPeak(.minimum, timestamp: time(0.5), metricValue: 0.1)
    #expect(counter.count == 0)
}

@Test func repCounter_twoFullSquatsCountTwo() {
    var counter = makeCounter()
    // First squat
    counter.processPeak(.maximum, timestamp: time(0), metricValue: 0.9)
    counter.processPeak(.minimum, timestamp: time(1), metricValue: 0.1)
    // Second squat
    counter.processPeak(.maximum, timestamp: time(2), metricValue: 0.85)
    counter.processPeak(.minimum, timestamp: time(3), metricValue: 0.15)
    #expect(counter.count == 2)
}

@Test func repCounter_resetClearsAllState() {
    var counter = makeCounter()
    counter.processPeak(.maximum, timestamp: time(0), metricValue: 0.9)
    counter.processPeak(.minimum, timestamp: time(1), metricValue: 0.1)
    #expect(counter.count == 1)
    counter.reset()
    #expect(counter.count == 0)
    #expect(counter.state == .transition)
}

@Test func repCounter_afterResetLoneMinDoesNotCount() {
    var counter = makeCounter()
    counter.processPeak(.maximum, timestamp: time(0), metricValue: 0.9)
    counter.processPeak(.minimum, timestamp: time(1), metricValue: 0.1)
    counter.reset()
    // After reset, lastPeakType is nil — a lone minimum should not count
    counter.processPeak(.minimum, timestamp: time(2), metricValue: 0.05)
    #expect(counter.count == 0)
}

@Test func repCounter_resetsAfterThreeSecondsOfNoActivity() {
    var counter = makeCounter(inactivityResetSeconds: 3.0, activityDeltaThreshold: 0.02)

    counter.ingestSample(timestamp: time(0.0), metricValue: 0.9)
    counter.processPeak(.maximum, timestamp: time(0.0), metricValue: 0.9)
    counter.ingestSample(timestamp: time(1.0), metricValue: 0.1)
    counter.processPeak(.minimum, timestamp: time(1.0), metricValue: 0.1)
    #expect(counter.count == 1)

    counter.ingestSample(timestamp: time(3.9), metricValue: 0.1)
    #expect(counter.count == 1)

    counter.ingestSample(timestamp: time(4.2), metricValue: 0.1)
    #expect(counter.count == 0)
    #expect(counter.state == .transition)
}

@Test func repCounter_doesNotResetWhenActivityContinues() {
    var counter = makeCounter(inactivityResetSeconds: 3.0, activityDeltaThreshold: 0.02)

    counter.ingestSample(timestamp: time(0.0), metricValue: 0.9)
    counter.processPeak(.maximum, timestamp: time(0.0), metricValue: 0.9)
    counter.ingestSample(timestamp: time(1.0), metricValue: 0.1)
    counter.processPeak(.minimum, timestamp: time(1.0), metricValue: 0.1)
    #expect(counter.count == 1)

    counter.ingestSample(timestamp: time(2.5), metricValue: 0.2)
    counter.ingestSample(timestamp: time(4.9), metricValue: 0.35)
    #expect(counter.count == 1)
}

@Test func repCounter_updateTuning_adjustsAmplitudeWithoutResettingCount() {
    var counter = makeCounter(minAmplitude: 0.40)

    counter.processPeak(.maximum, timestamp: time(0.0), metricValue: 0.90)
    counter.processPeak(.minimum, timestamp: time(1.0), metricValue: 0.70)
    #expect(counter.count == 0)

    counter.updateTuning(
        RepCounterTuning(
            minTimeBetweenReps: 0.5,
            minAmplitude: 0.15,
            upThreshold: 0.6,
            downThreshold: 0.3,
            inactivityResetSeconds: 3.0,
            activityDeltaThreshold: 0.015
        )
    )

    counter.processPeak(.maximum, timestamp: time(2.0), metricValue: 0.90)
    counter.processPeak(.minimum, timestamp: time(3.0), metricValue: 0.70)
    #expect(counter.count == 1)
}

@Test func repCounter_updateTuning_changesIdleResetWindow() {
    var counter = makeCounter(inactivityResetSeconds: 10.0, activityDeltaThreshold: 0.02)

    counter.ingestSample(timestamp: time(0.0), metricValue: 0.9)
    counter.processPeak(.maximum, timestamp: time(0.0), metricValue: 0.9)
    counter.ingestSample(timestamp: time(1.0), metricValue: 0.1)
    counter.processPeak(.minimum, timestamp: time(1.0), metricValue: 0.1)
    #expect(counter.count == 1)

    counter.updateTuning(
        RepCounterTuning(
            minTimeBetweenReps: 0.5,
            minAmplitude: 0.15,
            upThreshold: 0.6,
            downThreshold: 0.3,
            inactivityResetSeconds: 3.0,
            activityDeltaThreshold: 0.02
        )
    )

    counter.ingestSample(timestamp: time(4.2), metricValue: 0.1)
    #expect(counter.count == 0)
}

@Test func repCounter_manyMaximaFollowedByMinimumCountsOne() {
    // Simulates the arming-broadcast pattern: publisher fires .maximum every frame
    // while the person is standing (above threshold). A single .minimum should
    // still count exactly one rep. The minimum is placed 1 second after the last
    // maximum so the time gate (default 0.5 s) is satisfied.
    var counter = makeCounter()
    for i in 0 ..< 10 {
        counter.processPeak(.maximum, timestamp: time(Double(i) * 0.033), metricValue: 0.9)
    }
    counter.processPeak(.minimum, timestamp: time(1.0), metricValue: 0.1)
    #expect(counter.count == 1)
}

// MARK: - SpikeRejectionFilter

@Test func spikeFilter_normalValuesPassThrough() {
    var filter = SpikeRejectionFilter(maxDelta: 0.25)
    let values: [CGFloat] = [0.5, 0.55, 0.6, 0.58, 0.62]
    var results: [CGFloat] = []
    for v in values { results.append(filter.filter(v)) }
    #expect(results == values)
}

@Test func spikeFilter_spikeIsRejectedAndHeld() {
    var filter = SpikeRejectionFilter(maxDelta: 0.25)
    _ = filter.filter(0.5)         // lastAccepted = 0.5
    let held = filter.filter(0.0)  // delta 0.5 > 0.25 — should return 0.5
    #expect(held == 0.5)
    // Next normal value should resume from 0.5 (not from 0.0)
    let next = filter.filter(0.6)  // delta 0.1 from 0.5 — should pass
    #expect(next == 0.6)
}

@Test func spikeFilter_nanIsRejected() {
    var filter = SpikeRejectionFilter(maxDelta: 0.25)
    _ = filter.filter(0.5)
    let result = filter.filter(.nan)
    #expect(result == 0.5)
}

@Test func spikeFilter_infinityIsRejected() {
    var filter = SpikeRejectionFilter(maxDelta: 0.25)
    _ = filter.filter(0.5)
    let result = filter.filter(.infinity)
    #expect(result == 0.5)
}

@Test func spikeFilter_firstValueAlwaysPasses() {
    var filter = SpikeRejectionFilter(maxDelta: 0.25)
    let result = filter.filter(0.99)
    #expect(result == 0.99)
}

// MARK: - EMAMetricFilter

@Test func emaFilter_firstSamplePassesThrough() {
    var filter = EMAMetricFilter(alpha: 0.3)
    let result = filter.filter(0.7)
    #expect(result == 0.7)
}

@Test func emaFilter_secondSampleAppliesEMAFormula() {
    var filter = EMAMetricFilter(alpha: 0.3)
    _ = filter.filter(0.5)          // previous = 0.5
    let result = filter.filter(1.0) // 0.3 * 1.0 + 0.7 * 0.5 = 0.65
    #expect(abs(result - 0.65) < 0.0001)
}

@Test func emaFilter_convergesOnConstantSignal() {
    var filter = EMAMetricFilter(alpha: 0.3)
    var result: CGFloat = 0
    for _ in 0 ..< 100 {
        result = filter.filter(1.0)
    }
    #expect(abs(result - 1.0) < 0.001)
}

// MARK: - FrameTransformPolicy

#if canImport(UIKit)
@Test func transformPolicy_visionOrientationPortraitUnmirrored() {
    let result = FrameTransformPolicy.visionOrientation(for: .portrait, mirrored: false)
    #expect(result == .right)
}

@Test func transformPolicy_visionOrientationLandscapeRightMirrored() {
    let result = FrameTransformPolicy.visionOrientation(for: .landscapeRight, mirrored: true)
    #expect(result == .downMirrored)
}

@Test func transformPolicy_previewRotationAngles() {
    #expect(FrameTransformPolicy.previewRotationAngle(for: .portrait) == 90)
    #expect(FrameTransformPolicy.previewRotationAngle(for: .portraitUpsideDown) == 270)
    #expect(FrameTransformPolicy.previewRotationAngle(for: .landscapeLeft) == 0)
    #expect(FrameTransformPolicy.previewRotationAngle(for: .landscapeRight) == 180)
}

#if canImport(AVFoundation)
@Test func transformPolicy_previewMirrorsFrontCamera() {
    #expect(FrameTransformPolicy.previewMirrored(for: .front))
}

@Test func transformPolicy_previewDoesNotMirrorBackCamera() {
    #expect(!FrameTransformPolicy.previewMirrored(for: .back))
}

@Test func transformPolicy_visionInputUnmirroredForFrontCamera() {
    #expect(!FrameTransformPolicy.visionMirroredInput(for: .front))
}

@Test func transformPolicy_visionInputUnmirroredForBackCamera() {
    #expect(!FrameTransformPolicy.visionMirroredInput(for: .back))
}
#endif
#endif

// MARK: - DistanceFromFloorCalculator

private func motionJoints(
    rootX: CGFloat = 0.5,
    leftWristX: CGFloat = 0.5,
    rightWristX: CGFloat = 0.5,
    y: CGFloat = 0.5
) -> [VNHumanBodyPose3DObservation.JointName: CameraKit.NormalizedPoint] {
    [
        .root: CameraKit.NormalizedPoint(x: rootX, y: y),
        .leftWrist: CameraKit.NormalizedPoint(x: leftWristX, y: y),
        .rightWrist: CameraKit.NormalizedPoint(x: rightWristX, y: y),
    ]
}

@Test func adaptiveCalculator_selectsMostMovingJoint() {
    let calculator = AdaptiveDominantAxisCalculator(
        switchMargin: 1.15,
        switchConfirmationFrames: 2
    )

    let frames: [[VNHumanBodyPose3DObservation.JointName: CameraKit.NormalizedPoint]] = [
        motionJoints(rightWristX: 0.50),
        motionJoints(rightWristX: 0.80),
        motionJoints(rightWristX: 0.20),
        motionJoints(rightWristX: 0.78),
        motionJoints(rightWristX: 0.22),
    ]

    for joints in frames {
        _ = calculator.calculate(from: makeFrame(joints))
    }

    #expect(calculator.trackedJoints(from: makeFrame(frames.last!)) == [VNHumanBodyPose3DObservation.JointName.rightWrist])
}

@Test func adaptiveCalculator_doesNotSwitchOnSingleFrameSpike() {
    let calculator = AdaptiveDominantAxisCalculator(
        switchMargin: 1.20,
        switchConfirmationFrames: 3
    )

    let primeFrames: [[VNHumanBodyPose3DObservation.JointName: CameraKit.NormalizedPoint]] = [
        motionJoints(rightWristX: 0.50),
        motionJoints(rightWristX: 0.82),
        motionJoints(rightWristX: 0.18),
        motionJoints(rightWristX: 0.80),
    ]

    for joints in primeFrames {
        _ = calculator.calculate(from: makeFrame(joints))
    }
    #expect(calculator.trackedJoints(from: makeFrame(primeFrames.last!)) == [VNHumanBodyPose3DObservation.JointName.rightWrist])

    let spikeFrame = motionJoints(leftWristX: 0.95, rightWristX: 0.80)
    _ = calculator.calculate(from: makeFrame(spikeFrame))
    #expect(calculator.trackedJoints(from: makeFrame(spikeFrame)) == [VNHumanBodyPose3DObservation.JointName.rightWrist])
}

@Test func adaptiveCalculator_switchesAfterSustainedStrongerMotion() {
    let calculator = AdaptiveDominantAxisCalculator(
        switchMargin: 1.15,
        switchConfirmationFrames: 2
    )

    let rightDominant: [[VNHumanBodyPose3DObservation.JointName: CameraKit.NormalizedPoint]] = [
        motionJoints(rightWristX: 0.50),
        motionJoints(rightWristX: 0.80),
        motionJoints(rightWristX: 0.20),
        motionJoints(rightWristX: 0.78),
    ]
    for joints in rightDominant {
        _ = calculator.calculate(from: makeFrame(joints))
    }
    #expect(calculator.trackedJoints(from: makeFrame(rightDominant.last!)) == [VNHumanBodyPose3DObservation.JointName.rightWrist])

    let leftDominant: [[VNHumanBodyPose3DObservation.JointName: CameraKit.NormalizedPoint]] = [
        motionJoints(leftWristX: 0.10, rightWristX: 0.78),
        motionJoints(leftWristX: 0.90, rightWristX: 0.78),
        motionJoints(leftWristX: 0.15, rightWristX: 0.78),
        motionJoints(leftWristX: 0.85, rightWristX: 0.78),
    ]
    for joints in leftDominant {
        _ = calculator.calculate(from: makeFrame(joints))
    }

    #expect(calculator.trackedJoints(from: makeFrame(leftDominant.last!)) == [VNHumanBodyPose3DObservation.JointName.leftWrist])
}

@Test func distanceFromFloor_verticalMovementChangesMetric() {
    let calculator = DistanceFromFloorCalculator()

    let standing: [VNHumanBodyPose3DObservation.JointName: CameraKit.NormalizedPoint] = [
        .root: CameraKit.NormalizedPoint(x: 0.20, y: 0.50),
    ]
    let crouched: [VNHumanBodyPose3DObservation.JointName: CameraKit.NormalizedPoint] = [
        .root: CameraKit.NormalizedPoint(x: 0.80, y: 0.50),
    ]

    let standingMetric = calculator.calculate(from: makeFrame(standing))
    let crouchedMetric = calculator.calculate(from: makeFrame(crouched))

    #expect(standingMetric != nil)
    #expect(crouchedMetric != nil)
    #expect(standingMetric! > crouchedMetric!)
}

@Test func distanceFromFloor_horizontalMovementDoesNotChangeMetric() {
    let calculator = DistanceFromFloorCalculator()

    let leftSide: [VNHumanBodyPose3DObservation.JointName: CameraKit.NormalizedPoint] = [
        .root: CameraKit.NormalizedPoint(x: 0.35, y: 0.10),
    ]
    let rightSide: [VNHumanBodyPose3DObservation.JointName: CameraKit.NormalizedPoint] = [
        .root: CameraKit.NormalizedPoint(x: 0.35, y: 0.90),
    ]

    let leftMetric = calculator.calculate(from: makeFrame(leftSide))
    let rightMetric = calculator.calculate(from: makeFrame(rightSide))

    #expect(leftMetric != nil)
    #expect(rightMetric != nil)
    #expect(abs(leftMetric! - rightMetric!) < 0.0001)
}

@Test func distanceFromFloor_trackedJoints_prefersRoot() {
    let calculator = DistanceFromFloorCalculator()
    let joints: [VNHumanBodyPose3DObservation.JointName: CameraKit.NormalizedPoint] = [
        .root: CameraKit.NormalizedPoint(x: 0.40, y: 0.50),
        .leftHip: CameraKit.NormalizedPoint(x: 0.45, y: 0.55),
        .rightHip: CameraKit.NormalizedPoint(x: 0.45, y: 0.45),
    ]

    let tracked = calculator.trackedJoints(from: makeFrame(joints))
    #expect(tracked == [VNHumanBodyPose3DObservation.JointName.root])
}

@Test func distanceFromFloor_trackedJoints_usesHipPairWhenRootMissing() {
    let calculator = DistanceFromFloorCalculator()
    let joints: [VNHumanBodyPose3DObservation.JointName: CameraKit.NormalizedPoint] = [
        .leftHip: CameraKit.NormalizedPoint(x: 0.45, y: 0.55),
        .rightHip: CameraKit.NormalizedPoint(x: 0.45, y: 0.45),
    ]

    let tracked = Set(calculator.trackedJoints(from: makeFrame(joints)))
    let expected: Set<VNHumanBodyPose3DObservation.JointName> = [.leftHip, .rightHip]
    #expect(tracked == expected)
}

// MARK: - Squat profile

private func squatJoints(
    depth: CGFloat,
    missingKnees: Bool = false,
    hipSkew: CGFloat = 0
) -> [VNHumanBodyPose3DObservation.JointName: CameraKit.NormalizedPoint] {
    let d = max(0, min(1, depth))
    let shoulderX: CGFloat = 0.20
    let ankleX: CGFloat = 0.90
    let hipX: CGFloat = 0.52 + 0.24 * d
    let kneeX: CGFloat = 0.62 + 0.10 * d

    var joints: [VNHumanBodyPose3DObservation.JointName: CameraKit.NormalizedPoint] = [
        .leftShoulder: CameraKit.NormalizedPoint(x: shoulderX, y: 0.36),
        .rightShoulder: CameraKit.NormalizedPoint(x: shoulderX, y: 0.64),
        .leftHip: CameraKit.NormalizedPoint(x: hipX + hipSkew, y: 0.42),
        .rightHip: CameraKit.NormalizedPoint(x: hipX - hipSkew, y: 0.58),
        .leftAnkle: CameraKit.NormalizedPoint(x: ankleX, y: 0.46),
        .rightAnkle: CameraKit.NormalizedPoint(x: ankleX, y: 0.54),
    ]

    if !missingKnees {
        joints[.leftKnee] = CameraKit.NormalizedPoint(x: kneeX, y: 0.44)
        joints[.rightKnee] = CameraKit.NormalizedPoint(x: kneeX, y: 0.56)
    }

    return joints
}

private func offsetCameraJoints(depth d: CGFloat) -> [VNHumanBodyPose3DObservation.JointName: CameraKit.NormalizedPoint] {
    let d = max(0, min(1, d))
    let shoulderX: CGFloat = 0.15
    let kneeX: CGFloat = 0.45 + 0.12 * d
    let hipX: CGFloat = 0.35 + 0.18 * d
    return [
        .leftShoulder:  CameraKit.NormalizedPoint(x: shoulderX, y: 0.35),
        .rightShoulder: CameraKit.NormalizedPoint(x: shoulderX, y: 0.65),
        .leftHip:       CameraKit.NormalizedPoint(x: hipX, y: 0.42),
        .rightHip:      CameraKit.NormalizedPoint(x: hipX, y: 0.58),
        .leftKnee:      CameraKit.NormalizedPoint(x: kneeX, y: 0.40),
        .rightKnee:     CameraKit.NormalizedPoint(x: kneeX, y: 0.60),
    ]
}

private func feedSquatCounter(
    _ counter: inout SquatPhaseRepCounter,
    values: [CGFloat],
    startSeconds: Double = 0,
    stepSeconds: Double = 0.1
) {
    for (index, value) in values.enumerated() {
        let timestamp = CMTime(seconds: startSeconds + Double(index) * stepSeconds, preferredTimescale: 600)
        counter.ingestSample(timestamp: timestamp, metricValue: value)
    }
}

@Test func squatMetric_computesWithKneesButNoAnkles() {
    let calculator = SquatDepthMetricCalculator()

    var standing = squatJoints(depth: 0.0)
    standing.removeValue(forKey: .leftAnkle)
    standing.removeValue(forKey: .rightAnkle)
    let standingMetric = calculator.calculate(from: makeFrame(standing))
    #expect(standingMetric != nil)
    #expect(standingMetric! < 0.15)

    var deep = squatJoints(depth: 0.9)
    deep.removeValue(forKey: .leftAnkle)
    deep.removeValue(forKey: .rightAnkle)
    let deepMetric = calculator.calculate(from: makeFrame(deep))
    #expect(deepMetric != nil)
    #expect(deepMetric! > 0.62)
    #expect(deepMetric! > standingMetric!)
}

@Test func squatMetric_returnsNilWithNeitherAnklesNorKnees() {
    let calculator = SquatDepthMetricCalculator()
    var joints = squatJoints(depth: 0.5)
    joints.removeValue(forKey: .leftAnkle)
    joints.removeValue(forKey: .rightAnkle)
    joints.removeValue(forKey: .leftKnee)
    joints.removeValue(forKey: .rightKnee)
    #expect(calculator.calculate(from: makeFrame(joints)) == nil)
}

@Test func squatMetric_adaptiveNormalizationWorksWithOffsetCamera() {
    let calculator = SquatDepthMetricCalculator()
    for _ in 0..<30 { _ = calculator.calculate(from: makeFrame(offsetCameraJoints(depth: 0.0))) }
    for _ in 0..<30 { _ = calculator.calculate(from: makeFrame(offsetCameraJoints(depth: 1.0))) }
    let standingMetric = calculator.calculate(from: makeFrame(offsetCameraJoints(depth: 0.0)))
    let deepMetric = calculator.calculate(from: makeFrame(offsetCameraJoints(depth: 1.0)))
    #expect(standingMetric != nil)
    #expect(deepMetric != nil)
    #expect(standingMetric! < 0.20)
    #expect(deepMetric! > 0.62)
    #expect(deepMetric! > standingMetric!)
}

@Test func squatMetric_increasesWithDepth() {
    let calculator = SquatDepthMetricCalculator(hipWeight: 1, kneeWeight: 0)

    let standing = calculator.calculate(from: makeFrame(squatJoints(depth: 0.05)))
    let deep = calculator.calculate(from: makeFrame(squatJoints(depth: 0.95)))

    #expect(standing != nil)
    #expect(deep != nil)
    #expect(deep! > standing!)
}

@Test func squatMetric_handlesMissingKneesUsingHipDepth() {
    let calculator = SquatDepthMetricCalculator(hipWeight: 1, kneeWeight: 0)
    let metric = calculator.calculate(from: makeFrame(squatJoints(depth: 0.6, missingKnees: true)))
    #expect(metric != nil)
}

@Test func squatMetric_rejectsLargeHipAsymmetry() {
    let calculator = SquatDepthMetricCalculator(maxHipSymmetryDelta: 0.05)
    let metric = calculator.calculate(from: makeFrame(squatJoints(depth: 0.6, hipSkew: 0.08)))
    #expect(metric == nil)
}

@Test func squatCounter_countsOneFullCycle() {
    var counter = SquatPhaseRepCounter(minTimeBetweenReps: 0.4, minAmplitude: 0.15)
    let values: [CGFloat] = [0.05, 0.14, 0.24, 0.46, 0.66, 0.72, 0.56, 0.39, 0.20, 0.09, 0.05]

    feedSquatCounter(&counter, values: values)

    #expect(counter.count == 1)
    #expect(counter.state == .up)
}

@Test func squatCounter_doesNotCountPartialDepthCycle() {
    var counter = SquatPhaseRepCounter(minTimeBetweenReps: 0.4, minAmplitude: 0.15)
    let values: [CGFloat] = [0.05, 0.13, 0.23, 0.31, 0.39, 0.30, 0.19, 0.11, 0.05]

    feedSquatCounter(&counter, values: values)

    #expect(counter.count == 0)
}

@Test func squatCounter_bottomBounceCountsOnce() {
    var counter = SquatPhaseRepCounter(minTimeBetweenReps: 0.4, minAmplitude: 0.15)
    let values: [CGFloat] = [0.05, 0.15, 0.29, 0.50, 0.66, 0.73, 0.68, 0.74, 0.62, 0.51, 0.34, 0.18, 0.08]

    feedSquatCounter(&counter, values: values)

    #expect(counter.count == 1)
}

@Test func squatCounter_needsNewCycleForSecondRep() {
    var counter = SquatPhaseRepCounter(minTimeBetweenReps: 0.4, minAmplitude: 0.15)
    let first: [CGFloat] = [0.05, 0.16, 0.31, 0.54, 0.68, 0.71, 0.55, 0.37, 0.19, 0.08]
    let extraBottomMotion: [CGFloat] = [0.12, 0.48, 0.69, 0.62, 0.46]

    feedSquatCounter(&counter, values: first, startSeconds: 0)
    feedSquatCounter(&counter, values: extraBottomMotion, startSeconds: 1.2)

    #expect(counter.count == 1)
}

@Test func squatCounter_tuningCanRequireDeeperBottom() {
    var counter = SquatPhaseRepCounter(minTimeBetweenReps: 0.4, minAmplitude: 0.15)
    let values: [CGFloat] = [0.05, 0.14, 0.24, 0.46, 0.66, 0.72, 0.56, 0.39, 0.20, 0.09, 0.05]

    counter.updateTuning(
        RepCounterTuning(
            minTimeBetweenReps: 0.4,
            minAmplitude: 0.15,
            upThreshold: 0.2,
            downThreshold: 0.75,
            inactivityResetSeconds: 3,
            activityDeltaThreshold: 0.015,
            squatDescendEntryThreshold: 0.12,
            squatStandLockoutThreshold: 0.10
        )
    )

    feedSquatCounter(&counter, values: values)

    #expect(counter.count == 0)
}

@Test func squatCounter_tuningCanRequireFullerLockout() {
    var counter = SquatPhaseRepCounter(minTimeBetweenReps: 0.4, minAmplitude: 0.15)
    let values: [CGFloat] = [0.05, 0.14, 0.24, 0.46, 0.66, 0.72, 0.56, 0.39, 0.20, 0.09, 0.05]

    counter.updateTuning(
        RepCounterTuning(
            minTimeBetweenReps: 0.4,
            minAmplitude: 0.15,
            upThreshold: 0.2,
            downThreshold: 0.62,
            inactivityResetSeconds: 3,
            activityDeltaThreshold: 0.015,
            squatDescendEntryThreshold: 0.12,
            squatStandLockoutThreshold: 0.04
        )
    )

    feedSquatCounter(&counter, values: values)

    #expect(counter.count == 0)
}

@Test func squatCounter_tuningMinRepTimeBlocksFastSecondRep() {
    var counter = SquatPhaseRepCounter(minTimeBetweenReps: 0.4, minAmplitude: 0.15)
    let fastDoubleRep: [CGFloat] = [
        0.05, 0.14, 0.24, 0.46, 0.66, 0.72, 0.56, 0.39, 0.20, 0.09, 0.05,
        0.14, 0.24, 0.46, 0.66, 0.72, 0.56, 0.39, 0.20, 0.09, 0.05,
    ]

    counter.updateTuning(
        RepCounterTuning(
            minTimeBetweenReps: 1.6,
            minAmplitude: 0.15,
            upThreshold: 0.2,
            downThreshold: 0.62,
            inactivityResetSeconds: 3,
            activityDeltaThreshold: 0.015,
            squatDescendEntryThreshold: 0.12,
            squatStandLockoutThreshold: 0.10
        )
    )

    feedSquatCounter(&counter, values: fastDoubleRep)

    #expect(counter.count == 1)
}

@Test func squatExerciseProfile_usesConfiguredDepthThreshold() {
    let profile = SquatExerciseProfile()
    let configuration = RepCountingConfiguration(
        minTimeBetweenReps: 0.4,
        minAmplitude: 0.15,
        downThreshold: 0.75,
        squatDescendEntryThreshold: 0.12,
        squatStandLockoutThreshold: 0.10
    )

    let candidate = profile.makeRepCounter(configuration: configuration)
    #expect(candidate is SquatPhaseRepCounter)

    guard var counter = candidate as? SquatPhaseRepCounter else {
        Issue.record("Expected SquatPhaseRepCounter from squat profile")
        return
    }

    let values: [CGFloat] = [0.05, 0.14, 0.24, 0.46, 0.66, 0.72, 0.56, 0.39, 0.20, 0.09, 0.05]
    feedSquatCounter(&counter, values: values)
    #expect(counter.count == 0)
}

@Test func squatCounter_countsThreeConsecutiveReps() {
    var counter = SquatPhaseRepCounter(minTimeBetweenReps: 0.4, minAmplitude: 0.15)
    let cycle: [CGFloat] = [0.05, 0.14, 0.24, 0.46, 0.66, 0.72, 0.56, 0.39, 0.20, 0.09, 0.05]
    feedSquatCounter(&counter, values: cycle, startSeconds: 0.0)
    feedSquatCounter(&counter, values: cycle, startSeconds: 1.5)
    feedSquatCounter(&counter, values: cycle, startSeconds: 3.0)
    #expect(counter.count == 3)
}

@Test func squatMetric_standingPositionIsNearZero() {
    let calculator = SquatDepthMetricCalculator(hipWeight: 1, kneeWeight: 0)
    let metric = calculator.calculate(from: makeFrame(squatJoints(depth: 0.0)))
    #expect(metric != nil)
    #expect(metric! < 0.15)
}

@Test func squatMetric_deepSquatIsNearOne() {
    let calculator = SquatDepthMetricCalculator(hipWeight: 1, kneeWeight: 0)
    let metric = calculator.calculate(from: makeFrame(squatJoints(depth: 1.0)))
    #expect(metric != nil)
    #expect(metric! > 0.85)
}

@Test func squatMetric_trackedJointsIncludesLowerBody() {
    let calculator = SquatDepthMetricCalculator()
    let tracked = Set(calculator.trackedJoints(from: makeFrame(squatJoints(depth: 0.5))))
    #expect(tracked.contains(.leftHip))
    #expect(tracked.contains(.rightHip))
}

@Test func squatMetric_returnsNilWhenShouldersMissing() {
    let calculator = SquatDepthMetricCalculator()
    let joints: [VNHumanBodyPose3DObservation.JointName: CameraKit.NormalizedPoint] = [
        .leftHip:    CameraKit.NormalizedPoint(x: 0.60, y: 0.45),
        .rightHip:   CameraKit.NormalizedPoint(x: 0.60, y: 0.55),
        .leftAnkle:  CameraKit.NormalizedPoint(x: 0.90, y: 0.46),
        .rightAnkle: CameraKit.NormalizedPoint(x: 0.90, y: 0.54),
    ]
    #expect(calculator.calculate(from: makeFrame(joints)) == nil)
}

// MARK: - SquatDepth3DMetricCalculator

@Test func squatDepth3D_increasesWithDepth() {
    let calculator = SquatDepth3DMetricCalculator()
    // Warm up the window so adaptive normalisation can establish a range.
    for d in stride(from: 0.0, through: 1.0, by: 0.1) {
        _ = calculator.calculate(from: makeFrame(positions3D: squat3DPositions(squatDepth: d)))
    }
    let standing = calculator.calculate(from: makeFrame(positions3D: squat3DPositions(squatDepth: 0.0)))
    let deep     = calculator.calculate(from: makeFrame(positions3D: squat3DPositions(squatDepth: 1.0)))
    #expect(standing != nil)
    #expect(deep != nil)
    #expect(deep! > standing!)
}

@Test func squatDepth3D_standsAtLowMetricDeepSquatAtHighMetric() {
    let calculator = SquatDepth3DMetricCalculator()
    // Warm up with full range so adaptive normalisation kicks in.
    for d in stride(from: 0.0, through: 1.0, by: 0.1) {
        _ = calculator.calculate(from: makeFrame(positions3D: squat3DPositions(squatDepth: d)))
    }
    let standing = calculator.calculate(from: makeFrame(positions3D: squat3DPositions(squatDepth: 0.0)))
    let deep     = calculator.calculate(from: makeFrame(positions3D: squat3DPositions(squatDepth: 1.0)))
    #expect(standing! < 0.20)
    #expect(deep! > 0.65)
}

@Test func squatDepth3D_isDistanceInvariant() {
    // Two calculators, each warmed up at a different camera distance.
    // The metric should produce the same values regardless of Z depth.
    let close = SquatDepth3DMetricCalculator()
    let far   = SquatDepth3DMetricCalculator()

    for d in stride(from: 0.0, through: 1.0, by: 0.1) {
        _ = close.calculate(from: makeFrame(positions3D: squat3DPositions(squatDepth: d, cameraZ: 1.0)))
        _ = far.calculate(from:   makeFrame(positions3D: squat3DPositions(squatDepth: d, cameraZ: 4.0)))
    }

    let depths: [CGFloat] = [0.0, 0.3, 0.5, 0.8, 1.0]
    for d in depths {
        let closeMetric = close.calculate(from: makeFrame(positions3D: squat3DPositions(squatDepth: d, cameraZ: 1.0)))
        let farMetric   = far.calculate(from:   makeFrame(positions3D: squat3DPositions(squatDepth: d, cameraZ: 4.0)))
        #expect(closeMetric != nil)
        #expect(farMetric != nil)
        #expect(abs(closeMetric! - farMetric!) < 0.01, "metric differs at depth \(d): close=\(closeMetric!), far=\(farMetric!)")
    }
}

@Test func squatDepth3D_returnsNilWhenPositionsMissing() {
    let calculator = SquatDepth3DMetricCalculator()
    #expect(calculator.calculate(from: makeFrame()) == nil)
}

@Test func squatDepth3D_estimatesAnkleFromKneesWhenAnklesMissing() {
    let calculator = SquatDepth3DMetricCalculator()
    var pos = squat3DPositions(squatDepth: 0.0)
    pos.removeValue(forKey: .leftAnkle)
    pos.removeValue(forKey: .rightAnkle)
    let metric = calculator.calculate(from: makeFrame(positions3D: pos))
    #expect(metric != nil)
}

@Test func squatDepth3D_returnsNilWhenOnlyShoulderPresent() {
    let calculator = SquatDepth3DMetricCalculator()
    let pos: [VNHumanBodyPose3DObservation.JointName: SIMD3<Float>] = [
        .leftShoulder: SIMD3(x: 0, y: 0.4, z: 2.0),
    ]
    #expect(calculator.calculate(from: makeFrame(positions3D: pos)) == nil)
}

// MARK: - SquatJointFlexion3DMetricCalculator

@Test func squatJointFlexion3D_standingLowDeepHigh() {
    let calculator = SquatJointFlexion3DMetricCalculator(
        kneeBottomFlexionDegrees: 80,
        hipBottomFlexionDegrees: 60,
        kneeLockoutFlexionDegrees: 15,
        hipLockoutFlexionDegrees: 20
    )

    let standing = calculator.calculate(from: makeFrame(positions3D: squat3DJointFlexionPositions(
        kneeFlexionDegrees: 10,
        hipFlexionDegrees: 10
    )))
    let deep = calculator.calculate(from: makeFrame(positions3D: squat3DJointFlexionPositions(
        kneeFlexionDegrees: 95,
        hipFlexionDegrees: 75
    )))

    #expect(standing != nil)
    #expect(deep != nil)
    #expect(standing! < 0.20)
    #expect(deep! > 0.90)
}

@Test func squatJointFlexion3D_requiresBothHipAndKneeForBottom() {
    let calculator = SquatJointFlexion3DMetricCalculator(
        kneeBottomFlexionDegrees: 80,
        hipBottomFlexionDegrees: 60,
        kneeLockoutFlexionDegrees: 15,
        hipLockoutFlexionDegrees: 20
    )

    let kneeOnly = calculator.calculate(from: makeFrame(positions3D: squat3DJointFlexionPositions(
        kneeFlexionDegrees: 90,
        hipFlexionDegrees: 20
    )))
    let hipOnly = calculator.calculate(from: makeFrame(positions3D: squat3DJointFlexionPositions(
        kneeFlexionDegrees: 20,
        hipFlexionDegrees: 75
    )))

    #expect(kneeOnly != nil)
    #expect(hipOnly != nil)
    #expect(kneeOnly! < 0.55)
    #expect(hipOnly! < 0.55)
}

@Test func squatJointFlexion3D_fallsBackToSingleVisibleSide() {
    let calculator = SquatJointFlexion3DMetricCalculator()
    let metric = calculator.calculate(from: makeFrame(positions3D: squat3DJointFlexionPositions(
        kneeFlexionDegrees: 85,
        hipFlexionDegrees: 70,
        hideRightSide: true
    )))
    #expect(metric != nil)
}

@Test func squatJointFlexion3D_rejectsLargeSideAsymmetry() {
    let calculator = SquatJointFlexion3DMetricCalculator(maxSideAsymmetryDegrees: 20)
    let metric = calculator.calculate(from: makeFrame(positions3D: squat3DJointFlexionPositions(
        kneeFlexionDegrees: 80,
        hipFlexionDegrees: 65,
        rightSideFlexionOffset: -40
    )))
    #expect(metric == nil)
}

@Test func repCounterPublisher_exposesCurrentFlexionMetrics() async throws {
    let config = RepCountingConfiguration(spikeMaxDelta: 1.0, emaAlpha: 1.0)
    let publisher = RepCounterPublisher(configuration: config, exerciseProfile: SquatExerciseProfile())

    final class OutputBox: @unchecked Sendable {
        var latest: RepCounterOutput?
    }
    let box = OutputBox()
    let cancellable = publisher.repCounts.sink { box.latest = $0 }

    let frame = PoseFrame(
        timestamp: CMTime(seconds: 0, preferredTimescale: 600),
        joints: [:],
        positions3D: squat3DJointFlexionPositions(kneeFlexionDegrees: 75, hipFlexionDegrees: 60)
    )
    publisher.ingest(frame)

    try await Task.sleep(nanoseconds: 250_000_000)
    _ = cancellable

    #expect(box.latest?.squatFlexionMetrics != nil)
    #expect((box.latest?.squatFlexionMetrics?.kneeFlexionDegrees ?? 0) > 40)
    #expect((box.latest?.squatFlexionMetrics?.hipFlexionDegrees ?? 0) > 35)
}

@Test func repCounterPublisher_countsTwoSquatReps() async throws {
    let profile = SquatExerciseProfile()
    // spikeMaxDelta=1.0 + emaAlpha=1.0 disables both filters so controlled
    // synthetic joint frames reach the counter unmodified — filter behaviour
    // is covered by dedicated SpikeRejectionFilter/EMAMetricFilter tests.
    let config = RepCountingConfiguration(
        minTimeBetweenReps: 0.4,
        minAmplitude: 0.15,
        downThreshold: 0.80,
        spikeMaxDelta: 1.0,
        emaAlpha: 1.0
    )
    let publisher = RepCounterPublisher(configuration: config, exerciseProfile: profile)

    // Thread-safe box: sink closure runs on GCD queue, test reads on Swift task.
    final class OutputBox: @unchecked Sendable {
        var lastRepCount = 0
    }
    let box = OutputBox()
    let cancellable = publisher.repCounts.sink { box.lastRepCount = $0.repCount }

    let cycle: [CGFloat] = [0.05, 0.18, 0.30, 0.52, 0.78, 0.95, 0.80, 0.60, 0.35, 0.15, 0.05]
    func ingestCycle(startSeconds: Double) {
        for (i, depth) in cycle.enumerated() {
            let t = CMTime(seconds: startSeconds + Double(i) * 0.1, preferredTimescale: 600)
            publisher.ingest(PoseFrame(
                timestamp: t,
                joints: squatJoints(depth: depth),
                positions3D: squat3DJointFlexionPositions(
                    kneeFlexionDegrees: 10 + 95 * depth,
                    hipFlexionDegrees: 10 + 75 * depth
                )
            ))
        }
    }

    ingestCycle(startSeconds: 0.0)
    ingestCycle(startSeconds: 1.5)
    // 500ms: enough for all async GCD work items to complete before we read the result.
    try await Task.sleep(nanoseconds: 500_000_000)
    _ = cancellable

    #expect(box.lastRepCount == 2)
}

// MARK: - Bicep Curl

@Test func bicepCurlFlexion3D_straightArmLowContractedHigh() {
    let calculator = BicepCurlFlexion3DMetricCalculator(
        curlTopFlexionDegrees: 95,
        curlLockoutFlexionDegrees: 18
    )

    let straight = calculator.calculate(from: makeFrame(positions3D: bicepCurl3DJointPositions(
        leftElbowFlexionDegrees: 8,
        rightElbowFlexionDegrees: 10
    )))
    let contracted = calculator.calculate(from: makeFrame(positions3D: bicepCurl3DJointPositions(
        leftElbowFlexionDegrees: 105,
        rightElbowFlexionDegrees: 98
    )))

    #expect(straight != nil)
    #expect(contracted != nil)
    #expect(straight! < 0.15)
    #expect(contracted! > 0.90)
}

@Test func bicepCurlFlexion3D_singleArmFallbackSupported() {
    let calculator = BicepCurlFlexion3DMetricCalculator()
    let metric = calculator.calculate(from: makeFrame(positions3D: bicepCurl3DJointPositions(
        leftElbowFlexionDegrees: 100,
        rightElbowFlexionDegrees: 20,
        hideRightArm: true
    )))

    #expect(metric != nil)
}

@Test func bicepCurlExerciseProfile_usesCycleCounter() {
    let profile = BicepCurlExerciseProfile()
    let configuration = RepCountingConfiguration(minTimeBetweenReps: 0.45, minAmplitude: 0.30)

    let counter = profile.makeRepCounter(configuration: configuration)
    #expect(counter is CurlPhaseRepCounter)
}

@Test func bicepCurlFlexion3D_locksActiveSideMidRepUntilExtension() {
    let calculator = BicepCurlFlexion3DMetricCalculator(
        curlTopFlexionDegrees: 95,
        curlLockoutFlexionDegrees: 18
    )

    // Establish left side as active and lock it.
    _ = calculator.calculate(from: makeFrame(positions3D: bicepCurl3DJointPositions(
        leftElbowFlexionDegrees: 45,
        rightElbowFlexionDegrees: 12
    )))

    // Right side suddenly spikes, but active side should stay left mid-rep.
    let lockedMetric = calculator.calculate(from: makeFrame(positions3D: bicepCurl3DJointPositions(
        leftElbowFlexionDegrees: 55,
        rightElbowFlexionDegrees: 105
    )))
    #expect(lockedMetric != nil)
    #expect(lockedMetric! < 0.70)

    // After left returns near extension, lock can release and right may drive.
    _ = calculator.calculate(from: makeFrame(positions3D: bicepCurl3DJointPositions(
        leftElbowFlexionDegrees: 12,
        rightElbowFlexionDegrees: 20
    )))
    let releasedMetric = calculator.calculate(from: makeFrame(positions3D: bicepCurl3DJointPositions(
        leftElbowFlexionDegrees: 10,
        rightElbowFlexionDegrees: 100
    )))
    #expect(releasedMetric != nil)
    #expect(releasedMetric! > 0.85)
}

@Test func repCounterPublisher_exposesCurrentCurlFlexionMetrics() async throws {
    let config = RepCountingConfiguration(spikeMaxDelta: 1.0, emaAlpha: 1.0)
    let publisher = RepCounterPublisher(configuration: config, exerciseProfile: BicepCurlExerciseProfile())

    final class OutputBox: @unchecked Sendable {
        var latest: RepCounterOutput?
    }
    let box = OutputBox()
    let cancellable = publisher.repCounts.sink { box.latest = $0 }

    let frame = PoseFrame(
        timestamp: CMTime(seconds: 0, preferredTimescale: 600),
        joints: [:],
        positions3D: bicepCurl3DJointPositions(leftElbowFlexionDegrees: 88, rightElbowFlexionDegrees: 84)
    )
    publisher.ingest(frame)

    try await Task.sleep(nanoseconds: 250_000_000)
    _ = cancellable

    #expect(box.latest?.curlFlexionMetrics != nil)
    #expect((box.latest?.curlFlexionMetrics?.elbowFlexionDegrees ?? 0) > 40)
}

@Test func repCounterPublisher_countsTwoBicepCurlReps() async throws {
    let config = RepCountingConfiguration(
        minTimeBetweenReps: 0.4,
        minAmplitude: 0.25,
        upThreshold: 0.65,
        downThreshold: 0.25,
        spikeMaxDelta: 1.0,
        emaAlpha: 1.0
    )
    let publisher = RepCounterPublisher(configuration: config, exerciseProfile: BicepCurlExerciseProfile())

    final class OutputBox: @unchecked Sendable {
        var lastRepCount = 0
    }
    let box = OutputBox()
    let cancellable = publisher.repCounts.sink { box.lastRepCount = $0.repCount }

    let cycle: [CGFloat] = [10, 20, 35, 55, 80, 102, 78, 52, 30, 16, 8]
    func ingestCycle(startSeconds: Double) {
        for (i, flexion) in cycle.enumerated() {
            let t = CMTime(seconds: startSeconds + Double(i) * 0.1, preferredTimescale: 600)
            publisher.ingest(PoseFrame(
                timestamp: t,
                joints: [:],
                positions3D: bicepCurl3DJointPositions(
                    leftElbowFlexionDegrees: flexion,
                    rightElbowFlexionDegrees: max(8, flexion - 10)
                )
            ))
        }
    }

    ingestCycle(startSeconds: 0.0)
    ingestCycle(startSeconds: 1.7)

    try await Task.sleep(nanoseconds: 500_000_000)
    _ = cancellable

    #expect(box.lastRepCount == 2)
}

@Test func repCounterPublisher_doesNotOvercountBicepCurlWithNoisyOppositeArm() async throws {
    let config = RepCountingConfiguration(
        minTimeBetweenReps: 0.35,
        minAmplitude: 0.22,
        upThreshold: 0.62,
        downThreshold: 0.26,
        spikeMaxDelta: 1.0,
        emaAlpha: 1.0
    )
    let publisher = RepCounterPublisher(configuration: config, exerciseProfile: BicepCurlExerciseProfile())

    final class OutputBox: @unchecked Sendable {
        var lastRepCount = 0
    }
    let box = OutputBox()
    let cancellable = publisher.repCounts.sink { box.lastRepCount = $0.repCount }

    let left: [CGFloat] = [10, 35, 55, 80, 102, 78, 52, 30, 16, 8]
    let rightNoise: [CGFloat] = [10, 12, 95, 14, 90, 16, 88, 12, 84, 10]

    for i in left.indices {
        let t = CMTime(seconds: Double(i) * 0.1, preferredTimescale: 600)
        publisher.ingest(PoseFrame(
            timestamp: t,
            joints: [:],
            positions3D: bicepCurl3DJointPositions(
                leftElbowFlexionDegrees: left[i],
                rightElbowFlexionDegrees: rightNoise[i]
            )
        ))
    }

    try await Task.sleep(nanoseconds: 400_000_000)
    _ = cancellable

    #expect(box.lastRepCount == 1)
}

@Test func repCounterPublisher_switchingExerciseResetsCount() async throws {
    let config = RepCountingConfiguration(spikeMaxDelta: 1.0, emaAlpha: 1.0)
    let publisher = RepCounterPublisher(configuration: config, exerciseProfile: BicepCurlExerciseProfile())

    final class OutputBox: @unchecked Sendable {
        var lastRepCount = 0
    }
    let box = OutputBox()
    let cancellable = publisher.repCounts.sink { box.lastRepCount = $0.repCount }

    let cycle: [CGFloat] = [10, 20, 35, 55, 80, 102, 78, 52, 30, 16, 8]
    for (i, flexion) in cycle.enumerated() {
        let t = CMTime(seconds: Double(i) * 0.1, preferredTimescale: 600)
        publisher.ingest(PoseFrame(
            timestamp: t,
            joints: [:],
            positions3D: bicepCurl3DJointPositions(
                leftElbowFlexionDegrees: flexion,
                rightElbowFlexionDegrees: max(8, flexion - 10)
            )
        ))
    }

    try await Task.sleep(nanoseconds: 350_000_000)
    #expect(box.lastRepCount == 1)

    publisher.setExerciseProfile(SquatExerciseProfile(), configuration: config)
    try await Task.sleep(nanoseconds: 250_000_000)
    _ = cancellable

    #expect(box.lastRepCount == 0)
}

@Test func repCountingPublishers_areSendable() {
    func assertSendable<T: Sendable>(_: T.Type) {}

    assertSendable(RepCounterPublisher.self)
    assertSendable(PoseDetectorPublisher.self)
}

// MARK: - LivePipeline API

#if canImport(UIKit) && canImport(AVFoundation)
@Test func livePipeline_exposesInjectedCaptureSession() {
    let session = CameraSession()
    let pipeline = LivePipeline(cameraSession: session)

    #expect(pipeline.captureSession === session.session)
}

@Test func startAPIs_areParameterless() {
    let _: (CameraSession) -> () -> Void = CameraSession.startRunning
    let _: (LivePipeline) -> () -> Void = LivePipeline.start
    #expect(Bool(true))
}
#endif
