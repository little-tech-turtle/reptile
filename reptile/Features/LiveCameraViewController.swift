//
//  LiveCameraViewController.swift
//  reptile
//
//  Created by TechTurtle on 04/01/2026.
//

import CameraKit
import AVFoundation
import UIKit
import QuartzCore

final class LiveCameraViewController: UIViewController {
    private static let tuningStoragePrefix = "repTuning.v5"
    private static let cameraPositionStorageKey = "cameraPosition.v1"
    private static let exerciseModeStorageKey = "exerciseMode.v1"

    private let previewView = CameraPreviewView()
    private let repCountLabel = UILabel()
    private let statusLabel = UILabel()
    private let exerciseSelector = UISegmentedControl(items: ExerciseMode.allCases.map(\.title))
    private let cameraToggleButton = UIButton(type: .system)
    private let overlayView = SkeletonOverlayView()
    private let debugView = DebugOverlayView()
    private let tuningPanel = RepTuningPanelView()

    private let coordinator = LiveCameraCoordinator()
    private var selectedExercise: ExerciseMode = .squat

    private var pendingConfigurationUpdate: DispatchWorkItem?
    private let configurationDebounceInterval: TimeInterval = 0.12
    private let debugUpdateInterval: CFTimeInterval = 1.0 / 12.0
    private var lastDebugUpdateTime: CFTimeInterval = 0
    private var isAdjustingTuningControls = false
    private lazy var debugToggleGesture: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(toggleDebug))
        gesture.numberOfTapsRequired = 2
        gesture.cancelsTouchesInView = false
        gesture.delegate = self
        return gesture
    }()

    deinit {
        pendingConfigurationUpdate?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        setupPreviewView()
        setupOverlayView()
        setupRepCountLabel()
        setupStatusLabel()
        setupExerciseSelector()
        setupCameraToggleButton()
        setupDebugView()
        setupTuningPanel()
        view.addGestureRecognizer(debugToggleGesture)

        let initialExercise = loadSavedExerciseMode()
        selectedExercise = initialExercise
        let initialTuning = loadSavedRepTuning(for: initialExercise)
        let initialCameraPosition = loadSavedCameraPosition()

        coordinator.setExercise(initialExercise, configuration: initialTuning)
        coordinator.setCameraPosition(initialCameraPosition)
        debugView.updateConfiguration(initialTuning, exerciseMode: initialExercise)
        tuningPanel.apply(configuration: initialTuning, exerciseMode: initialExercise)
        updateCameraToggleButton(for: initialCameraPosition)
        updateExerciseSelector(for: initialExercise)
        tuningPanel.onConfigurationChanged = { [weak self] config in
            guard let self else { return }
            self.scheduleConfigurationUpdate(config, for: self.selectedExercise)
        }
        tuningPanel.onInteractionChanged = { [weak self] isInteracting in
            self?.setTuningInteractionState(isInteracting)
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

    private func setupExerciseSelector() {
        exerciseSelector.selectedSegmentTintColor = UIColor.white.withAlphaComponent(0.92)
        exerciseSelector.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        exerciseSelector.setTitleTextAttributes([.foregroundColor: UIColor.black], for: .selected)
        exerciseSelector.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)
        exerciseSelector.translatesAutoresizingMaskIntoConstraints = false
        exerciseSelector.addTarget(self, action: #selector(exerciseSelectionChanged), for: .valueChanged)

        view.addSubview(exerciseSelector)
        NSLayoutConstraint.activate([
            exerciseSelector.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            exerciseSelector.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            exerciseSelector.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.66),
        ])

        view.bringSubviewToFront(exerciseSelector)
    }

    private func setupCameraToggleButton() {
        var config = UIButton.Configuration.filled()
        config.title = "Front"
        config.image = UIImage(systemName: "camera.rotate")
        config.imagePadding = 6
        config.cornerStyle = .capsule
        config.baseBackgroundColor = UIColor.black.withAlphaComponent(0.55)
        config.baseForegroundColor = .white
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        cameraToggleButton.configuration = config
        cameraToggleButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        cameraToggleButton.translatesAutoresizingMaskIntoConstraints = false
        cameraToggleButton.addTarget(self, action: #selector(toggleCamera), for: .touchUpInside)

        view.addSubview(cameraToggleButton)
        NSLayoutConstraint.activate([
            cameraToggleButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            cameraToggleButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
        ])

        view.bringSubviewToFront(cameraToggleButton)
    }

    private func setupDebugView() {
        debugView.isHidden = true
        debugView.isUserInteractionEnabled = false
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

        let preferredHeight = tuningPanel.heightAnchor.constraint(equalToConstant: 320)
        preferredHeight.priority = .defaultHigh

        NSLayoutConstraint.activate([
            tuningPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            tuningPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            tuningPanel.bottomAnchor.constraint(equalTo: debugView.topAnchor, constant: -10),
            tuningPanel.topAnchor.constraint(greaterThanOrEqualTo: exerciseSelector.bottomAnchor, constant: 8),
            tuningPanel.heightAnchor.constraint(greaterThanOrEqualToConstant: 240),
            preferredHeight,
        ])

        view.bringSubviewToFront(tuningPanel)
    }

    @objc private func toggleDebug() {
        debugView.isHidden.toggle()
        tuningPanel.isHidden.toggle()
        lastDebugUpdateTime = 0
    }

    @objc private func toggleCamera() {
        let position = coordinator.toggleCameraPosition()
        updateCameraToggleButton(for: position)
        saveCameraPosition(position)
    }

    @objc private func exerciseSelectionChanged() {
        let index = exerciseSelector.selectedSegmentIndex
        guard ExerciseMode.allCases.indices.contains(index) else { return }
        applyExerciseSelection(ExerciseMode.allCases[index], persistSelection: true)
    }

    private func applyExerciseSelection(_ exerciseMode: ExerciseMode, persistSelection: Bool) {
        selectedExercise = exerciseMode
        let tuning = loadSavedRepTuning(for: exerciseMode)
        coordinator.setExercise(exerciseMode, configuration: tuning)
        repCountLabel.text = "0"
        debugView.updateConfiguration(tuning, exerciseMode: exerciseMode)
        tuningPanel.apply(configuration: tuning, exerciseMode: exerciseMode)
        updateExerciseSelector(for: exerciseMode)
        lastDebugUpdateTime = 0
        if persistSelection {
            saveExerciseMode(exerciseMode)
        }
    }

    private func updateExerciseSelector(for exerciseMode: ExerciseMode) {
        if let index = ExerciseMode.allCases.firstIndex(of: exerciseMode) {
            exerciseSelector.selectedSegmentIndex = index
        }
    }

    private func updateCameraToggleButton(for position: AVCaptureDevice.Position) {
        var config = cameraToggleButton.configuration ?? UIButton.Configuration.filled()
        config.title = position == .front ? "Front" : "Back"
        cameraToggleButton.configuration = config
        cameraToggleButton.accessibilityLabel = position == .front ? "Switch to back camera" : "Switch to front camera"
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
            if !debugView.isHidden && !isAdjustingTuningControls {
                let now = CACurrentMediaTime()
                if now - lastDebugUpdateTime >= debugUpdateInterval {
                    lastDebugUpdateTime = now
                    debugView.update(output: output, exerciseMode: model.exerciseMode)
                }
            }
        }
    }

    private func setTuningInteractionState(_ isInteracting: Bool) {
        isAdjustingTuningControls = isInteracting
        if !isInteracting {
            lastDebugUpdateTime = 0
        }
    }

    private func scheduleConfigurationUpdate(
        _ configuration: RepCountingConfiguration,
        for exerciseMode: ExerciseMode
    ) {
        pendingConfigurationUpdate?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.selectedExercise == exerciseMode else { return }
            self.coordinator.updateRepCountingConfiguration(configuration)
            self.debugView.updateConfiguration(configuration, exerciseMode: exerciseMode)
            self.saveRepTuning(configuration, for: exerciseMode)
        }

        pendingConfigurationUpdate = work
        DispatchQueue.main.asyncAfter(deadline: .now() + configurationDebounceInterval, execute: work)
    }

    private func saveRepTuning(_ configuration: RepCountingConfiguration, for exerciseMode: ExerciseMode) {
        let values: [String: Double] = [
            "armingThreshold": Double(configuration.armingThreshold),
            "minPeakHeight": Double(configuration.minPeakHeight),
            "minValleyDepth": Double(configuration.minValleyDepth),
            "peakWindowSize": Double(configuration.peakWindowSize),
            "minTimeBetweenReps": configuration.minTimeBetweenReps,
            "minAmplitude": Double(configuration.minAmplitude),
            "upThreshold": Double(configuration.upThreshold),
            "downThreshold": Double(configuration.downThreshold),
            "squatDescendEntryThreshold": Double(configuration.squatDescendEntryThreshold),
            "squatStandLockoutThreshold": Double(configuration.squatStandLockoutThreshold),
            "squatKneeBottomFlexionDegrees": Double(configuration.squatKneeBottomFlexionDegrees),
            "squatHipBottomFlexionDegrees": Double(configuration.squatHipBottomFlexionDegrees),
            "squatKneeLockoutFlexionDegrees": Double(configuration.squatKneeLockoutFlexionDegrees),
            "squatHipLockoutFlexionDegrees": Double(configuration.squatHipLockoutFlexionDegrees),
            "squatMaxSideAsymmetryDegrees": Double(configuration.squatMaxSideAsymmetryDegrees),
            "curlTopFlexionDegrees": Double(configuration.curlTopFlexionDegrees),
            "curlLockoutFlexionDegrees": Double(configuration.curlLockoutFlexionDegrees),
            "inactivityResetSeconds": configuration.inactivityResetSeconds,
            "activityDeltaThreshold": Double(configuration.activityDeltaThreshold),
            "spikeMaxDelta": Double(configuration.spikeMaxDelta),
            "emaAlpha": Double(configuration.emaAlpha),
        ]
        UserDefaults.standard.set(values, forKey: tuningStorageKey(for: exerciseMode))
    }

    private func saveExerciseMode(_ exerciseMode: ExerciseMode) {
        UserDefaults.standard.set(exerciseMode.rawValue, forKey: Self.exerciseModeStorageKey)
    }

    private func loadSavedExerciseMode() -> ExerciseMode {
        guard let raw = UserDefaults.standard.string(forKey: Self.exerciseModeStorageKey) else {
            return .squat
        }
        return ExerciseMode(rawValue: raw) ?? .squat
    }

    private static func tuningStorageKey(for exerciseMode: ExerciseMode) -> String {
        "\(tuningStoragePrefix).\(exerciseMode.rawValue)"
    }

    private func tuningStorageKey(for exerciseMode: ExerciseMode) -> String {
        Self.tuningStorageKey(for: exerciseMode)
    }

    private func saveCameraPosition(_ position: AVCaptureDevice.Position) {
        let rawValue = position == .back ? "back" : "front"
        UserDefaults.standard.set(rawValue, forKey: Self.cameraPositionStorageKey)
    }

    private func loadSavedCameraPosition() -> AVCaptureDevice.Position {
        guard let rawValue = UserDefaults.standard.string(forKey: Self.cameraPositionStorageKey) else {
            return .front
        }
        return rawValue == "back" ? .back : .front
    }

    private func loadSavedRepTuning(for exerciseMode: ExerciseMode) -> RepCountingConfiguration {
        guard
            let values = UserDefaults.standard.dictionary(forKey: tuningStorageKey(for: exerciseMode)),
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
            return LiveCameraCoordinator.defaultRepTuning(for: exerciseMode)
        }

        let defaults = LiveCameraCoordinator.defaultRepTuning(for: exerciseMode)
        let squatDescendEntryThreshold =
            (values["squatDescendEntryThreshold"] as? Double)
            ?? Double(defaults.squatDescendEntryThreshold)
        let squatStandLockoutThreshold =
            (values["squatStandLockoutThreshold"] as? Double)
            ?? Double(defaults.squatStandLockoutThreshold)
        let squatKneeBottomFlexionDegrees =
            (values["squatKneeBottomFlexionDegrees"] as? Double)
            ?? Double(defaults.squatKneeBottomFlexionDegrees)
        let squatHipBottomFlexionDegrees =
            (values["squatHipBottomFlexionDegrees"] as? Double)
            ?? Double(defaults.squatHipBottomFlexionDegrees)
        let squatKneeLockoutFlexionDegrees =
            (values["squatKneeLockoutFlexionDegrees"] as? Double)
            ?? Double(defaults.squatKneeLockoutFlexionDegrees)
        let squatHipLockoutFlexionDegrees =
            (values["squatHipLockoutFlexionDegrees"] as? Double)
            ?? Double(defaults.squatHipLockoutFlexionDegrees)
        let squatMaxSideAsymmetryDegrees =
            (values["squatMaxSideAsymmetryDegrees"] as? Double)
            ?? Double(defaults.squatMaxSideAsymmetryDegrees)
        let curlTopFlexionDegrees =
            (values["curlTopFlexionDegrees"] as? Double)
            ?? Double(defaults.curlTopFlexionDegrees)
        let curlLockoutFlexionDegrees =
            (values["curlLockoutFlexionDegrees"] as? Double)
            ?? Double(defaults.curlLockoutFlexionDegrees)

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
            squatDescendEntryThreshold: CGFloat(squatDescendEntryThreshold),
            squatStandLockoutThreshold: CGFloat(squatStandLockoutThreshold),
            squatKneeBottomFlexionDegrees: CGFloat(squatKneeBottomFlexionDegrees),
            squatHipBottomFlexionDegrees: CGFloat(squatHipBottomFlexionDegrees),
            squatKneeLockoutFlexionDegrees: CGFloat(squatKneeLockoutFlexionDegrees),
            squatHipLockoutFlexionDegrees: CGFloat(squatHipLockoutFlexionDegrees),
            squatMaxSideAsymmetryDegrees: CGFloat(squatMaxSideAsymmetryDegrees),
            curlTopFlexionDegrees: CGFloat(curlTopFlexionDegrees),
            curlLockoutFlexionDegrees: CGFloat(curlLockoutFlexionDegrees),
            inactivityResetSeconds: inactivityResetSeconds,
            activityDeltaThreshold: CGFloat(activityDeltaThreshold),
            spikeMaxDelta: CGFloat(spikeMaxDelta),
            emaAlpha: CGFloat(emaAlpha)
        )
    }
}

extension LiveCameraViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === debugToggleGesture else { return true }
        return !isInteractiveControlTouch(touch.view)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }

    private func isInteractiveControlTouch(_ touchedView: UIView?) -> Bool {
        var node = touchedView
        while let view = node {
            if view is UIControl {
                return true
            }
            if view === tuningPanel {
                return true
            }
            node = view.superview
        }
        return false
    }
}
