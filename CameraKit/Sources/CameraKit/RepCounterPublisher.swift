import Foundation
import Combine
import CoreMedia
import OSLog
import Vision

private let logger = Logger(subsystem: "CameraKit", category: "repCounting")

/// Quality of pose detection for rep counting
public enum DetectionQuality: Sendable {
    case good    // Most joints visible
    case partial // Some joints visible
    case poor    // Very few joints visible
}

public struct RepCountingConfiguration: Sendable {
    public struct Common: Sendable {
        public var armingThreshold: CGFloat
        public var inactivityResetSeconds: Double
        public var activityDeltaThreshold: CGFloat

        public init(
            armingThreshold: CGFloat = 0.5,
            inactivityResetSeconds: Double = 3.0,
            activityDeltaThreshold: CGFloat = 0.015
        ) {
            self.armingThreshold = armingThreshold
            self.inactivityResetSeconds = inactivityResetSeconds
            self.activityDeltaThreshold = activityDeltaThreshold
        }
    }

    public struct PeakDetection: Sendable {
        public var historyCapacity: Int
        public var minPeakHeight: CGFloat
        public var minValleyDepth: CGFloat
        public var windowSize: Int

        public init(
            historyCapacity: Int = 90,
            minPeakHeight: CGFloat = 0.08,
            minValleyDepth: CGFloat = 0.08,
            windowSize: Int = 5
        ) {
            self.historyCapacity = historyCapacity
            self.minPeakHeight = minPeakHeight
            self.minValleyDepth = minValleyDepth
            self.windowSize = windowSize
        }
    }

    public struct RepGates: Sendable {
        public var minTimeBetweenReps: Double
        public var minAmplitude: CGFloat
        public var upThreshold: CGFloat
        public var downThreshold: CGFloat

        public init(
            minTimeBetweenReps: Double = 0.6,
            minAmplitude: CGFloat = 0.18,
            upThreshold: CGFloat = 0.20,
            downThreshold: CGFloat = 0.92
        ) {
            self.minTimeBetweenReps = minTimeBetweenReps
            self.minAmplitude = minAmplitude
            self.upThreshold = upThreshold
            self.downThreshold = downThreshold
        }
    }

    public struct FilterTuning: Sendable {
        public var spikeMaxDelta: CGFloat
        public var emaAlpha: CGFloat

        public init(spikeMaxDelta: CGFloat = 0.25, emaAlpha: CGFloat = 0.3) {
            self.spikeMaxDelta = spikeMaxDelta
            self.emaAlpha = emaAlpha
        }
    }

    public struct SquatTuning: Sendable {
        public var descendEntryThreshold: CGFloat
        public var standLockoutThreshold: CGFloat
        public var kneeBottomFlexionDegrees: CGFloat
        public var hipBottomFlexionDegrees: CGFloat
        public var kneeLockoutFlexionDegrees: CGFloat
        public var hipLockoutFlexionDegrees: CGFloat
        public var maxSideAsymmetryDegrees: CGFloat

        public init(
            descendEntryThreshold: CGFloat = 0.18,
            standLockoutThreshold: CGFloat = 0.10,
            kneeBottomFlexionDegrees: CGFloat = 80,
            hipBottomFlexionDegrees: CGFloat = 60,
            kneeLockoutFlexionDegrees: CGFloat = 18,
            hipLockoutFlexionDegrees: CGFloat = 20,
            maxSideAsymmetryDegrees: CGFloat = 25
        ) {
            self.descendEntryThreshold = descendEntryThreshold
            self.standLockoutThreshold = standLockoutThreshold
            self.kneeBottomFlexionDegrees = kneeBottomFlexionDegrees
            self.hipBottomFlexionDegrees = hipBottomFlexionDegrees
            self.kneeLockoutFlexionDegrees = kneeLockoutFlexionDegrees
            self.hipLockoutFlexionDegrees = hipLockoutFlexionDegrees
            self.maxSideAsymmetryDegrees = maxSideAsymmetryDegrees
        }
    }

