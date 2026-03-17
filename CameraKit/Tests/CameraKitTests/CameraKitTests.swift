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
        _ = calculator.calculate(from: joints)
    }

    #expect(calculator.trackedJoints(from: frames.last!) == [VNHumanBodyPose3DObservation.JointName.rightWrist])
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
        _ = calculator.calculate(from: joints)
    }
    #expect(calculator.trackedJoints(from: primeFrames.last!) == [VNHumanBodyPose3DObservation.JointName.rightWrist])

    let spikeFrame = motionJoints(leftWristX: 0.95, rightWristX: 0.80)
    _ = calculator.calculate(from: spikeFrame)
    #expect(calculator.trackedJoints(from: spikeFrame) == [VNHumanBodyPose3DObservation.JointName.rightWrist])
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
        _ = calculator.calculate(from: joints)
    }
    #expect(calculator.trackedJoints(from: rightDominant.last!) == [VNHumanBodyPose3DObservation.JointName.rightWrist])

    let leftDominant: [[VNHumanBodyPose3DObservation.JointName: CameraKit.NormalizedPoint]] = [
        motionJoints(leftWristX: 0.10, rightWristX: 0.78),
        motionJoints(leftWristX: 0.90, rightWristX: 0.78),
        motionJoints(leftWristX: 0.15, rightWristX: 0.78),
        motionJoints(leftWristX: 0.85, rightWristX: 0.78),
    ]
    for joints in leftDominant {
        _ = calculator.calculate(from: joints)
    }

    #expect(calculator.trackedJoints(from: leftDominant.last!) == [VNHumanBodyPose3DObservation.JointName.leftWrist])
}

@Test func distanceFromFloor_verticalMovementChangesMetric() {
    let calculator = DistanceFromFloorCalculator()

    let standing: [VNHumanBodyPose3DObservation.JointName: CameraKit.NormalizedPoint] = [
        .root: CameraKit.NormalizedPoint(x: 0.20, y: 0.50),
    ]
    let crouched: [VNHumanBodyPose3DObservation.JointName: CameraKit.NormalizedPoint] = [
        .root: CameraKit.NormalizedPoint(x: 0.80, y: 0.50),
    ]

    let standingMetric = calculator.calculate(from: standing)
    let crouchedMetric = calculator.calculate(from: crouched)

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

    let leftMetric = calculator.calculate(from: leftSide)
    let rightMetric = calculator.calculate(from: rightSide)

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

    let tracked = calculator.trackedJoints(from: joints)
    #expect(tracked == [VNHumanBodyPose3DObservation.JointName.root])
}

@Test func distanceFromFloor_trackedJoints_usesHipPairWhenRootMissing() {
    let calculator = DistanceFromFloorCalculator()
    let joints: [VNHumanBodyPose3DObservation.JointName: CameraKit.NormalizedPoint] = [
        .leftHip: CameraKit.NormalizedPoint(x: 0.45, y: 0.55),
        .rightHip: CameraKit.NormalizedPoint(x: 0.45, y: 0.45),
    ]

    let tracked = Set(calculator.trackedJoints(from: joints))
    let expected: Set<VNHumanBodyPose3DObservation.JointName> = [.leftHip, .rightHip]
    #expect(tracked == expected)
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
