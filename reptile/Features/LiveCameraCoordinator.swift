import AVFoundation
import CameraKit
import Combine
import Foundation
import UIKit
import Vision

@MainActor
final class LiveCameraCoordinator {
    static let availableExercises: [ExerciseDefinition] = ExerciseCatalog.all

    static var defaultExercise: ExerciseDefinition {
        ExerciseCatalog.defaultExercise
    }

    static func definition(for id: String) -> ExerciseDefinition? {
        ExerciseCatalog.definition(for: id)
    }

    static func defaultRepTuning(for exerciseID: String) -> RepCountingConfiguration {
        ExerciseCatalog.definition(for: exerciseID)?.defaultTuning ?? ExerciseCatalog.defaultExercise.defaultTuning
    }

    private let pipeline: LivePipeline
    private let projector: ScreenSpaceProjector
    private var repTuning: RepCountingConfiguration
    private var selectedExerciseID: String
    private var cameraPosition: AVCaptureDevice.Position = .front
    private var latestInterfaceOrientation: UIInterfaceOrientation = .portrait

    private var cancellables = Set<AnyCancellable>()
    private weak var previewView: CameraPreviewView?
    private var renderHandler: ((LiveCameraRenderModel) -> Void)?

    private var latestState: LivePipelineState = .idle
    private var latestOutput: RepCounterOutput?

    init(
        pipeline: LivePipeline? = nil,
        exerciseID: String? = nil,
        repTuning: RepCountingConfiguration? = nil,
        projector: ScreenSpaceProjector = ScreenSpaceProjector()
    ) {
        let requestedExerciseID = exerciseID ?? ExerciseCatalog.defaultExercise.id
        let selectedDefinition = ExerciseCatalog.definition(for: requestedExerciseID) ?? ExerciseCatalog.defaultExercise
        self.selectedExerciseID = selectedDefinition.id
        self.repTuning = repTuning ?? selectedDefinition.defaultTuning
        self.pipeline = pipeline ?? LivePipeline(
            repCounter: RepCounterPublisher(configuration: self.repTuning, exerciseProfile: selectedDefinition.makeProfile())
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

    func currentExerciseID() -> String {
        selectedExerciseID
    }

    func setExercise(id: String, configuration: RepCountingConfiguration) {
        guard let definition = ExerciseCatalog.definition(for: id) else { return }

        selectedExerciseID = definition.id
        repTuning = configuration
        pipeline.setExerciseProfile(definition.makeProfile(), configuration: configuration)
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
                exerciseID: selectedExerciseID,
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
