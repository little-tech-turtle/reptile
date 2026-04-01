import AVFoundation
import CameraKit
import Combine
import Foundation
import UIKit
import Vision

enum ExerciseMode: String, CaseIterable {
    case squat
    case bicepCurl

    var title: String {
        switch self {
        case .squat:
            return "Squat"
        case .bicepCurl:
            return "Curl"
        }
    }

    var profile: any ExerciseProfile {
        switch self {
        case .squat:
            return SquatExerciseProfile()
        case .bicepCurl:
            return BicepCurlExerciseProfile()
        }
    }
}

@MainActor
final class LiveCameraCoordinator {
    nonisolated static let defaultSquatRepTuning = RepCountingConfiguration(
        armingThreshold: 0.5,
        minPeakHeight: 0.08,
        minValleyDepth: 0.08,
        peakWindowSize: 5,
        minTimeBetweenReps: 0.6,
        minAmplitude: 0.55,
        upThreshold: 0.20,
        downThreshold: 0.92,
        squatDescendEntryThreshold: 0.18,
        squatStandLockoutThreshold: 0.10,
        squatKneeBottomFlexionDegrees: 80,
        squatHipBottomFlexionDegrees: 60,
        squatKneeLockoutFlexionDegrees: 18,
        squatHipLockoutFlexionDegrees: 20,
        squatMaxSideAsymmetryDegrees: 25,
        inactivityResetSeconds: 3.0,
        activityDeltaThreshold: 0.015,
        spikeMaxDelta: 0.25,
        emaAlpha: 0.3
    )

    nonisolated static let defaultBicepCurlRepTuning = RepCountingConfiguration(
        armingThreshold: 0.5,
        minPeakHeight: 0.08,
        minValleyDepth: 0.08,
        peakWindowSize: 5,
        minTimeBetweenReps: 0.5,
        minAmplitude: 0.25,
        upThreshold: 0.65,
        downThreshold: 0.25,
        squatDescendEntryThreshold: 0.18,
        squatStandLockoutThreshold: 0.10,
        squatKneeBottomFlexionDegrees: 80,
        squatHipBottomFlexionDegrees: 60,
        squatKneeLockoutFlexionDegrees: 18,
        squatHipLockoutFlexionDegrees: 20,
        squatMaxSideAsymmetryDegrees: 25,
        curlTopFlexionDegrees: 95,
        curlLockoutFlexionDegrees: 18,
        inactivityResetSeconds: 3.0,
        activityDeltaThreshold: 0.015,
        spikeMaxDelta: 0.25,
        emaAlpha: 0.3
    )

    nonisolated static let defaultRepTuning = defaultSquatRepTuning

    nonisolated static func defaultRepTuning(for exercise: ExerciseMode) -> RepCountingConfiguration {
        switch exercise {
        case .squat:
            return defaultSquatRepTuning
        case .bicepCurl:
            return defaultBicepCurlRepTuning
        }
    }

    private let pipeline: LivePipeline
    private let projector: ScreenSpaceProjector
    private var repTuning: RepCountingConfiguration
    private var selectedExercise: ExerciseMode
    private var cameraPosition: AVCaptureDevice.Position = .front
    private var latestInterfaceOrientation: UIInterfaceOrientation = .portrait

    private var cancellables = Set<AnyCancellable>()
    private weak var previewView: CameraPreviewView?
    private var renderHandler: ((LiveCameraRenderModel) -> Void)?

    private var latestState: LivePipelineState = .idle
    private var latestOutput: RepCounterOutput?

    init(
        pipeline: LivePipeline? = nil,
        exerciseMode: ExerciseMode = .squat,
        repTuning: RepCountingConfiguration? = nil,
        projector: ScreenSpaceProjector = ScreenSpaceProjector()
    ) {
        self.selectedExercise = exerciseMode
        self.repTuning = repTuning ?? LiveCameraCoordinator.defaultRepTuning(for: exerciseMode)
        self.pipeline = pipeline ?? LivePipeline(
            repCounter: RepCounterPublisher(configuration: self.repTuning, exerciseProfile: exerciseMode.profile)
        )
        self.projector = projector
        applyCameraPolicy(for: cameraPosition)
        bindPipeline()
    }

    func bind(
        previewView: CameraPreviewView,
        render: @escaping (LiveCameraRenderModel) -> Void
    ) {
        self.previewView = previewView
        previewView.setSession(pipeline.captureSession)
        self.renderHandler = render
        applyPreviewConnectionState()
        publishRenderModel()
    }

