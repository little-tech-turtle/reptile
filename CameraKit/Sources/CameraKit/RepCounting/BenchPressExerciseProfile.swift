import Foundation

public struct BenchPressExerciseProfile: ExerciseProfile {
    public let id: String = "benchPress"

    public init() {}

    public func makeMetricCalculator(configuration: RepCountingConfiguration) -> any MetricCalculator {
        BenchPressFlexion3DMetricCalculator(
            benchBottomElbowFlexionDegrees: configuration.bench.bottomElbowFlexionDegrees,
            benchBottomShoulderFlexionDegrees: configuration.bench.bottomShoulderFlexionDegrees,
            benchLockoutElbowFlexionDegrees: configuration.bench.lockoutElbowFlexionDegrees,
            benchLockoutShoulderFlexionDegrees: configuration.bench.lockoutShoulderFlexionDegrees
        )
    }

    public func makePeakDetector(configuration: RepCountingConfiguration) -> any PeakDetector {
        LocalExtremaPeakDetector(
            historyCapacity: configuration.peakDetection.historyCapacity,
            minPeakHeight: configuration.peakDetection.minPeakHeight,
            minValleyDepth: configuration.peakDetection.minValleyDepth,
            windowSize: configuration.peakDetection.windowSize
        )
    }

    public func makeRepCounter(configuration: RepCountingConfiguration) -> any RepCounter {
        BenchPressPhaseRepCounter(
            minTimeBetweenReps: configuration.gates.minTimeBetweenReps,
            minAmplitude: configuration.gates.minAmplitude,
            upThreshold: configuration.gates.upThreshold,
            downThreshold: configuration.gates.downThreshold,
            inactivityResetSeconds: configuration.common.inactivityResetSeconds,
            activityDeltaThreshold: configuration.common.activityDeltaThreshold
        )
    }

    public func makeMetricFilters(configuration: RepCountingConfiguration) -> [any MetricFilter] {
        [
            SpikeRejectionFilter(maxDelta: configuration.filters.spikeMaxDelta),
            EMAMetricFilter(alpha: configuration.filters.emaAlpha),
        ]
    }
}
