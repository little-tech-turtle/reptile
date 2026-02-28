import Foundation

/// Protocol for smoothing a metric time series before peak detection
public protocol MetricFilter {
    mutating func filter(_ value: CGFloat) -> CGFloat
}

/// Exponential moving average filter — lower alpha = more smoothing, more lag
public struct EMAMetricFilter: MetricFilter {
    private let alpha: CGFloat
    private var previous: CGFloat?

    public init(alpha: CGFloat = 0.3) {
        self.alpha = alpha
    }

    public mutating func filter(_ value: CGFloat) -> CGFloat {
        let smoothed = previous.map { alpha * value + (1 - alpha) * $0 } ?? value
        previous = smoothed
        return smoothed
    }
}
