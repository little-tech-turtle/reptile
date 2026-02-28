import Foundation
import CoreMedia
import OSLog

private let logger = Logger(subsystem: "CameraKit", category: "peakDetection")

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

/// Detects local extrema (maxima and minima) using a full sliding window.
///
/// The candidate peak sits at `history[n - halfW - 1]`. Detection fires `halfW`
/// frames after the physical extremum — an acceptable lag for rep counting.
public struct LocalExtremaPeakDetector: PeakDetector {
    private var history: [MetricSample] = []
    private let historyCapacity: Int
    private let minPeakHeight: CGFloat
    private let minValleyDepth: CGFloat
    private let windowSize: Int

    /// - Parameters:
    ///   - historyCapacity: Maximum number of samples to retain.
    ///   - minPeakHeight: Minimum value a candidate maximum must exceed.
    ///   - minValleyDepth: Maximum value a candidate minimum must be below
    ///     (expressed as `1 - minValleyDepth`).
    ///   - windowSize: Full window width; must be odd and ≥ 3. `halfW = windowSize / 2`
    ///     samples on each side of the centre must all confirm the shape.
    public init(
        historyCapacity: Int = 90,
        minPeakHeight: CGFloat = 0.08,
        minValleyDepth: CGFloat = 0.08,
        windowSize: Int = 5
    ) {
        self.historyCapacity = historyCapacity
        self.minPeakHeight = minPeakHeight
        self.minValleyDepth = minValleyDepth
        self.windowSize = max(windowSize, 3)
    }

    public mutating func ingest(_ sample: MetricSample) -> PeakType? {
        history.append(sample)
        if history.count > historyCapacity {
            history.removeFirst()
        }

        let n = history.count
        // Need at least windowSize + 1 samples so the centre index is valid
        guard n >= windowSize + 1 else { return nil }

        let halfW = windowSize / 2
        let centerIdx = n - halfW - 1
        let centerValue = history[centerIdx].value

        // Check all halfW samples before and after the centre
        let before = (centerIdx - halfW ..< centerIdx).map { history[$0].value }
        let after = (centerIdx + 1 ... centerIdx + halfW).map { history[$0].value }

        // Detect local maximum
        if centerValue > minPeakHeight,
           before.allSatisfy({ $0 < centerValue }),
           after.allSatisfy({ $0 < centerValue }) {
            logger.debug("maximum detected at centerIdx=\(centerIdx) value=\(centerValue, format: .fixed(precision: 3))")
            return .maximum
        }

        // Detect local minimum
        let valleyThreshold = 1.0 - minValleyDepth
        if centerValue < valleyThreshold,
           before.allSatisfy({ $0 > centerValue }),
           after.allSatisfy({ $0 > centerValue }) {
            logger.debug("minimum detected at centerIdx=\(centerIdx) value=\(centerValue, format: .fixed(precision: 3))")
            return .minimum
        }

        return nil
    }
}
