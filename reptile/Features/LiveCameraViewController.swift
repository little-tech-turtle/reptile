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
        self.updatePreviewOrientation()
        
        if let io = view.window?.windowScene?.effectiveGeometry.interfaceOrientation {
            cameraSession.interfaceOrientation = io
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

    private func handleFrame(_ sampleBuffer: CMSampleBuffer, connection: AVCaptureConnection) {
        if isProcessing { return }
        isProcessing = true

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            isProcessing = false
            return
        }
        
        
        let orientation = cameraSession.visionOrientation()

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
    
    

    private func projectJointsToView(
        _ observation: VNHumanBodyPose3DObservation
    ) -> [VNHumanBodyPose3DObservation.JointName: CGPoint] {
        var result: [VNHumanBodyPose3DObservation.JointName: CGPoint] = [:]

        assert(Thread.isMainThread)

        let previewLayer = previewView.videoPreviewLayer
        
        let v = cameraSession.visionOrientation()
        
        print("UI:", 
              "previewAngle:", previewView.videoPreviewLayer.connection?.videoRotationAngle ?? -1,
              "visionOrientation:", visionOrientationString(v),
        )

        for jointName in observation.availableJointNames {
            guard let point2D = try? observation.pointInImage(jointName) else {
                continue
            }

            //var captureDevicePoint = CGPoint(x:point2D.x , y: 1 - point2D.y)
            // This is what we're trying to achieve with this transformation: CGPoint(x: 1 - point2D.y , y: point2D.x)
            let captureDevicePoint = CGPoint(x: 1 - point2D.y , y: 1 - point2D.x)
            //let captureDevicePoint = CGPoint(x: -transformedCaptureDevicePoint.x, y:transformedCaptureDevicePoint.y)
            //let transformation = CGAffineTransform( a:0, b:1, c:-1, d:0, tx:1, ty:0)
            //let transformation = CGAffineTransform.identity.rotated(by: .pi)
            //captureDevicePoint = captureDevicePoint.applying(transformation)
            //TODO: Then we want to mirror this over the y axis or maybe we want to turn mirrored on? investigate tomorrow
            
            //let flipY = CGAffineTransform(scaleX: 1, y: -1)
            //captureDevicePoint = captureDevicePoint.applying(flipY)
           
            print("captureDevicePoint: \(captureDevicePoint.x) , \(captureDevicePoint.y)")
            let layerPoint = previewLayer.layerPointConverted(fromCaptureDevicePoint: captureDevicePoint)
            print("layer point ",layerPoint.debugDescription)
           
            result[jointName] = layerPoint
        }
        return result
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
                guard
                    let connection = self.previewView.videoPreviewLayer
                        .connection
                else { return }
                self.updatePreviewOrientation()
            

                self.statusLabel.text = ""  // Hide text once running
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
        cameraSession.stopRunning()
    }
}