    public struct CurlTuning: Sendable {
        public var topFlexionDegrees: CGFloat
        public var lockoutFlexionDegrees: CGFloat

        public init(topFlexionDegrees: CGFloat = 95, lockoutFlexionDegrees: CGFloat = 18) {
            self.topFlexionDegrees = topFlexionDegrees
            self.lockoutFlexionDegrees = lockoutFlexionDegrees
        }
    }

    public struct BenchTuning: Sendable {
        public var bottomElbowFlexionDegrees: CGFloat
        public var bottomShoulderFlexionDegrees: CGFloat
        public var lockoutElbowFlexionDegrees: CGFloat
        public var lockoutShoulderFlexionDegrees: CGFloat

        public init(
            bottomElbowFlexionDegrees: CGFloat = 45,
            bottomShoulderFlexionDegrees: CGFloat = 45,
            lockoutElbowFlexionDegrees: CGFloat = 12,
            lockoutShoulderFlexionDegrees: CGFloat = 12
        ) {
            self.bottomElbowFlexionDegrees = bottomElbowFlexionDegrees
            self.bottomShoulderFlexionDegrees = bottomShoulderFlexionDegrees
            self.lockoutElbowFlexionDegrees = lockoutElbowFlexionDegrees
            self.lockoutShoulderFlexionDegrees = lockoutShoulderFlexionDegrees
        }
    }

    public var common: Common
    public var peakDetection: PeakDetection
    public var gates: RepGates
    public var filters: FilterTuning
    public var squat: SquatTuning
    public var curl: CurlTuning
    public var bench: BenchTuning

    public init(
        common: Common = .init(),
        peakDetection: PeakDetection = .init(),
        gates: RepGates = .init(),
        filters: FilterTuning = .init(),
        squat: SquatTuning = .init(),
        curl: CurlTuning = .init(),
        bench: BenchTuning = .init()
    ) {
        self.common = common
        self.peakDetection = peakDetection
        self.gates = gates
        self.filters = filters
        self.squat = squat
        self.curl = curl
        self.bench = bench
    }

    public static let squatDefault = RepCountingConfiguration(
        gates: .init(minTimeBetweenReps: 0.6, minAmplitude: 0.55, upThreshold: 0.20, downThreshold: 0.82),
        squat: .init(
            descendEntryThreshold: 0.18,
            standLockoutThreshold: 0.10,
            kneeBottomFlexionDegrees: 72,
            hipBottomFlexionDegrees: 52,
            kneeLockoutFlexionDegrees: 18,
            hipLockoutFlexionDegrees: 20,
            maxSideAsymmetryDegrees: 25
        )
    )

    public static let bicepCurlDefault = RepCountingConfiguration(
        gates: .init(minTimeBetweenReps: 0.5, minAmplitude: 0.25, upThreshold: 0.60, downThreshold: 0.35),
        curl: .init(topFlexionDegrees: 128, lockoutFlexionDegrees: 34)
    )

    public static let benchPressDefault = RepCountingConfiguration(
        gates: .init(minTimeBetweenReps: 0.5, minAmplitude: 0.20, upThreshold: 0.60, downThreshold: 0.30),
        bench: .init(
            bottomElbowFlexionDegrees: 45,
            bottomShoulderFlexionDegrees: 45,
            lockoutElbowFlexionDegrees: 12,
            lockoutShoulderFlexionDegrees: 12
        )
    )

    var repCounterTuning: RepCounterTuning {
        RepCounterTuning(
            minTimeBetweenReps: gates.minTimeBetweenReps,
            minAmplitude: gates.minAmplitude,
            upThreshold: gates.upThreshold,
            downThreshold: gates.downThreshold,
            inactivityResetSeconds: common.inactivityResetSeconds,
            activityDeltaThreshold: common.activityDeltaThreshold,
            squatDescendEntryThreshold: squat.descendEntryThreshold,
            squatStandLockoutThreshold: squat.standLockoutThreshold
        )
    }
}

