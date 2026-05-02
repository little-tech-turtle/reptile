import Foundation

/// Rejects metric values that jump more than `maxDelta` from the last accepted
/// value. Apply before EMAMetricFilter to prevent bad joint readings from
/// corrupting the smoothed signal and runningMax.
public struct SpikeRejectionFilter: MetricFilter {
    private let maxDelta: CGFloat
    private let consecutiveRejectsBeforeResync: Int
    private var lastAccepted: CGFloat?
    private var rejectStreak: Int = 0
    private var rejectDirection: Int = 0

    public init(maxDelta: CGFloat = 0.25, consecutiveRejectsBeforeResync: Int = 3) {
        self.maxDelta = maxDelta
        self.consecutiveRejectsBeforeResync = max(1, consecutiveRejectsBeforeResync)
    }

    public mutating func filter(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return lastAccepted ?? 0 }

        guard let last = lastAccepted else {
            lastAccepted = value
            rejectStreak = 0
            rejectDirection = 0
            return value
        }

        if abs(value - last) > maxDelta {
            let direction = value > last ? 1 : -1
            if direction == rejectDirection {
                rejectStreak += 1
            } else {
                rejectDirection = direction
                rejectStreak = 1
            }

            if rejectStreak >= consecutiveRejectsBeforeResync {
                lastAccepted = value
                rejectStreak = 0
                rejectDirection = 0
                return value
            }
            return last  // spike — hold previous value, don't update lastAccepted
        }

        lastAccepted = value
        rejectStreak = 0
        rejectDirection = 0
        return value
    }
}
