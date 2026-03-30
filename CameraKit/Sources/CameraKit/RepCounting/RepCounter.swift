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

public struct RepCounterTuning: Sendable {
    public var minTimeBetweenReps: Double
    public var minAmplitude: CGFloat
    public var upThreshold: CGFloat
    public var downThreshold: CGFloat
    public var inactivityResetSeconds: Double
    public var activityDeltaThreshold: CGFloat
    public var squatDescendEntryThreshold: CGFloat
    public var squatStandLockoutThreshold: CGFloat

    public init(
        minTimeBetweenReps: Double,
        minAmplitude: CGFloat,
        upThreshold: CGFloat,
        downThreshold: CGFloat,
        inactivityResetSeconds: Double,
        activityDeltaThreshold: CGFloat,
        squatDescendEntryThreshold: CGFloat = 0.12,
        squatStandLockoutThreshold: CGFloat = 0.10
    ) {
        self.minTimeBetweenReps = minTimeBetweenReps
        self.minAmplitude = minAmplitude
        self.upThreshold = upThreshold
        self.downThreshold = downThreshold
        self.inactivityResetSeconds = inactivityResetSeconds
        self.activityDeltaThreshold = activityDeltaThreshold
        self.squatDescendEntryThreshold = squatDescendEntryThreshold
        self.squatStandLockoutThreshold = squatStandLockoutThreshold
    }
}

/// Protocol for counting reps based on peak patterns
public protocol RepCounter {
    var count: Int { get }
    var state: RepCounterState { get }
    var consumesPeakEvents: Bool { get }
    mutating func ingestSample(timestamp: CMTime, metricValue: CGFloat)
    mutating func updateTuning(_ tuning: RepCounterTuning)
    mutating func processPeak(_ peak: PeakType, timestamp: CMTime, metricValue: CGFloat)
    mutating func reset()
}

public extension RepCounter {
    var consumesPeakEvents: Bool { true }
    mutating func ingestSample(timestamp: CMTime, metricValue: CGFloat) {}
    mutating func updateTuning(_ tuning: RepCounterTuning) {}
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

    private var minTimeBetweenReps: Double
    private var minAmplitude: CGFloat
    private var upThreshold: CGFloat
    private var downThreshold: CGFloat
    private var inactivityResetSeconds: Double
    private var activityDeltaThreshold: CGFloat

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

