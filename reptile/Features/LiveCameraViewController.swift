//
//  LiveCameraViewController.swift
//  reptile
//
//  Created by TechTurtle on 04/01/2026.
//

import AVFoundation
import CameraKit
import UIKit
import Vision

final class LiveCameraViewController: UIViewController {

    private let cameraSession = CameraSession()

    private let previewView = CameraPreviewView()

    private let statusLabel = UILabel()

    private let overlayView = SkeletonOverlayView()
    private let bodyPose3DRequest = VNDetectHumanBodyPose3DRequest()
    private let sequenceHandler = VNSequenceRequestHandler()

    private let visionQueue = DispatchQueue(label: "vision.queue")

    private var isProcessing = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupPreviewView()
        setupOverlayView()
        setupStatusLabel()

        cameraSession.setFrameHandler { [weak self] sampleBuffer, connection in
            self?.handleFrame(sampleBuffer, connection:connection)
        }
        startCamera()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewView.frame = view.bounds
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

    private func handleFrame(_ sampleBuffer: CMSampleBuffer, connection: AVCaptureConnection) {
        if isProcessing { return }
        isProcessing = true

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            isProcessing = false
            return
        }
        
        let orientation = visionOrientation(from: connection)

        visionQueue.async { [weak self] in
            defer { self?.isProcessing = false }
            guard let self else { return }

            autoreleasepool {
                do {
                    let req3D = VNDetectHumanBodyPose3DRequest()
                    let handler = VNImageRequestHandler(
                        cvPixelBuffer: pixelBuffer,
                        orientation: orientation,
                        options: [:]
                    )
                    try handler.perform([req3D])

                    guard let obs = req3D.results?.first else { return }

                    DispatchQueue.main.async {
                        self.overlayView.joints = self.projectJointsToView(obs)
                    }
                } catch {
                    let ns = error as NSError
                    print("Vision:", ns.domain, ns.code, ns.userInfo)
                }
            }
        }
    }
    private func currentInterfaceOrientation() -> UIInterfaceOrientation {
        view.window?.windowScene?.effectiveGeometry.interfaceOrientation ?? .portrait
    }
    
    private func visionOrientation(from connection: AVCaptureConnection) -> CGImagePropertyOrientation {
    
        switch currentInterfaceOrientation() {
        case .portrait:            return .right
        case .portraitUpsideDown:  return .left
        case .landscapeLeft:       return .up       // home indicator on the right
        case .landscapeRight:      return .down     // home indicator on the left
        default:                   return .right
        }
    }
    

    private func projectJointsToView(
        _ observation: VNHumanBodyPose3DObservation
    ) -> [VNHumanBodyPose3DObservation.JointName: CGPoint] {
        var result: [VNHumanBodyPose3DObservation.JointName: CGPoint] = [:]

        assert(Thread.isMainThread)

        let previewLayer = previewView.videoPreviewLayer

        for jointName in observation.availableJointNames {
            guard let point2D = try? observation.pointInImage(jointName) else {
                continue
            }

            let captureDevicePoint = CGPoint(x: point2D.x, y: 1.0 - point2D.y)
            //let captureDevicePoint = CGPoint(x: point2D.x, y: point2D.y)
            let layerPoint = previewLayer.layerPointConverted(fromCaptureDevicePoint: captureDevicePoint)
           
            result[jointName] = layerPoint
        }
        return result
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
                guard
                    let connection = self.previewView.videoPreviewLayer
                        .connection
                else { return }
                if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = true
                }

                self.statusLabel.text = ""  // Hide text once running
            case .failure(let error):
                self.statusLabel.text =
                    "Camera error: \(errorMessage(for: error))"
            }
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
        cameraSession.stopRunning()
    }
}
