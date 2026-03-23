//
//  LiveCameraViewController.swift
//  reptile
//
//  Created by TechTurtle on 04/01/2026.
//

import CameraKit
import UIKit

final class LiveCameraViewController: UIViewController {
    private static let tuningStorageKey = "repTuning.v1"

    private let previewView = CameraPreviewView()
    private let repCountLabel = UILabel()
    private let statusLabel = UILabel()
    private let overlayView = SkeletonOverlayView()
    private let debugView = DebugOverlayView()
    private let tuningPanel = RepTuningPanelView()

    private let coordinator = LiveCameraCoordinator()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        setupPreviewView()
        setupOverlayView()
        setupRepCountLabel()
        setupStatusLabel()
        setupDebugView()
        setupTuningPanel()

        let tap = UITapGestureRecognizer(target: self, action: #selector(toggleDebug))
        view.addGestureRecognizer(tap)

        let initialTuning = loadSavedRepTuning()
        coordinator.updateRepCountingConfiguration(initialTuning)
        debugView.updateConfiguration(initialTuning)
        tuningPanel.apply(configuration: initialTuning)
        tuningPanel.onConfigurationChanged = { [weak self] config in
            guard let self else { return }
            self.coordinator.updateRepCountingConfiguration(config)
            self.debugView.updateConfiguration(config)
            self.saveRepTuning(config)
        }

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

    private func setupRepCountLabel() {
        repCountLabel.textColor = .white
        repCountLabel.font = .monospacedDigitSystemFont(ofSize: 88, weight: .bold)
        repCountLabel.textAlignment = .center
        repCountLabel.text = "0"
        repCountLabel.adjustsFontSizeToFitWidth = true
        repCountLabel.minimumScaleFactor = 0.6
        repCountLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(repCountLabel)

        NSLayoutConstraint.activate([
            repCountLabel.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor,
                constant: 8
            ),
            repCountLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            repCountLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            repCountLabel.heightAnchor.constraint(equalToConstant: 100),
        ])

        view.bringSubviewToFront(repCountLabel)
    }

    private func setupStatusLabel() {
        statusLabel.textColor = .white
        statusLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 1
        statusLabel.text = "Starting camera…"
        statusLabel.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        statusLabel.layer.cornerRadius = 10
        statusLabel.layer.masksToBounds = true

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(
                equalTo: repCountLabel.bottomAnchor,
                constant: 4
            ),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 28),
            statusLabel.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.8),
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

    private func setupTuningPanel() {
        tuningPanel.isHidden = true
        tuningPanel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tuningPanel)

        NSLayoutConstraint.activate([
            tuningPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            tuningPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            tuningPanel.bottomAnchor.constraint(equalTo: debugView.topAnchor, constant: -10),
            tuningPanel.heightAnchor.constraint(equalToConstant: 244),
        ])

        view.bringSubviewToFront(tuningPanel)
    }

    @objc private func toggleDebug() {
        debugView.isHidden.toggle()
        tuningPanel.isHidden.toggle()
    }

    private func currentInterfaceOrientation() -> UIInterfaceOrientation {
        if let io = view.window?.windowScene?.effectiveGeometry.interfaceOrientation {
            return io
        }
        return .portrait
    }

    private func render(_ model: LiveCameraRenderModel) {
        overlayView.joints = model.joints
        overlayView.highlightedJoints = model.trackedJoints

        if let output = model.output {
            repCountLabel.text = "\(output.repCount)"
        } else {
            repCountLabel.text = "0"
        }

        statusLabel.text = model.statusText
        statusLabel.isHidden = model.statusText.isEmpty

        if let output = model.output {
            debugView.update(output: output)
        }
    }

    private func saveRepTuning(_ configuration: RepCountingConfiguration) {
        let values: [String: Double] = [
            "armingThreshold": Double(configuration.armingThreshold),
            "minPeakHeight": Double(configuration.minPeakHeight),
            "minValleyDepth": Double(configuration.minValleyDepth),
            "peakWindowSize": Double(configuration.peakWindowSize),
            "minTimeBetweenReps": configuration.minTimeBetweenReps,
            "minAmplitude": Double(configuration.minAmplitude),
            "upThreshold": Double(configuration.upThreshold),
            "downThreshold": Double(configuration.downThreshold),
            "inactivityResetSeconds": configuration.inactivityResetSeconds,
            "activityDeltaThreshold": Double(configuration.activityDeltaThreshold),
            "spikeMaxDelta": Double(configuration.spikeMaxDelta),
            "emaAlpha": Double(configuration.emaAlpha),
        ]
        UserDefaults.standard.set(values, forKey: Self.tuningStorageKey)
    }

    private func loadSavedRepTuning() -> RepCountingConfiguration {
        guard
            let values = UserDefaults.standard.dictionary(forKey: Self.tuningStorageKey),
            let armingThreshold = values["armingThreshold"] as? Double,
            let minPeakHeight = values["minPeakHeight"] as? Double,
            let minValleyDepth = values["minValleyDepth"] as? Double,
            let peakWindowSize = values["peakWindowSize"] as? Double,
            let minTimeBetweenReps = values["minTimeBetweenReps"] as? Double,
            let minAmplitude = values["minAmplitude"] as? Double,
            let upThreshold = values["upThreshold"] as? Double,
            let downThreshold = values["downThreshold"] as? Double,
            let inactivityResetSeconds = values["inactivityResetSeconds"] as? Double,
            let activityDeltaThreshold = values["activityDeltaThreshold"] as? Double,
            let spikeMaxDelta = values["spikeMaxDelta"] as? Double,
            let emaAlpha = values["emaAlpha"] as? Double
        else {
            return LiveCameraCoordinator.defaultRepTuning
        }

        return RepCountingConfiguration(
            armingThreshold: CGFloat(armingThreshold),
            peakHistoryCapacity: LiveCameraCoordinator.defaultRepTuning.peakHistoryCapacity,
            minPeakHeight: CGFloat(minPeakHeight),
            minValleyDepth: CGFloat(minValleyDepth),
            peakWindowSize: Int(peakWindowSize),
            minTimeBetweenReps: minTimeBetweenReps,
            minAmplitude: CGFloat(minAmplitude),
            upThreshold: CGFloat(upThreshold),
            downThreshold: CGFloat(downThreshold),
            inactivityResetSeconds: inactivityResetSeconds,
            activityDeltaThreshold: CGFloat(activityDeltaThreshold),
            spikeMaxDelta: CGFloat(spikeMaxDelta),
            emaAlpha: CGFloat(emaAlpha)
        )
    }
}