    public mutating func updateTuning(_ tuning: RepCounterTuning) {
        minTimeBetweenReps = tuning.minTimeBetweenReps
        minAmplitude = tuning.minAmplitude
        upThreshold = tuning.upThreshold
        downThreshold = tuning.downThreshold
        inactivityResetSeconds = tuning.inactivityResetSeconds
        activityDeltaThreshold = tuning.activityDeltaThreshold
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

/// Counts full-depth squats with a phase-state machine.
///
/// Expected metric range is `0...1` where lower values are standing and higher
/// values are deeper squat positions.
public struct SquatPhaseRepCounter: RepCounter {
    private enum Phase {
        case standing
        case descending
        case bottom
        case ascending
    }

    public private(set) var count: Int = 0
    public private(set) var state: RepCounterState = .up
    public var consumesPeakEvents: Bool { false }

    private var minTimeBetweenReps: Double
    private var minAmplitude: CGFloat
    private var upThreshold: CGFloat
    private var downThreshold: CGFloat
    private var inactivityResetSeconds: Double
    private var activityDeltaThreshold: CGFloat

    private var descendEntryThreshold: CGFloat
    private var standLockoutThreshold: CGFloat
    private let bottomExitThreshold: CGFloat
    private let movementDeltaThreshold: CGFloat
    private let minCycleDuration: Double

    private var phase: Phase = .standing
    private var lastObservedMetric: CGFloat?
    private var lastActivityTime: CMTime?
    private var idleResetArmed: Bool = true

    private var cycleStartTime: CMTime?
    private var cycleStartDepth: CGFloat?
    private var cycleMaxDepth: CGFloat?
    private var lastRepTime: CMTime = .zero

    public init(
        minTimeBetweenReps: Double = 0.6,
        minAmplitude: CGFloat = 0.16,
        upThreshold: CGFloat = 0.20,
        downThreshold: CGFloat = 0.62,
        inactivityResetSeconds: Double = 3.0,
        activityDeltaThreshold: CGFloat = 0.015,
        descendEntryThreshold: CGFloat = 0.12,
        standLockoutThreshold: CGFloat = 0.10,
        bottomExitThreshold: CGFloat = 0.46,
        movementDeltaThreshold: CGFloat = 0.008,
        minCycleDuration: Double = 0.45
    ) {
        self.minTimeBetweenReps = minTimeBetweenReps
        self.minAmplitude = minAmplitude
        self.upThreshold = upThreshold
        self.downThreshold = downThreshold
        self.inactivityResetSeconds = inactivityResetSeconds
        self.activityDeltaThreshold = activityDeltaThreshold
        self.descendEntryThreshold = descendEntryThreshold
        self.standLockoutThreshold = standLockoutThreshold
        self.bottomExitThreshold = bottomExitThreshold
        self.movementDeltaThreshold = movementDeltaThreshold
        self.minCycleDuration = minCycleDuration
    }

    public mutating func updateTuning(_ tuning: RepCounterTuning) {
        minTimeBetweenReps = tuning.minTimeBetweenReps
        minAmplitude = tuning.minAmplitude
        upThreshold = tuning.upThreshold
        downThreshold = tuning.downThreshold
        inactivityResetSeconds = tuning.inactivityResetSeconds
        activityDeltaThreshold = tuning.activityDeltaThreshold
        descendEntryThreshold = tuning.squatDescendEntryThreshold
        standLockoutThreshold = tuning.squatStandLockoutThreshold
    }

    public mutating func ingestSample(timestamp: CMTime, metricValue: CGFloat) {
        let previousMetric = lastObservedMetric
        let delta = abs(metricValue - (previousMetric ?? metricValue))
        if previousMetric == nil || delta >= activityDeltaThreshold {
            lastActivityTime = timestamp
            idleResetArmed = true
        }
        lastObservedMetric = metricValue

        guard let activityTime = lastActivityTime else {
            updateState(metricValue: metricValue)
            return
        }

        let idleSeconds = CMTimeGetSeconds(timestamp - activityTime)
        if idleSeconds >= inactivityResetSeconds, idleResetArmed {
            if count > 0 {
                logger.info("Squat counter reset after idle timeout (\(idleSeconds, format: .fixed(precision: 2))s)")
            }
            reset()
            idleResetArmed = false
            return
        }

        let velocity = metricValue - (previousMetric ?? metricValue)
        processPhaseTransition(timestamp: timestamp, metricValue: metricValue, velocity: velocity)
        updateState(metricValue: metricValue)
    }

    public mutating func processPeak(_ peak: PeakType, timestamp: CMTime, metricValue: CGFloat) {
        // SquatPhaseRepCounter is sample-driven and ignores explicit peaks.
    }

    private mutating func processPhaseTransition(
        timestamp: CMTime,
        metricValue: CGFloat,
        velocity: CGFloat
    ) {
        switch phase {
        case .standing:
            guard metricValue >= descendEntryThreshold,
                  velocity > movementDeltaThreshold else {
                return
            }
            phase = .descending
            cycleStartTime = timestamp
            cycleStartDepth = metricValue
            cycleMaxDepth = metricValue

        case .descending:
            cycleMaxDepth = max(cycleMaxDepth ?? metricValue, metricValue)

            if metricValue >= downThreshold {
                phase = .bottom
                return
            }

            if metricValue <= standLockoutThreshold,
               velocity < -movementDeltaThreshold {
                clearCycleState()
                phase = .standing
            }

        case .bottom:
            cycleMaxDepth = max(cycleMaxDepth ?? metricValue, metricValue)
            if metricValue <= bottomExitThreshold,
               velocity < -movementDeltaThreshold {
                phase = .ascending
            }

        case .ascending:
            cycleMaxDepth = max(cycleMaxDepth ?? metricValue, metricValue)

            if metricValue >= downThreshold,
               velocity > movementDeltaThreshold {
                phase = .bottom
                return
            }

            guard metricValue <= standLockoutThreshold else {
                return
            }

            let timeSinceLastRep = CMTimeGetSeconds(timestamp - lastRepTime)
            let cycleDuration = CMTimeGetSeconds(timestamp - (cycleStartTime ?? timestamp))
            let depthRange = (cycleMaxDepth ?? metricValue) - (cycleStartDepth ?? metricValue)

            if depthRange >= minAmplitude,
               cycleDuration >= minCycleDuration,
               timeSinceLastRep >= minTimeBetweenReps {
                count += 1
                lastRepTime = timestamp
                let capturedCount = count
                logger.info("Squat counted - total=\(capturedCount)")
            }

            clearCycleState()
            phase = .standing
        }
    }

    private mutating func updateState(metricValue: CGFloat) {
        if metricValue <= upThreshold {
            state = .up
        } else if metricValue >= downThreshold {
            state = .down
        } else {
            state = .transition
        }
    }

    private mutating func clearCycleState() {
        cycleStartTime = nil
        cycleStartDepth = nil
        cycleMaxDepth = nil
    }

    public mutating func reset() {
        count = 0
        state = .up
        phase = .standing
        lastObservedMetric = nil
        lastActivityTime = nil
        idleResetArmed = true
        clearCycleState()
        lastRepTime = .zero
    }
}
