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
    static let tuningStoragePrefix = "repTuning.v6"
    private static let cameraPositionStorageKey = "cameraPosition.v1"
    private static let exerciseIDStorageKey = "exerciseID.v1"

    private let previewView = CameraPreviewView()
    private let repCountLabel = UILabel()
    private let statusLabel = UILabel()
    private let exercisePicker = ExerciseNodePickerView()
    private let cameraToggleButton = UIButton(type: .system)
    private let overlayView = SkeletonOverlayView()
    private let debugView = DebugOverlayView()
    private let tuningPanel = RepTuningPanelView()
    private let repFeedbackPlayer = RepFeedbackPlayer()
    private let tuningUpdateCoordinator = RepTuningUpdateCoordinator()

    private let coordinator = LiveCameraCoordinator()
    private var selectedExerciseID = LiveCameraCoordinator.defaultExercise.id

    private let debugUpdateInterval: CFTimeInterval = 1.0 / 12.0
    private var lastDebugUpdateTime: CFTimeInterval = 0
    private var isAdjustingTuningControls = false
    private var lastRepCountForFeedback = 0
    private lazy var debugToggleGesture: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(toggleDebug))
        gesture.numberOfTapsRequired = 2
        gesture.cancelsTouchesInView = false
        gesture.delegate = self
        return gesture
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        setupPreviewView()
        setupOverlayView()
        setupRepCountLabel()
        setupStatusLabel()
        setupExercisePicker()
        setupCameraToggleButton()
        setupDebugView()
        setupTuningPanel()
        view.addGestureRecognizer(debugToggleGesture)

        let initialExerciseID = loadSavedExerciseID()
        let initialExerciseDefinition = LiveCameraCoordinator.definition(for: initialExerciseID)
            ?? LiveCameraCoordinator.defaultExercise
        selectedExerciseID = initialExerciseDefinition.id
        let initialTuning = loadSavedRepTuning(for: initialExerciseDefinition.id)
        let initialCameraPosition = loadSavedCameraPosition()

        coordinator.setExercise(id: initialExerciseDefinition.id, configuration: initialTuning)
        coordinator.setCameraPosition(initialCameraPosition)
        debugView.updateConfiguration(initialTuning, exerciseDefinition: initialExerciseDefinition)
        tuningPanel.apply(configuration: initialTuning, exerciseDefinition: initialExerciseDefinition)
        updateCameraToggleButton(for: initialCameraPosition)
        updateExercisePicker(for: initialExerciseDefinition.id)
        tuningPanel.onConfigurationChanged = { [weak self] config in
            guard let self else { return }
            self.scheduleConfigurationUpdate(config, for: self.selectedExerciseID)
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

    private func setupExercisePicker() {
        exercisePicker.translatesAutoresizingMaskIntoConstraints = false
        exercisePicker.onExerciseSelected = { [weak self] exerciseID in
            self?.applyExerciseSelection(exerciseID, persistSelection: true)
        }

        view.addSubview(exercisePicker)
        NSLayoutConstraint.activate([
            exercisePicker.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            exercisePicker.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            exercisePicker.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.80),
            exercisePicker.heightAnchor.constraint(equalToConstant: 94),
        ])

        view.bringSubviewToFront(exercisePicker)
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
            tuningPanel.topAnchor.constraint(greaterThanOrEqualTo: exercisePicker.bottomAnchor, constant: 8),
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

    private func applyExerciseSelection(_ exerciseID: String, persistSelection: Bool) {
        guard let exerciseDefinition = LiveCameraCoordinator.definition(for: exerciseID) else { return }
        if selectedExerciseID == exerciseDefinition.id {
            if persistSelection {
                saveExerciseID(exerciseDefinition.id)
            }
            return
        }

        selectedExerciseID = exerciseDefinition.id
        let tuning = loadSavedRepTuning(for: exerciseDefinition.id)
        coordinator.setExercise(id: exerciseDefinition.id, configuration: tuning)
        repCountLabel.text = "0"
        lastRepCountForFeedback = 0
        debugView.updateConfiguration(tuning, exerciseDefinition: exerciseDefinition)
        tuningPanel.apply(configuration: tuning, exerciseDefinition: exerciseDefinition)
        updateExercisePicker(for: exerciseDefinition.id)
        lastDebugUpdateTime = 0
        if persistSelection {
            saveExerciseID(exerciseDefinition.id)
        }
    }

    private func updateExercisePicker(for exerciseID: String) {
        exercisePicker.apply(
            exercises: LiveCameraCoordinator.availableExercises,
            selectedExerciseID: exerciseID
        )
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
            if output.repCount > lastRepCountForFeedback {
                let sound = LiveCameraCoordinator.definition(for: output.exerciseProfileID)?.repSound
                repFeedbackPlayer.playRepSound(sound)
            }
            lastRepCountForFeedback = output.repCount
            repCountLabel.text = "\(output.repCount)"
        } else {
            repCountLabel.text = "0"
            lastRepCountForFeedback = 0
        }

        statusLabel.text = model.statusText
        statusLabel.isHidden = model.statusText.isEmpty

        if let output = model.output {
            if !debugView.isHidden && !isAdjustingTuningControls {
                let now = CACurrentMediaTime()
                if now - lastDebugUpdateTime >= debugUpdateInterval {
                    lastDebugUpdateTime = now
                    let exerciseDefinition = LiveCameraCoordinator.definition(for: model.exerciseID)
                        ?? LiveCameraCoordinator.defaultExercise
                    debugView.update(output: output, exerciseDefinition: exerciseDefinition)
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
        for exerciseID: String
    ) {
        guard selectedExerciseID == exerciseID else { return }

        tuningUpdateCoordinator.apply(
            configuration: configuration,
            for: exerciseID,
            shouldPersist: { [weak self] id in
                self?.selectedExerciseID == id
            },
            applyNow: { [weak self] appliedConfig, id in
                guard let self else { return }
                self.coordinator.updateRepCountingConfiguration(appliedConfig)
                guard let definition = LiveCameraCoordinator.definition(for: id) else { return }
                self.debugView.updateConfiguration(appliedConfig, exerciseDefinition: definition)
            },
            persist: { [weak self] persistedConfig, id in
                self?.saveRepTuning(persistedConfig, for: id)
            }
        )
    }

    private func saveRepTuning(_ configuration: RepCountingConfiguration, for exerciseID: String) {
        let values: [String: Double] = [
            "armingThreshold": Double(configuration.common.armingThreshold),
            "inactivityResetSeconds": configuration.common.inactivityResetSeconds,
            "activityDeltaThreshold": Double(configuration.common.activityDeltaThreshold),
            "peakHistoryCapacity": Double(configuration.peakDetection.historyCapacity),
            "minPeakHeight": Double(configuration.peakDetection.minPeakHeight),
            "minValleyDepth": Double(configuration.peakDetection.minValleyDepth),
            "peakWindowSize": Double(configuration.peakDetection.windowSize),
            "minTimeBetweenReps": configuration.gates.minTimeBetweenReps,
            "minAmplitude": Double(configuration.gates.minAmplitude),
            "upThreshold": Double(configuration.gates.upThreshold),
            "downThreshold": Double(configuration.gates.downThreshold),
            "squatDescendEntryThreshold": Double(configuration.squat.descendEntryThreshold),
            "squatStandLockoutThreshold": Double(configuration.squat.standLockoutThreshold),
            "squatKneeBottomFlexionDegrees": Double(configuration.squat.kneeBottomFlexionDegrees),
            "squatHipBottomFlexionDegrees": Double(configuration.squat.hipBottomFlexionDegrees),
            "squatKneeLockoutFlexionDegrees": Double(configuration.squat.kneeLockoutFlexionDegrees),
            "squatHipLockoutFlexionDegrees": Double(configuration.squat.hipLockoutFlexionDegrees),
            "squatMaxSideAsymmetryDegrees": Double(configuration.squat.maxSideAsymmetryDegrees),
            "curlTopFlexionDegrees": Double(configuration.curl.topFlexionDegrees),
            "curlLockoutFlexionDegrees": Double(configuration.curl.lockoutFlexionDegrees),
            "benchBottomElbowFlexionDegrees": Double(configuration.bench.bottomElbowFlexionDegrees),
            "benchBottomShoulderFlexionDegrees": Double(configuration.bench.bottomShoulderFlexionDegrees),
            "benchLockoutElbowFlexionDegrees": Double(configuration.bench.lockoutElbowFlexionDegrees),
            "benchLockoutShoulderFlexionDegrees": Double(configuration.bench.lockoutShoulderFlexionDegrees),
            "spikeMaxDelta": Double(configuration.filters.spikeMaxDelta),
            "emaAlpha": Double(configuration.filters.emaAlpha),
        ]
        UserDefaults.standard.set(values, forKey: tuningStorageKey(for: exerciseID))
    }

    private func saveExerciseID(_ exerciseID: String) {
        UserDefaults.standard.set(exerciseID, forKey: Self.exerciseIDStorageKey)
    }

    private func loadSavedExerciseID() -> String {
        guard let savedID = UserDefaults.standard.string(forKey: Self.exerciseIDStorageKey) else {
            return LiveCameraCoordinator.defaultExercise.id
        }
        return LiveCameraCoordinator.definition(for: savedID)?.id ?? LiveCameraCoordinator.defaultExercise.id
    }

    private static func tuningStorageKey(for exerciseID: String) -> String {
        "\(tuningStoragePrefix).\(exerciseID)"
    }

    private func tuningStorageKey(for exerciseID: String) -> String {
        Self.tuningStorageKey(for: exerciseID)
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

    private func loadSavedRepTuning(for exerciseID: String) -> RepCountingConfiguration {
        guard
            let values = UserDefaults.standard.dictionary(forKey: tuningStorageKey(for: exerciseID)),
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
            return LiveCameraCoordinator.defaultRepTuning(for: exerciseID)
        }

        let defaults = LiveCameraCoordinator.defaultRepTuning(for: exerciseID)
        let peakHistoryCapacity =
            (values["peakHistoryCapacity"] as? Double)
            ?? Double(defaults.peakDetection.historyCapacity)
        let squatDescendEntryThreshold =
            (values["squatDescendEntryThreshold"] as? Double)
            ?? Double(defaults.squat.descendEntryThreshold)
        let squatStandLockoutThreshold =
            (values["squatStandLockoutThreshold"] as? Double)
            ?? Double(defaults.squat.standLockoutThreshold)
        let squatKneeBottomFlexionDegrees =
            (values["squatKneeBottomFlexionDegrees"] as? Double)
            ?? Double(defaults.squat.kneeBottomFlexionDegrees)
        let squatHipBottomFlexionDegrees =
            (values["squatHipBottomFlexionDegrees"] as? Double)
            ?? Double(defaults.squat.hipBottomFlexionDegrees)
        let squatKneeLockoutFlexionDegrees =
            (values["squatKneeLockoutFlexionDegrees"] as? Double)
            ?? Double(defaults.squat.kneeLockoutFlexionDegrees)
        let squatHipLockoutFlexionDegrees =
            (values["squatHipLockoutFlexionDegrees"] as? Double)
            ?? Double(defaults.squat.hipLockoutFlexionDegrees)
        let squatMaxSideAsymmetryDegrees =
            (values["squatMaxSideAsymmetryDegrees"] as? Double)
            ?? Double(defaults.squat.maxSideAsymmetryDegrees)
        let curlTopFlexionDegrees =
            (values["curlTopFlexionDegrees"] as? Double)
            ?? Double(defaults.curl.topFlexionDegrees)
        let curlLockoutFlexionDegrees =
            (values["curlLockoutFlexionDegrees"] as? Double)
            ?? Double(defaults.curl.lockoutFlexionDegrees)
        let benchBottomElbowFlexionDegrees =
            (values["benchBottomElbowFlexionDegrees"] as? Double)
            ?? Double(defaults.bench.bottomElbowFlexionDegrees)
        let benchBottomShoulderFlexionDegrees =
            (values["benchBottomShoulderFlexionDegrees"] as? Double)
            ?? Double(defaults.bench.bottomShoulderFlexionDegrees)
        let benchLockoutElbowFlexionDegrees =
            (values["benchLockoutElbowFlexionDegrees"] as? Double)
            ?? Double(defaults.bench.lockoutElbowFlexionDegrees)
        let benchLockoutShoulderFlexionDegrees =
            (values["benchLockoutShoulderFlexionDegrees"] as? Double)
            ?? Double(defaults.bench.lockoutShoulderFlexionDegrees)

        return RepCountingConfiguration(
            common: .init(
                armingThreshold: CGFloat(armingThreshold),
                inactivityResetSeconds: inactivityResetSeconds,
                activityDeltaThreshold: CGFloat(activityDeltaThreshold)
            ),
            peakDetection: .init(
                historyCapacity: Int(peakHistoryCapacity),
                minPeakHeight: CGFloat(minPeakHeight),
                minValleyDepth: CGFloat(minValleyDepth),
                windowSize: Int(peakWindowSize)
            ),
            gates: .init(
                minTimeBetweenReps: minTimeBetweenReps,
                minAmplitude: CGFloat(minAmplitude),
                upThreshold: CGFloat(upThreshold),
                downThreshold: CGFloat(downThreshold)
            ),
            filters: .init(
                spikeMaxDelta: CGFloat(spikeMaxDelta),
                emaAlpha: CGFloat(emaAlpha)
            ),
            squat: .init(
                descendEntryThreshold: CGFloat(squatDescendEntryThreshold),
                standLockoutThreshold: CGFloat(squatStandLockoutThreshold),
                kneeBottomFlexionDegrees: CGFloat(squatKneeBottomFlexionDegrees),
                hipBottomFlexionDegrees: CGFloat(squatHipBottomFlexionDegrees),
                kneeLockoutFlexionDegrees: CGFloat(squatKneeLockoutFlexionDegrees),
                hipLockoutFlexionDegrees: CGFloat(squatHipLockoutFlexionDegrees),
                maxSideAsymmetryDegrees: CGFloat(squatMaxSideAsymmetryDegrees)
            ),
            curl: .init(
                topFlexionDegrees: CGFloat(curlTopFlexionDegrees),
                lockoutFlexionDegrees: CGFloat(curlLockoutFlexionDegrees)
            ),
            bench: .init(
                bottomElbowFlexionDegrees: CGFloat(benchBottomElbowFlexionDegrees),
                bottomShoulderFlexionDegrees: CGFloat(benchBottomShoulderFlexionDegrees),
                lockoutElbowFlexionDegrees: CGFloat(benchLockoutElbowFlexionDegrees),
                lockoutShoulderFlexionDegrees: CGFloat(benchLockoutShoulderFlexionDegrees)
            )
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
