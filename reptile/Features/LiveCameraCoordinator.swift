import AVFoundation
import CameraKit
import Combine
import Foundation
import UIKit
import Vision

@MainActor
final class LiveCameraCoordinator {
    private let pipeline: LivePipeline
    private let projector: ScreenSpaceProjector

    private var cancellables = Set<AnyCancellable>()
    private weak var previewView: CameraPreviewView?
    private var renderHandler: ((LiveCameraRenderModel) -> Void)?

    private var latestState: LivePipelineState = .idle
    private var latestOutput: RepCounterOutput?

    init(
        pipeline: LivePipeline = LivePipeline(),
        projector: ScreenSpaceProjector = ScreenSpaceProjector()
    ) {
        self.pipeline = pipeline
        self.projector = projector
        bindPipeline()
    }

    func bind(
        previewView: CameraPreviewView,
        render: @escaping (LiveCameraRenderModel) -> Void
    ) {
        self.previewView = previewView
        previewView.setSession(pipeline.captureSession)
        self.renderHandler = render
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
    }

    func updateInterfaceOrientation(_ orientation: UIInterfaceOrientation) {
        pipeline.setInterfaceOrientation(orientation)
        updatePreviewOrientation(orientation)
    }

    private func bindPipeline() {
        pipeline.outputs
            .receive(on: RunLoop.main)
            .sink { [weak self] output in
                guard let self else { return }
                self.latestOutput = output
                self.publishRenderModel()
            }
            .store(in: &cancellables)

        pipeline.states
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self else { return }
                self.latestState = state
                self.publishRenderModel()
            }
            .store(in: &cancellables)
    }

    private func updatePreviewOrientation(_ orientation: UIInterfaceOrientation) {
        guard let connection = previewView?.videoPreviewLayer.connection else { return }

        let angle = FrameTransformPolicy.previewRotationAngle(for: orientation)
        if connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
    }

    private func publishRenderModel() {
        guard let renderHandler else { return }

        let joints = projectedJoints(from: latestOutput)
        let status = statusText(state: latestState, output: latestOutput)

        renderHandler(
            LiveCameraRenderModel(
                statusText: status,
                joints: joints,
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
            guard let output else { return "" }
            return "Reps: \(output.repCount) • State: \(output.state.rawValue) • \(qualityIndicator(for: output.detectionQuality))"
        case .stopping:
            return "Stopping camera…"
        case .failed(let error):
            return "Camera error: \(errorMessage(for: error))"
        }
    }

    private func qualityIndicator(for quality: DetectionQuality) -> String {
        switch quality {
        case .good:
            return "●"
        case .partial:
            return "◐"
        case .poor:
            return "○"
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
