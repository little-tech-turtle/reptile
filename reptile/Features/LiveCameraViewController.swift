//
//  LiveCameraViewController.swift
//  reptile
//
//  Created by TechTurtle on 04/01/2026.
//

import CameraKit
import UIKit

final class LiveCameraViewController: UIViewController {
    private let previewView = CameraPreviewView()
    private let statusLabel = UILabel()
    private let overlayView = SkeletonOverlayView()
    private let debugView = DebugOverlayView()

    private let coordinator = LiveCameraCoordinator()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        setupPreviewView()
        setupOverlayView()
        setupStatusLabel()
        setupDebugView()

        let tap = UITapGestureRecognizer(target: self, action: #selector(toggleDebug))
        view.addGestureRecognizer(tap)

        coordinator.bind(previewView: previewView) { [weak self] model in
            guard let self else { return }
            self.render(model)
        }
        coordinator.start()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        coordinator.updateInterfaceOrientation(currentInterfaceOrientation())
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
    }

    private func setupOverlayView() {
        overlayView.backgroundColor = .clear
        overlayView.isUserInteractionEnabled = false
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlayView)

        NSLayoutConstraint.activate([
            overlayView.topAnchor.constraint(equalTo: view.topAnchor),
            overlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            overlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        view.bringSubviewToFront(overlayView)
    }

    private func setupStatusLabel() {
        statusLabel.textColor = .white
        statusLabel.font = .systemFont(ofSize: 14, weight: .medium)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 2
        statusLabel.text = "Starting camera…"
        statusLabel.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        statusLabel.layer.cornerRadius = 10
        statusLabel.layer.masksToBounds = true

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor,
                constant: 8
            ),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            statusLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 36),
        ])

        view.bringSubviewToFront(statusLabel)
    }

    private func setupDebugView() {
        debugView.isHidden = true
        debugView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(debugView)

        NSLayoutConstraint.activate([
            debugView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            debugView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            debugView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            debugView.heightAnchor.constraint(equalToConstant: 200),
        ])

        view.bringSubviewToFront(debugView)
    }

    @objc private func toggleDebug() {
        debugView.isHidden.toggle()
    }

    private func currentInterfaceOrientation() -> UIInterfaceOrientation {
        if let io = view.window?.windowScene?.effectiveGeometry.interfaceOrientation {
            return io
        }
        return .portrait
    }

    private func render(_ model: LiveCameraRenderModel) {
        overlayView.joints = model.joints
        statusLabel.text = model.statusText

        if let output = model.output {
            debugView.update(output: output)
        }
    }
}
