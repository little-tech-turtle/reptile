import Foundation
import CoreMedia
import OSLog

private let logger = Logger(subsystem: "CameraKit", category: "repCounting")

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
    mutating func ingestSample(timestamp: CMTime, metricValue: CGFloat)
    mutating func processPeak(_ peak: PeakType, timestamp: CMTime, metricValue: CGFloat)
    mutating func reset()
}

public extension RepCounter {
    mutating func ingestSample(timestamp: CMTime, metricValue: CGFloat) {}
}

/// Counts reps using an alternating-peak state machine with an amplitude gate.
///
/// A rep is counted when a `.minimum` arrives **and**:
/// 1. A `.maximum` was seen before it (arms the counter), and
/// 2. The drop from the last maximum to this minimum is ≥ `minAmplitude`, and
/// 3. Enough time has elapsed since the last counted rep.
///
/// Consecutive minima without an intervening maximum count as one rep at most.
public struct CycleBasedRepCounter: RepCounter {
    public private(set) var count: Int = 0
    public private(set) var state: RepCounterState = .transition

    private var lastPeakTime: CMTime = .zero
    private var lastPeakType: PeakType? = nil
    private var lastPeakValue: CGFloat = 0

    private let minTimeBetweenReps: Double
    private let minAmplitude: CGFloat
    private let upThreshold: CGFloat
    private let downThreshold: CGFloat
    private let inactivityResetSeconds: Double
    private let activityDeltaThreshold: CGFloat

    private var lastObservedMetric: CGFloat?
    private var lastActivityTime: CMTime?
    private var idleResetArmed: Bool = true

    public init(
        minTimeBetweenReps: Double = 0.5,
        minAmplitude: CGFloat = 0.15,
        upThreshold: CGFloat = 0.6,
        downThreshold: CGFloat = 0.3,
        inactivityResetSeconds: Double = 3.0,
        activityDeltaThreshold: CGFloat = 0.015
    ) {
        self.minTimeBetweenReps = minTimeBetweenReps
        self.minAmplitude = minAmplitude
        self.upThreshold = upThreshold
        self.downThreshold = downThreshold
        self.inactivityResetSeconds = inactivityResetSeconds
        self.activityDeltaThreshold = activityDeltaThreshold
    }

    public mutating func ingestSample(timestamp: CMTime, metricValue: CGFloat) {
        let delta = abs(metricValue - (lastObservedMetric ?? metricValue))
        if lastObservedMetric == nil || delta >= activityDeltaThreshold {
            lastActivityTime = timestamp
            idleResetArmed = true
        }
        lastObservedMetric = metricValue

        guard let activityTime = lastActivityTime else { return }
        let idleSeconds = CMTimeGetSeconds(timestamp - activityTime)
        guard idleSeconds >= inactivityResetSeconds, idleResetArmed else { return }

        if count > 0 {
            logger.info("Rep counter reset after idle timeout (\(idleSeconds, format: .fixed(precision: 2))s)")
            reset()
        }
        idleResetArmed = false
    }

    public mutating func processPeak(_ peak: PeakType, timestamp: CMTime, metricValue: CGFloat) {
        switch peak {
        case .maximum:
            lastPeakType = .maximum
            lastPeakValue = metricValue

        case .minimum:
            let amplitude = lastPeakValue - metricValue
            let capturedPeakType = lastPeakType
            let capturedMinAmplitude = minAmplitude
            let capturedMinTime = minTimeBetweenReps
            logger.debug("min peak — lastPeakType=\(String(describing: capturedPeakType)) amplitude=\(amplitude, format: .fixed(precision: 3))")

            guard case .maximum = lastPeakType else {
                logger.debug("min rejected — no preceding maximum")
                updateState(metricValue: metricValue)
                return
            }
            guard amplitude >= minAmplitude else {
                logger.debug("min rejected — amplitude \(amplitude, format: .fixed(precision: 3)) < minAmplitude \(capturedMinAmplitude, format: .fixed(precision: 3))")
                updateState(metricValue: metricValue)
                return
            }
            let timeSinceLastRep = CMTimeGetSeconds(timestamp - lastPeakTime)
            guard timeSinceLastRep > minTimeBetweenReps else {
                logger.debug("min rejected — time gate (\(timeSinceLastRep, format: .fixed(precision: 2))s < \(capturedMinTime, format: .fixed(precision: 2))s)")
                updateState(metricValue: metricValue)
                return
            }

            count += 1
            lastPeakTime = timestamp
            lastPeakType = .minimum  // Prevents consecutive minima from re-counting
            let capturedCount = count
            let capturedStateRaw = state.rawValue
            logger.info("Rep counted — total=\(capturedCount) state=\(capturedStateRaw)")
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
        lastPeakType = nil
        lastPeakValue = 0
        lastObservedMetric = nil
        lastActivityTime = nil
        idleResetArmed = true
    }
}
