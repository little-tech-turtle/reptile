import Foundation
import CoreMedia
import Vision

public let repProcessingContractVersion = 1

public struct RepCountingProcessingEnvironment {
    public var metricCalculator: any MetricCalculator
    public var peakDetector: any PeakDetector
    public var repCounter: any RepCounter
    public var metricFilters: [any MetricFilter]
    public var armingThreshold: CGFloat
    public var metricWindow: [CGFloat]
    public let metricWindowCapacity: Int
    public var exerciseProfileID: String

    public init(
        metricCalculator: any MetricCalculator,
        peakDetector: any PeakDetector,
        repCounter: any RepCounter,
        metricFilters: [any MetricFilter],
        armingThreshold: CGFloat,
        metricWindow: [CGFloat],
        metricWindowCapacity: Int,
        exerciseProfileID: String
    ) {
        self.metricCalculator = metricCalculator
        self.peakDetector = peakDetector
        self.repCounter = repCounter
        self.metricFilters = metricFilters
        self.armingThreshold = armingThreshold
        self.metricWindow = metricWindow
        self.metricWindowCapacity = metricWindowCapacity
        self.exerciseProfileID = exerciseProfileID
    }

    public var runningMax: CGFloat { metricWindow.max() ?? 0 }
}

public struct RepCountingProcessResult {
    public let metric: CGFloat?
    public let quality: DetectionQuality
    public let trackedJoints: [VNHumanBodyPose3DObservation.JointName]
    public let exerciseDiagnostics: ExerciseDiagnostics?
    public let statusHint: String?

    public init(
        metric: CGFloat?,
        quality: DetectionQuality,
        trackedJoints: [VNHumanBodyPose3DObservation.JointName],
        exerciseDiagnostics: ExerciseDiagnostics?,
        statusHint: String? = nil
    ) {
        self.metric = metric
        self.quality = quality
        self.trackedJoints = trackedJoints
        self.exerciseDiagnostics = exerciseDiagnostics
        self.statusHint = statusHint
    }
}

public protocol ExerciseProcessingStrategy {
    mutating func process(
        _ poseFrame: PoseFrame,
        environment: inout RepCountingProcessingEnvironment
    ) -> RepCountingProcessResult

    mutating func reset()
}

public struct SquatProcessingStrategy: ExerciseProcessingStrategy {
    public init() {}

    public mutating func process(
        _ poseFrame: PoseFrame,
        environment: inout RepCountingProcessingEnvironment
    ) -> RepCountingProcessResult {
        let exerciseDiagnostics = (environment.metricCalculator as? any ExerciseDiagnosticsProvider)?.diagnostics(from: poseFrame)

        guard let metric = environment.metricCalculator.calculate(from: poseFrame) else {
            return RepCountingProcessResult(
                metric: nil,
                quality: .poor,
                trackedJoints: environment.metricCalculator.trackedJoints(from: poseFrame),
                exerciseDiagnostics: exerciseDiagnostics
            )
        }

        let trackedJoints = environment.metricCalculator.trackedJoints(from: poseFrame)

        var filteredMetric = metric
        for i in environment.metricFilters.indices {
            var filter = environment.metricFilters[i]
            filteredMetric = filter.filter(filteredMetric)
            environment.metricFilters[i] = filter
        }

        environment.repCounter.ingestSample(timestamp: poseFrame.timestamp, metricValue: filteredMetric)

        environment.metricWindow.append(filteredMetric)
        if environment.metricWindow.count > environment.metricWindowCapacity {
            environment.metricWindow.removeFirst()
        }

        if environment.repCounter.consumesPeakEvents {
            if filteredMetric > environment.armingThreshold {
                environment.repCounter.processPeak(.maximum, timestamp: poseFrame.timestamp, metricValue: environment.runningMax)
            }

            let sample = MetricSample(timestamp: poseFrame.timestamp, value: filteredMetric)
            if let peak = environment.peakDetector.ingest(sample) {
                switch peak {
                case .minimum:
                    environment.repCounter.processPeak(.minimum, timestamp: poseFrame.timestamp, metricValue: filteredMetric)
                case .maximum:
                    environment.repCounter.processPeak(.maximum, timestamp: poseFrame.timestamp, metricValue: environment.runningMax)
                }
            }
        }

        let quality: DetectionQuality = poseFrame.joints.count >= 10 ? .good :
            poseFrame.joints.count >= 5 ? .partial : .poor

        return RepCountingProcessResult(
            metric: filteredMetric,
            quality: quality,
            trackedJoints: trackedJoints,
            exerciseDiagnostics: exerciseDiagnostics
        )
    }

    public mutating func reset() {}
}
