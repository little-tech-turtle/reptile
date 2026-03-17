import Foundation
import Combine
import CoreMedia
import OSLog
import Vision

private let logger = Logger(subsystem: "CameraKit", category: "repCounting")

/// Quality of pose detection for rep counting
public enum DetectionQuality: Sendable {
    case good    // Most joints visible
    case partial // Some joints visible
    case poor    // Very few joints visible
}

public struct RepCountingConfiguration: Sendable {
    public var armingThreshold: CGFloat
    public var peakHistoryCapacity: Int
    public var minPeakHeight: CGFloat
    public var minValleyDepth: CGFloat
    public var peakWindowSize: Int
    public var minTimeBetweenReps: Double
    public var minAmplitude: CGFloat
    public var upThreshold: CGFloat
    public var downThreshold: CGFloat
    public var inactivityResetSeconds: Double
    public var activityDeltaThreshold: CGFloat
    public var spikeMaxDelta: CGFloat
    public var emaAlpha: CGFloat

    public init(
        armingThreshold: CGFloat = 0.5,
        peakHistoryCapacity: Int = 90,
        minPeakHeight: CGFloat = 0.08,
        minValleyDepth: CGFloat = 0.08,
        peakWindowSize: Int = 5,
        minTimeBetweenReps: Double = 0.5,
        minAmplitude: CGFloat = 0.15,
        upThreshold: CGFloat = 0.6,
        downThreshold: CGFloat = 0.3,
        inactivityResetSeconds: Double = 3.0,
        activityDeltaThreshold: CGFloat = 0.015,
        spikeMaxDelta: CGFloat = 0.25,
        emaAlpha: CGFloat = 0.3
    ) {
        self.armingThreshold = armingThreshold
        self.peakHistoryCapacity = peakHistoryCapacity
        self.minPeakHeight = minPeakHeight
        self.minValleyDepth = minValleyDepth
        self.peakWindowSize = peakWindowSize
        self.minTimeBetweenReps = minTimeBetweenReps
        self.minAmplitude = minAmplitude
        self.upThreshold = upThreshold
        self.downThreshold = downThreshold
        self.inactivityResetSeconds = inactivityResetSeconds
        self.activityDeltaThreshold = activityDeltaThreshold
        self.spikeMaxDelta = spikeMaxDelta
        self.emaAlpha = emaAlpha
    }
}

/// Output from rep counter including pose and rep count
public struct RepCounterOutput: Sendable {
    public let poseFrame: PoseFrame
    public let repCount: Int
    public let currentMetric: CGFloat?
    public let state: RepCounterState
    public let detectionQuality: DetectionQuality
    public let runningMax: CGFloat
    public let trackedJoints: [VNHumanBodyPose3DObservation.JointName]

    public init(
        poseFrame: PoseFrame,
        repCount: Int,
        currentMetric: CGFloat?,
        state: RepCounterState,
        detectionQuality: DetectionQuality,
        runningMax: CGFloat = 0,
        trackedJoints: [VNHumanBodyPose3DObservation.JointName] = []
    ) {
        self.poseFrame = poseFrame
        self.repCount = repCount
        self.currentMetric = currentMetric
        self.state = state
        self.detectionQuality = detectionQuality
        self.runningMax = runningMax
        self.trackedJoints = trackedJoints
    }
}

/// Orchestrates metric calculation, peak detection, and rep counting
public final class RepCounterPublisher {
    private let subject = PassthroughSubject<RepCounterOutput, Never>()
    private let processingQueue = DispatchQueue(label: "camerakit.repcount.processing")
    private var metricCalculator: any MetricCalculator
    private var peakDetector: any PeakDetector
    private var repCounter: any RepCounter
    private var metricFilters: [any MetricFilter]
    private let armingThreshold: CGFloat
    private var metricWindow: [CGFloat] = []
    private let metricWindowCapacity = 60
    private var runningMax: CGFloat { metricWindow.max() ?? 0 }

    public var repCounts: AnyPublisher<RepCounterOutput, Never> {
        subject.eraseToAnyPublisher()
    }

    public init(
        metricCalculator: any MetricCalculator = AdaptiveDominantAxisCalculator(),
        peakDetector: any PeakDetector = LocalExtremaPeakDetector(),
        repCounter: any RepCounter = CycleBasedRepCounter(),
        metricFilters: [any MetricFilter] = [SpikeRejectionFilter(), EMAMetricFilter()],
        armingThreshold: CGFloat = 0.5
    ) {
        self.metricCalculator = metricCalculator
        self.peakDetector = peakDetector
        self.repCounter = repCounter
        self.metricFilters = metricFilters
        self.armingThreshold = armingThreshold
    }

