import Foundation
import CoreMedia

/// Type of peak detected in metric time series
public enum PeakType {
    case maximum
    case minimum
}

/// A single timestamped metric value
public struct MetricSample {
    public let timestamp: CMTime
    public let value: CGFloat

    public init(timestamp: CMTime, value: CGFloat) {
        self.timestamp = timestamp
        self.value = value
    }
}

/// Protocol for detecting peaks in metric time series
public protocol PeakDetector {
    mutating func ingest(_ sample: MetricSample) -> PeakType?
}

/// Detects local extrema (maxima and minima) in time series
public struct LocalExtremaPeakDetector: PeakDetector {
    private var history: [MetricSample] = []
    private let historyCapacity: Int
    private let minPeakHeight: CGFloat
    private let windowSize: Int

    public init(historyCapacity: Int = 90, minPeakHeight: CGFloat = 0.08, windowSize: Int = 5) {
        self.historyCapacity = historyCapacity
        self.minPeakHeight = minPeakHeight
        self.windowSize = windowSize
    }

    public mutating func ingest(_ sample: MetricSample) -> PeakType? {
        history.append(sample)
        if history.count > historyCapacity {
            history.removeFirst()
        }

        guard history.count >= windowSize else { return nil }

        let n = history.count
        let current = history[n-1].value
        let prev1 = history[n-2].value
        let prev2 = history[n-3].value

        // Detect local maximum (peak)
        if prev2 < prev1 && prev1 > current && prev1 > minPeakHeight {
            return .maximum
        }

        // Detect local minimum (valley)
        if prev2 > prev1 && prev1 < current {
            return .minimum
        }

        return nil
    }
}