/// Output from rep counter including pose and rep count
public struct RepCounterOutput: Sendable {
    public let exerciseProfileID: String
    public let poseFrame: PoseFrame
    public let repCount: Int
    public let currentMetric: CGFloat?
    public let state: RepCounterState
    public let detectionQuality: DetectionQuality
    public let runningMax: CGFloat
    public let trackedJoints: [VNHumanBodyPose3DObservation.JointName]
    public let exerciseDiagnostics: ExerciseDiagnostics?

    public init(
        exerciseProfileID: String,
        poseFrame: PoseFrame,
        repCount: Int,
        currentMetric: CGFloat?,
        state: RepCounterState,
        detectionQuality: DetectionQuality,
        runningMax: CGFloat = 0,
        trackedJoints: [VNHumanBodyPose3DObservation.JointName] = [],
        exerciseDiagnostics: ExerciseDiagnostics? = nil
    ) {
        self.exerciseProfileID = exerciseProfileID
        self.poseFrame = poseFrame
        self.repCount = repCount
        self.currentMetric = currentMetric
        self.state = state
        self.detectionQuality = detectionQuality
        self.runningMax = runningMax
        self.trackedJoints = trackedJoints
        self.exerciseDiagnostics = exerciseDiagnostics
    }
}

/// Orchestrates metric calculation, peak detection, and rep counting
public final class RepCounterPublisher: @unchecked Sendable {
    private let subject = PassthroughSubject<RepCounterOutput, Never>()
    private let processingQueue = DispatchQueue(label: "camerakit.repcount.processing")
    public private(set) var exerciseProfileID: String

    private var metricCalculatorFactory: (RepCountingConfiguration) -> any MetricCalculator
    private var peakDetectorFactory: (RepCountingConfiguration) -> any PeakDetector
    private var repCounterFactory: (RepCountingConfiguration) -> any RepCounter
    private var metricFilterFactory: (RepCountingConfiguration) -> [any MetricFilter]

    private var metricCalculator: any MetricCalculator
    private var peakDetector: any PeakDetector
    private var repCounter: any RepCounter
    private var metricFilters: [any MetricFilter]
    private var armingThreshold: CGFloat
    private var metricWindow: [CGFloat] = []
    private let metricWindowCapacity = 60
    private var runningMax: CGFloat { metricWindow.max() ?? 0 }

    @inline(__always)
    private func assertOnProcessingQueue() {
        dispatchPrecondition(condition: .onQueue(processingQueue))
    }

    public var repCounts: AnyPublisher<RepCounterOutput, Never> {
        subject.eraseToAnyPublisher()
    }

    public init(
        metricCalculator: any MetricCalculator = SquatJointFlexion3DMetricCalculator(),
        peakDetector: any PeakDetector = LocalExtremaPeakDetector(),
        repCounter: any RepCounter = SquatPhaseRepCounter(),
        metricFilters: [any MetricFilter] = [SpikeRejectionFilter(), EMAMetricFilter()],
        armingThreshold: CGFloat = 0.5,
        exerciseProfileID: String = "custom",
        metricCalculatorFactory: ((RepCountingConfiguration) -> any MetricCalculator)? = nil,
        peakDetectorFactory: ((RepCountingConfiguration) -> any PeakDetector)? = nil,
        repCounterFactory: ((RepCountingConfiguration) -> any RepCounter)? = nil,
        metricFilterFactory: ((RepCountingConfiguration) -> [any MetricFilter])? = nil
    ) {
        self.exerciseProfileID = exerciseProfileID
        self.metricCalculatorFactory = metricCalculatorFactory ?? { _ in metricCalculator }
        self.peakDetectorFactory = peakDetectorFactory ?? { Self.makePeakDetector($0) }
        self.repCounterFactory = repCounterFactory ?? { _ in repCounter }
        self.metricFilterFactory = metricFilterFactory ?? { Self.makeMetricFilters($0) }
        self.metricCalculator = metricCalculator
        self.peakDetector = peakDetector
        self.repCounter = repCounter
        self.metricFilters = metricFilters
        self.armingThreshold = armingThreshold
    }

