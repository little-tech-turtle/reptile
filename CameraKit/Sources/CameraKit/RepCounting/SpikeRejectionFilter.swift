import Foundation

/// Rejects metric values that jump more than `maxDelta` from the last accepted
/// value. Apply before EMAMetricFilter to prevent bad joint readings from
/// corrupting the smoothed signal and runningMax.
public struct SpikeRejectionFilter: MetricFilter {
    private let maxDelta: CGFloat
    private var lastAccepted: CGFloat?

    public init(maxDelta: CGFloat = 0.25) {
        self.maxDelta = maxDelta
    }

    public mutating func filter(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return lastAccepted ?? 0 }

        guard let last = lastAccepted else {
            lastAccepted = value
            return value
        }

        if abs(value - last) > maxDelta {
            return last  // spike — hold previous value, don't update lastAccepted
        }

        lastAccepted = value
        return value
    }
}
