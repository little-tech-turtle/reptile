import CameraKit
import UIKit

/// UIScrollView subclass that prevents the scroll gesture from cancelling
/// touch tracking inside UISlider subviews. Without this override the pan
/// recogniser can steal the touch mid-drag, making sliders unresponsive.
private final class SliderFriendlyScrollView: UIScrollView {
    override func touchesShouldCancel(in view: UIView) -> Bool {
        view is UISlider ? false : super.touchesShouldCancel(in: view)
    }
}

final class RepTuningPanelView: UIView {
    var onConfigurationChanged: ((RepCountingConfiguration) -> Void)?
    var onInteractionChanged: ((Bool) -> Void)?

    private var configuration = RepCountingConfiguration()
    private var exerciseMode: ExerciseMode = .squat
    private var activeSliderInteractions = 0

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Rep Tuning"
        label.textColor = .white
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        return label
    }()

    private let resetButton: UIButton = {
        let button = UIButton(type: .system)
        var config = UIButton.Configuration.plain()
        config.title = "Reset"
        config.baseForegroundColor = .white
        config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10)
        button.configuration = config
        button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        button.backgroundColor = UIColor.white.withAlphaComponent(0.14)
        button.layer.cornerRadius = 8
        return button
    }()

    private let stackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        return stack
    }()

    private let scrollView: SliderFriendlyScrollView = {
        let scrollView = SliderFriendlyScrollView()
        scrollView.showsVerticalScrollIndicator = true
        scrollView.delaysContentTouches = false
        return scrollView
    }()

    private let kneeBottomRow = TuningSliderRow(title: "Knee bottom flexion", min: 45, max: 130, format: "%.0f°")
    private let hipBottomRow = TuningSliderRow(title: "Hip bottom flexion", min: 30, max: 120, format: "%.0f°")
    private let kneeLockoutRow = TuningSliderRow(title: "Knee lockout max", min: 0, max: 45, format: "%.0f°")
    private let hipLockoutRow = TuningSliderRow(title: "Hip lockout max", min: 0, max: 50, format: "%.0f°")
    private let curlTopRow = TuningSliderRow(title: "Curl top flexion", min: 45, max: 140, format: "%.0f°")
    private let curlLockoutRow = TuningSliderRow(title: "Curl lockout max", min: 0, max: 50, format: "%.0f°")
    private let minAmplitudeRow = TuningSliderRow(title: "Min range of motion", min: 0.05, max: 0.55, format: "%.0f%%", displayScale: 100)
    private let minTimeRow = TuningSliderRow(title: "Min time between reps", min: 0.20, max: 1.80, format: "%.1fs")

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        wireEvents()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
        wireEvents()
    }

    func apply(configuration: RepCountingConfiguration) {
        apply(configuration: configuration, exerciseMode: exerciseMode)
    }

    func apply(configuration: RepCountingConfiguration, exerciseMode: ExerciseMode) {
        self.configuration = configuration
        self.exerciseMode = exerciseMode
        titleLabel.text = "Rep Tuning (\(exerciseMode.title))"
        applyExerciseVisibility()
        syncRows()
    }

    @objc private func resetTapped() {
        applyAndPublish(LiveCameraCoordinator.defaultRepTuning(for: exerciseMode))
    }

    private func setupUI() {
        backgroundColor = UIColor.black.withAlphaComponent(0.68)
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous

        let header = UIStackView(arrangedSubviews: [titleLabel, UIView(), resetButton])
        header.axis = .horizontal
        header.alignment = .center
        header.translatesAutoresizingMaskIntoConstraints = false

        stackView.addArrangedSubview(kneeBottomRow)
        stackView.addArrangedSubview(hipBottomRow)
        stackView.addArrangedSubview(kneeLockoutRow)
        stackView.addArrangedSubview(hipLockoutRow)
        stackView.addArrangedSubview(curlTopRow)
        stackView.addArrangedSubview(curlLockoutRow)
        stackView.addArrangedSubview(minAmplitudeRow)
        stackView.addArrangedSubview(minTimeRow)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(header)
        addSubview(scrollView)
        scrollView.addSubview(stackView)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),

            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])
    }

    private func wireEvents() {
        resetButton.addTarget(self, action: #selector(resetTapped), for: .touchUpInside)

        kneeBottomRow.onValueChanged = { [weak self] value in
            self?.update { $0.squatKneeBottomFlexionDegrees = CGFloat(value) }
        }
        hipBottomRow.onValueChanged = { [weak self] value in
            self?.update { $0.squatHipBottomFlexionDegrees = CGFloat(value) }
        }
        kneeLockoutRow.onValueChanged = { [weak self] value in
            self?.update { $0.squatKneeLockoutFlexionDegrees = CGFloat(value) }
        }
        hipLockoutRow.onValueChanged = { [weak self] value in
            self?.update { $0.squatHipLockoutFlexionDegrees = CGFloat(value) }
        }
        curlTopRow.onValueChanged = { [weak self] value in
            self?.update { $0.curlTopFlexionDegrees = CGFloat(value) }
        }
        curlLockoutRow.onValueChanged = { [weak self] value in
            self?.update { $0.curlLockoutFlexionDegrees = CGFloat(value) }
        }
        minAmplitudeRow.onValueChanged = { [weak self] value in
            self?.update { $0.minAmplitude = CGFloat(value) }
        }
        minTimeRow.onValueChanged = { [weak self] value in
            self?.update { $0.minTimeBetweenReps = Double(value) }
        }

        let rows = [kneeBottomRow, hipBottomRow, kneeLockoutRow, hipLockoutRow, curlTopRow, curlLockoutRow, minAmplitudeRow, minTimeRow]
        for row in rows {
            row.onInteractionChanged = { [weak self] isInteracting in
                self?.handleRowInteractionChanged(isInteracting)
            }
        }
    }

    private func handleRowInteractionChanged(_ isInteracting: Bool) {
        if isInteracting {
            activeSliderInteractions += 1
            if activeSliderInteractions == 1 {
                onInteractionChanged?(true)
            }
            return
        }

        activeSliderInteractions = max(0, activeSliderInteractions - 1)
        if activeSliderInteractions == 0 {
            onInteractionChanged?(false)
        }
    }

    private func update(_ mutate: (inout RepCountingConfiguration) -> Void) {
        mutate(&configuration)
        onConfigurationChanged?(configuration)
    }

    private func applyAndPublish(_ configuration: RepCountingConfiguration) {
        apply(configuration: configuration)
        onConfigurationChanged?(configuration)
    }

    private func syncRows() {
        kneeBottomRow.setValue(Float(configuration.squatKneeBottomFlexionDegrees))
        hipBottomRow.setValue(Float(configuration.squatHipBottomFlexionDegrees))
        kneeLockoutRow.setValue(Float(configuration.squatKneeLockoutFlexionDegrees))
        hipLockoutRow.setValue(Float(configuration.squatHipLockoutFlexionDegrees))
        curlTopRow.setValue(Float(configuration.curlTopFlexionDegrees))
        curlLockoutRow.setValue(Float(configuration.curlLockoutFlexionDegrees))
        minAmplitudeRow.setValue(Float(configuration.minAmplitude))
        minTimeRow.setValue(Float(configuration.minTimeBetweenReps))
    }

    private func applyExerciseVisibility() {
        let isSquat = exerciseMode == .squat
        kneeBottomRow.isHidden = !isSquat
        hipBottomRow.isHidden = !isSquat
        kneeLockoutRow.isHidden = !isSquat
        hipLockoutRow.isHidden = !isSquat
        curlTopRow.isHidden = isSquat
        curlLockoutRow.isHidden = isSquat
    }
}