    public convenience init(
        configuration: RepCountingConfiguration,
        exerciseProfile: any ExerciseProfile = SquatExerciseProfile()
    ) {
        self.init(
            metricCalculator: exerciseProfile.makeMetricCalculator(configuration: configuration),
            peakDetector: exerciseProfile.makePeakDetector(configuration: configuration),
            repCounter: exerciseProfile.makeRepCounter(configuration: configuration),
            metricFilters: exerciseProfile.makeMetricFilters(configuration: configuration),
            armingThreshold: configuration.common.armingThreshold,
            exerciseProfileID: exerciseProfile.id,
            metricCalculatorFactory: { exerciseProfile.makeMetricCalculator(configuration: $0) },
            peakDetectorFactory: { exerciseProfile.makePeakDetector(configuration: $0) },
            repCounterFactory: { exerciseProfile.makeRepCounter(configuration: $0) },
            metricFilterFactory: { exerciseProfile.makeMetricFilters(configuration: $0) }
        )
    }

    public func updateConfiguration(_ configuration: RepCountingConfiguration) {
        processingQueue.async { [weak self] in
            guard let self else { return }
            self.assertOnProcessingQueue()

            self.metricCalculator = self.metricCalculatorFactory(configuration)
            self.peakDetector = self.peakDetectorFactory(configuration)
            self.metricFilters = self.metricFilterFactory(configuration)
            self.armingThreshold = configuration.common.armingThreshold
            self.repCounter.updateTuning(configuration.repCounterTuning)
            self.metricWindow.removeAll()
        }
    }

    public func setExerciseProfile(
        _ exerciseProfile: any ExerciseProfile,
        configuration: RepCountingConfiguration
    ) {
        processingQueue.async { [weak self] in
            guard let self else { return }
            self.assertOnProcessingQueue()

            self.exerciseProfileID = exerciseProfile.id
            self.metricCalculatorFactory = { exerciseProfile.makeMetricCalculator(configuration: $0) }
            self.peakDetectorFactory = { exerciseProfile.makePeakDetector(configuration: $0) }
            self.repCounterFactory = { exerciseProfile.makeRepCounter(configuration: $0) }
            self.metricFilterFactory = { exerciseProfile.makeMetricFilters(configuration: $0) }

            self.metricCalculator = self.metricCalculatorFactory(configuration)
            self.peakDetector = self.peakDetectorFactory(configuration)
            self.repCounter = self.repCounterFactory(configuration)
            self.metricFilters = self.metricFilterFactory(configuration)
            self.armingThreshold = configuration.common.armingThreshold
            self.metricWindow.removeAll()
        }
    }

    public func ingest(_ poseFrame: PoseFrame) {
        processingQueue.async { [weak self] in
            self?.process(poseFrame)
        }
    }

