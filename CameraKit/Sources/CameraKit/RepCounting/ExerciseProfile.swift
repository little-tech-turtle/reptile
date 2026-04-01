import Foundation

public protocol ExerciseProfile {
    var id: String { get }

    func makeMetricCalculator(configuration: RepCountingConfiguration) -> any MetricCalculator
    func makePeakDetector(configuration: RepCountingConfiguration) -> any PeakDetector
    func makeRepCounter(configuration: RepCountingConfiguration) -> any RepCounter
    func makeMetricFilters(configuration: RepCountingConfiguration) -> [any MetricFilter]
}

public struct SquatExerciseProfile: ExerciseProfile {
    public let id: String = "squat"

    public init() {}

    public func makeMetricCalculator(configuration: RepCountingConfiguration) -> any MetricCalculator {
        SquatJointFlexion3DMetricCalculator(
            kneeBottomFlexionDegrees: configuration.squatKneeBottomFlexionDegrees,
            hipBottomFlexionDegrees: configuration.squatHipBottomFlexionDegrees,
            kneeLockoutFlexionDegrees: configuration.squatKneeLockoutFlexionDegrees,
            hipLockoutFlexionDegrees: configuration.squatHipLockoutFlexionDegrees,
            maxSideAsymmetryDegrees: configuration.squatMaxSideAsymmetryDegrees
        )
    }

    public func makePeakDetector(configuration: RepCountingConfiguration) -> any PeakDetector {
        LocalExtremaPeakDetector(
            historyCapacity: configuration.peakHistoryCapacity,
            minPeakHeight: configuration.minPeakHeight,
            minValleyDepth: configuration.minValleyDepth,
            windowSize: configuration.peakWindowSize
        )
    }

    public func makeRepCounter(configuration: RepCountingConfiguration) -> any RepCounter {
        SquatPhaseRepCounter(
            minTimeBetweenReps: configuration.minTimeBetweenReps,
            minAmplitude: configuration.minAmplitude,
            upThreshold: configuration.upThreshold,
            downThreshold: configuration.downThreshold,
            inactivityResetSeconds: configuration.inactivityResetSeconds,
            activityDeltaThreshold: configuration.activityDeltaThreshold,
            descendEntryThreshold: configuration.squatDescendEntryThreshold,
            standLockoutThreshold: configuration.squatStandLockoutThreshold
        )
    }

    public func makeMetricFilters(configuration: RepCountingConfiguration) -> [any MetricFilter] {
        [
            SpikeRejectionFilter(maxDelta: configuration.spikeMaxDelta),
            EMAMetricFilter(alpha: configuration.emaAlpha),
        ]
    }
}

public struct BicepCurlExerciseProfile: ExerciseProfile {
    public let id: String = "bicepCurl"

    public init() {}

    public func makeMetricCalculator(configuration: RepCountingConfiguration) -> any MetricCalculator {
        BicepCurlFlexion3DMetricCalculator(
            curlTopFlexionDegrees: configuration.curlTopFlexionDegrees,
            curlLockoutFlexionDegrees: configuration.curlLockoutFlexionDegrees
        )
    }

    public func makePeakDetector(configuration: RepCountingConfiguration) -> any PeakDetector {
        LocalExtremaPeakDetector(
            historyCapacity: configuration.peakHistoryCapacity,
            minPeakHeight: configuration.minPeakHeight,
            minValleyDepth: configuration.minValleyDepth,
            windowSize: configuration.peakWindowSize
        )
    }

    public func makeRepCounter(configuration: RepCountingConfiguration) -> any RepCounter {
        CycleBasedRepCounter(
            minTimeBetweenReps: configuration.minTimeBetweenReps,
            minAmplitude: configuration.minAmplitude,
            upThreshold: configuration.upThreshold,
            downThreshold: configuration.downThreshold,
            inactivityResetSeconds: configuration.inactivityResetSeconds,
            activityDeltaThreshold: configuration.activityDeltaThreshold
        )
    }

    public func makeMetricFilters(configuration: RepCountingConfiguration) -> [any MetricFilter] {
        [
            SpikeRejectionFilter(maxDelta: configuration.spikeMaxDelta),
            EMAMetricFilter(alpha: configuration.emaAlpha),
        ]
    }
}
