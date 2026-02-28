import Foundation
import CoreMedia

/// State of the rep counter
public enum RepCounterState: String, Sendable {
    case up
    case down
    case transition
}

/// Protocol for counting reps based on peak patterns
public protocol RepCounter {
    var count: Int { get }
    var state: RepCounterState { get }
    mutating func processPeak(_ peak: PeakType, timestamp: CMTime, metricValue: CGFloat)
    mutating func reset()
}

/// Counts reps based on peak/valley cycles
public struct CycleBasedRepCounter: RepCounter {
    public private(set) var count: Int = 0
    public private(set) var state: RepCounterState = .transition

    private var lastPeakTime: CMTime = .zero
    private let minTimeBetweenReps: Double
    private let upThreshold: CGFloat
    private let downThreshold: CGFloat

    public init(minTimeBetweenReps: Double = 0.5, upThreshold: CGFloat = 0.6, downThreshold: CGFloat = 0.3) {
        self.minTimeBetweenReps = minTimeBetweenReps
        self.upThreshold = upThreshold
        self.downThreshold = downThreshold
    }

    public mutating func processPeak(_ peak: PeakType, timestamp: CMTime, metricValue: CGFloat) {
        let timeSinceLastPeak = CMTimeGetSeconds(timestamp - lastPeakTime)

        // Only count if enough time has passed since last peak (prevents double-counting)
        if timeSinceLastPeak > minTimeBetweenReps {
            count += 1
            lastPeakTime = timestamp
        }

        updateState(metricValue: metricValue)
    }

    private mutating func updateState(metricValue: CGFloat) {
        if metricValue > upThreshold {
            state = .up
        } else if metricValue < downThreshold {
            state = .down
        } else {
            state = .transition
        }
    }

    public mutating func reset() {
        count = 0
        state = .transition
        lastPeakTime = .zero
    }
}