    func start() {
        pipeline.start()
    }

    func stop() {
        pipeline.stop()
    }

    func setMirrorInput(_ isMirrored: Bool) {
        pipeline.setMirrorInput(isMirrored)
        applyPreviewConnectionState()
    }

    func currentCameraPosition() -> AVCaptureDevice.Position {
        cameraPosition
    }

    @discardableResult
    func toggleCameraPosition() -> AVCaptureDevice.Position {
        let next: AVCaptureDevice.Position = cameraPosition == .front ? .back : .front
        setCameraPosition(next)
        return cameraPosition
    }

    func setCameraPosition(_ position: AVCaptureDevice.Position) {
        guard position == .front || position == .back else { return }
        guard position != cameraPosition else { return }

        cameraPosition = position
        applyCameraPolicy(for: position)
        applyPreviewConnectionState()
    }

    func updateInterfaceOrientation(_ orientation: UIInterfaceOrientation) {
        latestInterfaceOrientation = orientation
        pipeline.setInterfaceOrientation(orientation)
        applyPreviewConnectionState()
    }

    func currentRepCountingConfiguration() -> RepCountingConfiguration {
        repTuning
    }

    func currentExercise() -> ExerciseMode {
        selectedExercise
    }

    func setExercise(_ exercise: ExerciseMode, configuration: RepCountingConfiguration) {
        selectedExercise = exercise
        repTuning = configuration
        pipeline.setExerciseProfile(exercise.profile, configuration: configuration)
    }

    func updateRepCountingConfiguration(_ configuration: RepCountingConfiguration) {
        repTuning = configuration
        pipeline.updateRepCountingConfiguration(configuration)
    }

    private func bindPipeline() {
        pipeline.outputs
            .receive(on: RunLoop.main)
            .sink { [weak self] output in
                guard let self else { return }
                self.latestOutput = output
                self.applyPreviewConnectionState()
                self.publishRenderModel()
            }
            .store(in: &cancellables)

        pipeline.states
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self else { return }
                self.latestState = state
                self.applyPreviewConnectionState()
                self.publishRenderModel()
            }
            .store(in: &cancellables)
    }

    private func applyPreviewConnectionState() {
        guard let connection = previewView?.videoPreviewLayer.connection else { return }

        let angle = FrameTransformPolicy.previewRotationAngle(for: latestInterfaceOrientation)
        if connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }

        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = FrameTransformPolicy.previewMirrored(for: cameraPosition)
        }
    }

    private func applyCameraPolicy(for position: AVCaptureDevice.Position) {
        pipeline.setCameraPosition(position)
        pipeline.setMirrorInput(FrameTransformPolicy.visionMirroredInput(for: position))
    }

    private func publishRenderModel() {
        guard let renderHandler else { return }

        let joints = projectedJoints(from: latestOutput)
        let status = statusText(state: latestState, output: latestOutput)
        let trackedJoints = Set(latestOutput?.trackedJoints ?? [])

        renderHandler(
            LiveCameraRenderModel(
                statusText: status,
                joints: joints,
                trackedJoints: trackedJoints,
                exerciseMode: selectedExercise,
                output: latestOutput
            )
        )
    }

    private func projectedJoints(
        from output: RepCounterOutput?
    ) -> [VNHumanBodyPose3DObservation.JointName: CGPoint] {
        guard
            let output,
            let previewLayer = previewView?.videoPreviewLayer
        else {
            return [:]
        }

        return projector.project(
            normalized: output.poseFrame.joints,
            in: previewLayer
        )
    }

    private func statusText(
        state: LivePipelineState,
        output: RepCounterOutput?
    ) -> String {
        switch state {
        case .idle:
            return ""
        case .starting:
            return "Starting camera…"
        case .running:
            return ""
        case .stopping:
            return "Stopping camera…"
        case .failed(let error):
            return "Camera error: \(errorMessage(for: error))"
        }
    }

    private func errorMessage(for error: CameraSessionError) -> String {
        switch error {
        case .permissionDenied:
            return "Permission denied. Enable camera in Settings."
        case .restricted:
            return "Camera restricted on this device."
        case .noCameraAvailable:
            return "No camera available."
        case .configurationFailed:
            return "Could not configure camera."
        }
    }
}
