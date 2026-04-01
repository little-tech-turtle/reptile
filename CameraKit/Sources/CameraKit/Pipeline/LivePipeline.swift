import AVFoundation
import Combine
import Foundation
import UIKit

public enum LivePipelineState: Sendable {
    case idle
    case starting
    case running
    case stopping
    case failed(CameraSessionError)
}

public final class LivePipeline {
    private let cameraSession: CameraSession
    private let poseDetector: PoseDetectorPublisher
    private let repCounter: RepCounterPublisher

    private let outputSubject = PassthroughSubject<RepCounterOutput, Never>()
    private let stateSubject = CurrentValueSubject<LivePipelineState, Never>(.idle)
    private var cancellables = Set<AnyCancellable>()

    public var outputs: AnyPublisher<RepCounterOutput, Never> {
        outputSubject.eraseToAnyPublisher()
    }

    public var captureSession: AVCaptureSession {
        cameraSession.session
    }

    public var states: AnyPublisher<LivePipelineState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    public init(
        cameraSession: CameraSession = CameraSession(),
        poseDetector: PoseDetectorPublisher = PoseDetectorPublisher(),
        repCounter: RepCounterPublisher = RepCounterPublisher()
    ) {
        self.cameraSession = cameraSession
        self.poseDetector = poseDetector
        self.repCounter = repCounter

        wirePipeline()
        wireSessionState()
    }

    deinit {
        poseDetector.finish()
        cameraSession.stopRunning()
    }

    public func start() {
        cameraSession.startRunning()
    }

    public func stop() {
        stateSubject.send(.stopping)
        cameraSession.stopRunning()
        repCounter.reset()
    }

    public func setInterfaceOrientation(_ orientation: UIInterfaceOrientation) {
        cameraSession.setInterfaceOrientation(orientation)
    }

    public func setMirrorInput(_ isMirrored: Bool) {
        cameraSession.setMirrorInput(isMirrored)
    }

    public func setCameraPosition(_ position: AVCaptureDevice.Position) {
        cameraSession.setCameraPosition(position)
    }

    public func updateRepCountingConfiguration(_ configuration: RepCountingConfiguration) {
        repCounter.updateConfiguration(configuration)
    }

    public func setExerciseProfile(
        _ exerciseProfile: any ExerciseProfile,
        configuration: RepCountingConfiguration
    ) {
        repCounter.setExerciseProfile(exerciseProfile, configuration: configuration)
    }

    private func wirePipeline() {
        cameraSession.frames
            .sink { [weak self] frame in
                self?.poseDetector.ingest(frame)
            }
            .store(in: &cancellables)

        poseDetector.poses
            .sink { [weak self] poseFrame in
                self?.repCounter.ingest(poseFrame)
            }
            .store(in: &cancellables)

        repCounter.repCounts
            .sink { [weak self] output in
                self?.outputSubject.send(output)
            }
            .store(in: &cancellables)
    }

    private func wireSessionState() {
        cameraSession.states
            .sink { [weak self] state in
                self?.stateSubject.send(Self.mapState(state))
            }
            .store(in: &cancellables)
    }

    private static func mapState(_ state: CameraSessionState) -> LivePipelineState {
        switch state {
        case .idle:
            return .idle
        case .starting:
            return .starting
        case .running:
            return .running
        case .stopping:
            return .stopping
        case .failed(let error):
            return .failed(error)
        }
    }
}
