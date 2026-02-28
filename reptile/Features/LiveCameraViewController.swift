//
//  LiveCameraViewController.swift
//  reptile
//
//  Created by TechTurtle on 04/01/2026.
//

import AVFoundation
import CameraKit
import UIKit
import Combine
import Vision
final class LiveCameraViewController: UIViewController {

    private let cameraSession = CameraSession()

    private let previewView = CameraPreviewView()

    private let statusLabel = UILabel()

    private let overlayView = SkeletonOverlayView()
    
    private let poseDetector = PoseDetectorPublisher()
    private let projector = ScreenSpaceProjector()
    private let repCounter = RepCounterPublisher()
    private var cancellables = Set<AnyCancellable>()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupPreviewView()
        setupOverlayView()
        setupStatusLabel()
        cameraSession.frames
            .sink { [weak self] frame in
                self?.poseDetector.ingest(frame)
            }.store(in: &cancellables)

        poseDetector.poses
            .sink { [weak self] poseFrame in
                self?.repCounter.ingest(poseFrame)
            }.store(in: &cancellables)

        repCounter.repCounts
            .receive(on: RunLoop.main)
            .sink { [weak self] output in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let previewLayer = self.previewView.videoPreviewLayer
                    let screenJoints = self.projector.project(
                        normalized: output.poseFrame.joints,
                        in: previewLayer
                    )
                    self.overlayView.joints = screenJoints

                    // Update status label with rep count and state
                    let qualityIndicator: String
                    switch output.detectionQuality {
                    case .good: qualityIndicator = "●"
                    case .partial: qualityIndicator = "◐"
                    case .poor: qualityIndicator = "○"
                    }

                    self.statusLabel.text = "Reps: \(output.repCount) • State: \(output.state.rawValue) • \(qualityIndicator)"
                }
            }.store(in: &cancellables)
        startCamera()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.updatePreviewOrientation()
        
        if let io = view.window?.windowScene?.effectiveGeometry.interfaceOrientation {
            cameraSession.setInterfaceOrientation(io)
        }
        statusLabel.frame = CGRect(
            x: 16,
            y: view.safeAreaInsets.top + 16,
            width: view.bounds.width - 32,
            height: 40
        )
    }

    private func setupPreviewView() {
        previewView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(previewView)

        NSLayoutConstraint.activate([
            previewView.topAnchor.constraint(equalTo: view.topAnchor),
            previewView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        view.bringSubviewToFront(overlayView)
    }

    private func setupOverlayView() {
        //overlayView.backgroundColor = .clear
        overlayView.backgroundColor = UIColor.red.withAlphaComponent(0.2)
        overlayView.isUserInteractionEnabled = false
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlayView)

        NSLayoutConstraint.activate([
            overlayView.topAnchor.constraint(equalTo: view.topAnchor),
            overlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            overlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func currentInterfaceOrientation() -> UIInterfaceOrientation {
        view.window?.windowScene?.effectiveGeometry.interfaceOrientation ?? .portrait
    }
    
    
    
    private func visionOrientationString(_ o: CGImagePropertyOrientation) -> String {
        switch o {
        case .up: return "up"
        case .down: return "down"
        case .left: return "left"
        case .right: return "right"
        case .upMirrored: return "upMirrored"
        case .downMirrored: return "downMirrored"
        case .leftMirrored: return "leftMirrored"
        case .rightMirrored: return "rightMirrored"
        @unknown default: return "unknown"
        }
    }


    private func setupStatusLabel() {
        statusLabel.textColor = .white
        statusLabel.font = .systemFont(ofSize: 14, weight: .medium)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 1000
        statusLabel.text = "Starting camera…"
        statusLabel.backgroundColor = UIColor.black.withAlphaComponent(0.4)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor,
                constant: 8
            ),
            statusLabel.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -8
            ),
        ])
    }

    private func startCamera() {
        cameraSession.startRunning {
            [weak self] (result: Result<AVCaptureSession, CameraSessionError>)
            in
            guard let self else { return }

            switch result {
            case .success(let session):
                self.previewView.setSession(session)
                self.updatePreviewOrientation()
                self.statusLabel.text = ""
            case .failure(let error):
                self.statusLabel.text =
                    "Camera error: \(errorMessage(for: error))"
            }
        }
    }
    
    private func updatePreviewOrientation() {
        guard let connection = previewView.videoPreviewLayer.connection else { return }

        let io = view.window?.windowScene?.effectiveGeometry.interfaceOrientation ?? .portrait

        let angle: CGFloat
        switch io {
        case .portrait:            angle = 90
        case .portraitUpsideDown:  angle = 270
        case .landscapeLeft:       angle = 0
        case .landscapeRight:      angle = 180
        default:                   angle = 90
        }

        if connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
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

    deinit {
        poseDetector.finish()
        cameraSession.stopRunning()
    }
}
