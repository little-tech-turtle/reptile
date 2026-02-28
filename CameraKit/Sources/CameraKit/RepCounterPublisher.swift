import Foundation
import Combine
import CoreMedia

/// Quality of pose detection for rep counting
public enum DetectionQuality: Sendable {
    case good    // Most joints visible
    case partial // Some joints visible
    case poor    // Very few joints visible
}

/// Output from rep counter including pose and rep count
public struct RepCounterOutput: Sendable {
    public let poseFrame: PoseFrame
    public let repCount: Int
    public let currentMetric: CGFloat?
    public let state: RepCounterState
    public let detectionQuality: DetectionQuality

    public init(
        poseFrame: PoseFrame,
        repCount: Int,
        currentMetric: CGFloat?,
        state: RepCounterState,
        detectionQuality: DetectionQuality
    ) {
        self.poseFrame = poseFrame
        self.repCount = repCount
        self.currentMetric = currentMetric
        self.state = state
        self.detectionQuality = detectionQuality
    }
}

/// Orchestrates metric calculation, peak detection, and rep counting
public final class RepCounterPublisher {
    private let subject = PassthroughSubject<RepCounterOutput, Never>()
    private var metricCalculator: any MetricCalculator
    private var peakDetector: any PeakDetector
    private var repCounter: any RepCounter

    public var repCounts: AnyPublisher<RepCounterOutput, Never> {
        subject.eraseToAnyPublisher()
    }

    public init(
        metricCalculator: any MetricCalculator = DistanceFromFloorCalculator(),
        peakDetector: any PeakDetector = LocalExtremaPeakDetector(),
        repCounter: any RepCounter = CycleBasedRepCounter()
    ) {
        self.metricCalculator = metricCalculator
        self.peakDetector = peakDetector
        self.repCounter = repCounter
    }

    public func ingest(_ poseFrame: PoseFrame) {
        guard let metric = metricCalculator.calculate(from: poseFrame.joints) else {
            sendOutput(poseFrame: poseFrame, metric: nil, quality: .poor)
            return
        }

        let sample = MetricSample(timestamp: poseFrame.timestamp, value: metric)

        if let peak = peakDetector.ingest(sample) {
            repCounter.processPeak(peak, timestamp: poseFrame.timestamp, metricValue: metric)
        }

        let quality: DetectionQuality = poseFrame.joints.count >= 10 ? .good :
                                        poseFrame.joints.count >= 5 ? .partial : .poor

        sendOutput(poseFrame: poseFrame, metric: metric, quality: quality)
    }

    private func sendOutput(poseFrame: PoseFrame, metric: CGFloat?, quality: DetectionQuality) {
        let output = RepCounterOutput(
            poseFrame: poseFrame,
            repCount: repCounter.count,
            currentMetric: metric,
            state: repCounter.state,
            detectionQuality: quality
        )
        subject.send(output)
    }

    public func reset() {
        repCounter.reset()
    }
}
