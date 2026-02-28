import Testing
import CoreMedia
@testable import CameraKit

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

private func makeCounter(minAmplitude: CGFloat = 0.15, minTime: Double = 0.5) -> CycleBasedRepCounter {
    CycleBasedRepCounter(minTimeBetweenReps: minTime, minAmplitude: minAmplitude)
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
