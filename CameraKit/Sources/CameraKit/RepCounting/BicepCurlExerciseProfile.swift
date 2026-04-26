import Foundation

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
        CurlPhaseRepCounter(
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