    public convenience init(
        configuration: RepCountingConfiguration,
        metricCalculator: any MetricCalculator = AdaptiveDominantAxisCalculator()
    ) {
        self.init(
            metricCalculator: metricCalculator,
            peakDetector: LocalExtremaPeakDetector(
                historyCapacity: configuration.peakHistoryCapacity,
                minPeakHeight: configuration.minPeakHeight,
                minValleyDepth: configuration.minValleyDepth,
                windowSize: configuration.peakWindowSize
            ),
            repCounter: CycleBasedRepCounter(
                minTimeBetweenReps: configuration.minTimeBetweenReps,
                minAmplitude: configuration.minAmplitude,
                upThreshold: configuration.upThreshold,
                downThreshold: configuration.downThreshold,
                inactivityResetSeconds: configuration.inactivityResetSeconds,
                activityDeltaThreshold: configuration.activityDeltaThreshold
            ),
            metricFilters: [
                SpikeRejectionFilter(maxDelta: configuration.spikeMaxDelta),
                EMAMetricFilter(alpha: configuration.emaAlpha),
            ],
            armingThreshold: configuration.armingThreshold
        )
    }

    public func ingest(_ poseFrame: PoseFrame) {
        processingQueue.async { [weak self] in
            self?.process(poseFrame)
        }
    }

    private func process(_ poseFrame: PoseFrame) {
        guard let metric = metricCalculator.calculate(from: poseFrame.joints) else {
            sendOutput(
                poseFrame: poseFrame,
                metric: nil,
                quality: .poor,
                trackedJoints: metricCalculator.trackedJoints(from: poseFrame.joints)
            )
            return
        }

        let trackedJoints = metricCalculator.trackedJoints(from: poseFrame.joints)

        // Explicit write-back guards against Swift existential mutation edge cases
        var filteredMetric = metric
        for i in metricFilters.indices {
            var f = metricFilters[i]
            filteredMetric = f.filter(filteredMetric)
            metricFilters[i] = f
        }
        logger.debug("metric=\(filteredMetric, format: .fixed(precision: 3))")

        repCounter.ingestSample(timestamp: poseFrame.timestamp, metricValue: filteredMetric)

        metricWindow.append(filteredMetric)
        if metricWindow.count > metricWindowCapacity { metricWindow.removeFirst() }

        // Threshold-based arming: keep the counter armed whenever we're clearly
        // above the "standing" position, even when no sharp EMA peak is detected.
        if filteredMetric > armingThreshold {
            repCounter.processPeak(.maximum, timestamp: poseFrame.timestamp, metricValue: runningMax)
        }

        let sample = MetricSample(timestamp: poseFrame.timestamp, value: filteredMetric)

        let previousCount = repCounter.count
        if let peak = peakDetector.ingest(sample) {
            switch peak {
            case .minimum:
                repCounter.processPeak(.minimum, timestamp: poseFrame.timestamp, metricValue: filteredMetric)
            case .maximum:
                // Redundant when arming threshold fired, but kept for protocol contract
                repCounter.processPeak(.maximum, timestamp: poseFrame.timestamp, metricValue: runningMax)
            }
        }
        if repCounter.count != previousCount {
            logger.info("Rep counted — total=\(self.repCounter.count) state=\(self.repCounter.state.rawValue)")
        }

        let quality: DetectionQuality = poseFrame.joints.count >= 10 ? .good :
                                        poseFrame.joints.count >= 5 ? .partial : .poor

        sendOutput(
            poseFrame: poseFrame,
            metric: filteredMetric,
            quality: quality,
            trackedJoints: trackedJoints
        )
    }

    private func sendOutput(
        poseFrame: PoseFrame,
        metric: CGFloat?,
        quality: DetectionQuality,
        trackedJoints: [VNHumanBodyPose3DObservation.JointName]
    ) {
        let output = RepCounterOutput(
            poseFrame: poseFrame,
            repCount: repCounter.count,
            currentMetric: metric,
            state: repCounter.state,
            detectionQuality: quality,
            runningMax: runningMax,
            trackedJoints: trackedJoints
        )
        subject.send(output)
    }

    public func reset() {
        processingQueue.async { [weak self] in
            guard let self else { return }
            self.repCounter.reset()
            self.metricWindow.removeAll()
        }
    }
}
