import Foundation

public struct SquatExerciseProfile: ExerciseProfile {
    public let id: String = "squat"

    public init() {}

    public func makeMetricCalculator(configuration: RepCountingConfiguration) -> any MetricCalculator {
        SquatJointFlexion3DMetricCalculator(
            kneeBottomFlexionDegrees: configuration.squat.kneeBottomFlexionDegrees,
            hipBottomFlexionDegrees: configuration.squat.hipBottomFlexionDegrees,
            kneeLockoutFlexionDegrees: configuration.squat.kneeLockoutFlexionDegrees,
            hipLockoutFlexionDegrees: configuration.squat.hipLockoutFlexionDegrees,
            maxSideAsymmetryDegrees: configuration.squat.maxSideAsymmetryDegrees
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
        SquatPhaseRepCounter(
            minTimeBetweenReps: configuration.gates.minTimeBetweenReps,
            minAmplitude: configuration.gates.minAmplitude,
            upThreshold: configuration.gates.upThreshold,
            downThreshold: configuration.gates.downThreshold,
            inactivityResetSeconds: configuration.common.inactivityResetSeconds,
            activityDeltaThreshold: configuration.common.activityDeltaThreshold,
            descendEntryThreshold: configuration.squat.descendEntryThreshold,
            standLockoutThreshold: configuration.squat.standLockoutThreshold
        )
    }

    public func makeMetricFilters(configuration: RepCountingConfiguration) -> [any MetricFilter] {
        [
            SpikeRejectionFilter(maxDelta: configuration.filters.spikeMaxDelta),
        ]
    }
}