    private func process(_ poseFrame: PoseFrame) {
        assertOnProcessingQueue()

        let exerciseDiagnostics = currentExerciseDiagnostics(from: poseFrame)

        guard let metric = metricCalculator.calculate(from: poseFrame) else {
            sendOutput(
                poseFrame: poseFrame,
                metric: nil,
                quality: .poor,
                trackedJoints: metricCalculator.trackedJoints(from: poseFrame),
                exerciseDiagnostics: exerciseDiagnostics
            )
            return
        }

        let trackedJoints = metricCalculator.trackedJoints(from: poseFrame)

        // Explicit write-back guards against Swift existential mutation edge cases
        var filteredMetric = metric
        for i in metricFilters.indices {
            var f = metricFilters[i]
            filteredMetric = f.filter(filteredMetric)
            metricFilters[i] = f
        }
        logger.debug("metric=\(filteredMetric, format: .fixed(precision: 3))")

        repCounter.ingestSample(timestamp: poseFrame.timestamp, metricValue: filteredMetric)

        metricWindow.append(filteredMetric)
        if metricWindow.count > metricWindowCapacity { metricWindow.removeFirst() }

        let previousCount = repCounter.count

        if repCounter.consumesPeakEvents {
            // Threshold-based arming keeps the peak-driven counter armed whenever
            // we are clearly above the standing position.
            if filteredMetric > armingThreshold {
                repCounter.processPeak(.maximum, timestamp: poseFrame.timestamp, metricValue: runningMax)
            }

            let sample = MetricSample(timestamp: poseFrame.timestamp, value: filteredMetric)

            if let peak = peakDetector.ingest(sample) {
                switch peak {
                case .minimum:
                    repCounter.processPeak(.minimum, timestamp: poseFrame.timestamp, metricValue: filteredMetric)
                case .maximum:
                    repCounter.processPeak(.maximum, timestamp: poseFrame.timestamp, metricValue: runningMax)
                }
            }
        }

        if repCounter.count != previousCount {
            logger.info("Rep counted — total=\(self.repCounter.count) state=\(self.repCounter.state.rawValue)")
        }

        let quality: DetectionQuality = poseFrame.joints.count >= 10 ? .good :
                                        poseFrame.joints.count >= 5 ? .partial : .poor

        sendOutput(
            poseFrame: poseFrame,
            metric: filteredMetric,
            quality: quality,
            trackedJoints: trackedJoints,
            exerciseDiagnostics: exerciseDiagnostics
        )
    }

    private func sendOutput(
        poseFrame: PoseFrame,
        metric: CGFloat?,
        quality: DetectionQuality,
        trackedJoints: [VNHumanBodyPose3DObservation.JointName],
        exerciseDiagnostics: ExerciseDiagnostics?
    ) {
        assertOnProcessingQueue()

        let output = RepCounterOutput(
            exerciseProfileID: exerciseProfileID,
            poseFrame: poseFrame,
            repCount: repCounter.count,
            currentMetric: metric,
            state: repCounter.state,
            detectionQuality: quality,
            runningMax: runningMax,
            trackedJoints: trackedJoints,
            exerciseDiagnostics: exerciseDiagnostics
        )
        subject.send(output)
    }

    private func currentExerciseDiagnostics(from poseFrame: PoseFrame) -> ExerciseDiagnostics? {
        (metricCalculator as? any ExerciseDiagnosticsProvider)?.diagnostics(from: poseFrame)
    }

    public func reset() {
        processingQueue.async { [weak self] in
            guard let self else { return }
            self.assertOnProcessingQueue()
            self.repCounter.reset()
            self.metricWindow.removeAll()
        }
    }

    private static func makePeakDetector(_ configuration: RepCountingConfiguration) -> LocalExtremaPeakDetector {
        LocalExtremaPeakDetector(
            historyCapacity: configuration.peakDetection.historyCapacity,
            minPeakHeight: configuration.peakDetection.minPeakHeight,
            minValleyDepth: configuration.peakDetection.minValleyDepth,
            windowSize: configuration.peakDetection.windowSize
        )
    }

    private static func makeRepCounter(_ configuration: RepCountingConfiguration) -> SquatPhaseRepCounter {
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

    private static func makeMetricFilters(_ configuration: RepCountingConfiguration) -> [any MetricFilter] {
        [
            SpikeRejectionFilter(maxDelta: configuration.filters.spikeMaxDelta),
            EMAMetricFilter(alpha: configuration.filters.emaAlpha),
        ]
    }
}
