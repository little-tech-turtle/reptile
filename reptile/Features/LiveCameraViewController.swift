//
//  LiveCameraViewController.swift
//  reptile
//
//  Created by TechTurtle on 04/01/2026.
//

import UIKit
import AVFoundation
import CameraKit
import Vision

final class LiveCameraViewController: UIViewController {
    
    private let cameraSession = CameraSession()
    
    private let previewView = CameraPreviewView()
    
    private let statusLabel = UILabel()
    
    private let overlayView = SkeletonOverlayView()
    private let bodyPose3DRequest = VNDetectHumanBodyPose3DRequest()
    private let sequenceHandler = VNSequenceRequestHandler()
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupPreviewView()
        setupOverlayView()
        setupStatusLabel()
        
        cameraSession.setFrameHandler { [weak self] pixelBuffer in
            self?.handleFrame(pixelBuffer)
        }
        startCamera()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewView.frame = view.bounds
        statusLabel.frame = CGRect(x:16, y: view.safeAreaInsets.top + 16, width: view.bounds.width - 32, height: 40)
    }
    
    private func setupPreviewView(){
        previewView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(previewView)
        
        NSLayoutConstraint.activate([
            previewView.topAnchor.constraint(equalTo: view.topAnchor),
                previewView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
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
    
    private func handleFrame(_ pixelBuffer: CVPixelBuffer){
        print("frame handler called")
        let orientation: CGImagePropertyOrientation = .up
        do {
            try sequenceHandler.perform([bodyPose3DRequest],on:pixelBuffer, orientation: orientation)
            guard let observation = bodyPose3DRequest.results?.first else {return}
            
            
            DispatchQueue.main.async {[weak self] in
                guard let self else {return}
                let joints = self.projectJointsToView(observation)
                print("joints found: \(joints.count)")
                self.overlayView.joints = joints
                
                let previewConnection = self.previewView.videoPreviewLayer.connection!
                let outputConnection = self.cameraSession.session.outputs.compactMap{ ($0 as? AVCaptureVideoDataOutput)?.connection(with: .video)}.first!
                let uiOrientation = UIApplication.shared.connectedScenes.compactMap{($0 as? UIWindowScene)?.effectiveGeometry}.first
                
                print( """
    UI orientation: \(uiOrientation.debugDescription)
    Vision orientation: \(self.visionOrientationString(orientation))

    Preview:
      mirrored: \(previewConnection.isVideoMirrored ?? false)
      autoMirror: \(previewConnection.automaticallyAdjustsVideoMirroring ?? false)

    Output:
      mirrored: \(outputConnection.isVideoMirrored ?? false)
      autoMirror: \(outputConnection.automaticallyAdjustsVideoMirroring ?? false)
    """)
                
            }
            
        }catch {
            print("Vision Error: \(error)")
        }
        
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

    
    private func projectJointsToView(_ observation: VNHumanBodyPose3DObservation) -> [VNHumanBodyPose3DObservation.JointName: CGPoint] {
        var result: [VNHumanBodyPose3DObservation.JointName: CGPoint] = [:]
        
        assert(Thread.isMainThread)
        
        let previewLayer = previewView.videoPreviewLayer
        
        for jointName in observation.availableJointNames{
            guard let point2D = try? observation.pointInImage(jointName) else {continue}
            
            let normalized = CGPoint(x: point2D.x, y: 1.0 - point2D.y)
            let rect = CGRect(x: normalized.x, y:normalized.y, width: 0.001, height: 0.001)
            let layerRect = previewLayer.layerRectConverted(fromMetadataOutputRect: rect)
            //let captureDevicePoint = CGPoint(x: point2D.x, y: point2D.y)
            //let layerPoint = previewLayer.layerPointConverted(fromCaptureDevicePoint: captureDevicePoint)
            let layerPoint = CGPoint(x: layerRect.midX, y: layerRect.midY)
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
            statusLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            statusLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8)
        ])
    }
    
    private func startCamera() {
        cameraSession.startRunning { [weak self] (result: Result<AVCaptureSession, CameraSessionError>) in
            guard let self else { return }

            switch result {
            case .success(let session):
                self.previewView.setSession(session)
                if let connection = self.previewView.videoPreviewLayer.connection, connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
                self.statusLabel.text = "" // Hide text once running
            case .failure(let error):
                self.statusLabel.text = "Camera error: \(errorMessage(for: error))"
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
