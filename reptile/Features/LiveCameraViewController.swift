//
//  LiveCameraViewController.swift
//  reptile
//
//  Created by TechTurtle on 04/01/2026.
//

import UIKit
import AVFoundation
import CameraKit

final class LiveCameraViewController: UIViewController {
    
    private let cameraSession = CameraSession()
    
    private let previewView = CameraPreviewView()
    
    private let statusLabel = UILabel()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupPreviewView()
        setupStatusLabel()
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
    }
    
    private func setupStatusLabel() {
        statusLabel.textColor = .white
        statusLabel.font = .systemFont(ofSize: 14, weight: .medium)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 2
        statusLabel.text = "Starting camera…"
        statusLabel.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)
        
        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }
    
    private func startCamera() {
        cameraSession.startRunning { [weak self] (result: Result<AVCaptureSession, CameraSessionError>) in
            guard let self else { return }

            switch result {
            case .success(let session):
                self.previewView.setSession(session)
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
