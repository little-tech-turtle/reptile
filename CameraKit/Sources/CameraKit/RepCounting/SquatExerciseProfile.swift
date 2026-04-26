import Foundation

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
        ]
    }
}