private final class TuningSliderRow: UIView {
    var onValueChanged: ((Float) -> Void)?
    var onInteractionChanged: ((Bool) -> Void)?

    private let titleLabel = UILabel()
    private let valueLabel = UILabel()
    private let slider = UISlider()
    private let format: String
    private let displayScale: Float
    private var isInteracting = false

    init(title: String, min: Float, max: Float, format: String, displayScale: Float = 1) {
        self.format = format
        self.displayScale = displayScale
        super.init(frame: .zero)

        titleLabel.text = title
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)

        valueLabel.textColor = .white
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        valueLabel.textAlignment = .right
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)

        slider.minimumValue = min
        slider.maximumValue = max
        slider.minimumTrackTintColor = .systemGreen
        slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.25)
        slider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
        slider.addTarget(self, action: #selector(sliderTouchDown), for: .touchDown)
        slider.addTarget(self, action: #selector(sliderTouchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        let top = UIStackView(arrangedSubviews: [titleLabel, UIView(), valueLabel])
        top.axis = .horizontal
        top.alignment = .center

        let stack = UIStackView(arrangedSubviews: [top, slider])
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func setValue(_ value: Float) {
        slider.setValue(value, animated: false)
        valueLabel.text = String(format: format, value * displayScale)
    }

    @objc private func sliderChanged() {
        if slider.isTracking {
            setInteracting(true)
        }
        valueLabel.text = String(format: format, slider.value * displayScale)
        onValueChanged?(slider.value)
    }

    @objc private func sliderTouchDown() {
        setInteracting(true)
    }

    @objc private func sliderTouchUp() {
        setInteracting(false)
    }

    private func setInteracting(_ interacting: Bool) {
        guard isInteracting != interacting else { return }
        isInteracting = interacting
        onInteractionChanged?(interacting)
    }
}
