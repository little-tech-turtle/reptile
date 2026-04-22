import CameraKit
import UIKit

private final class SliderFriendlyScrollView: UIScrollView {
    override func touchesShouldCancel(in view: UIView) -> Bool {
        view is UISlider ? false : super.touchesShouldCancel(in: view)
    }
}

final class RepTuningPanelView: UIView {
    var onConfigurationChanged: ((RepCountingConfiguration) -> Void)?
    var onInteractionChanged: ((Bool) -> Void)?

    private struct RowBinding {
        let control: TuningControlDefinition
        let row: TuningSliderRow
    }

    private var configuration = RepCountingConfiguration()
    private var exerciseDefinition: ExerciseDefinition = ExerciseCatalog.defaultExercise
    private var rowBindings: [RowBinding] = []
    private var activeSliderInteractions = 0

    private let titleLabel: UILabel = {
        let label = UILabel()
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

    func apply(
        configuration: RepCountingConfiguration,
        exerciseDefinition: ExerciseDefinition
    ) {
        self.configuration = configuration
        self.exerciseDefinition = exerciseDefinition
        titleLabel.text = "Rep Tuning (\(exerciseDefinition.title))"
        rebuildRowsIfNeeded(for: exerciseDefinition)
        syncRows()
    }

    @objc private func resetTapped() {
        applyAndPublish(exerciseDefinition.defaultTuning)
    }

    private func setupUI() {
        backgroundColor = UIColor.black.withAlphaComponent(0.68)
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous

        let header = UIStackView(arrangedSubviews: [titleLabel, UIView(), resetButton])
        header.axis = .horizontal
        header.alignment = .center
        header.translatesAutoresizingMaskIntoConstraints = false

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
    }

    private func rebuildRowsIfNeeded(for definition: ExerciseDefinition) {
        let currentIDs = rowBindings.map { $0.control.id }
        let targetIDs = definition.tuningControls.map { $0.id }
        guard currentIDs != targetIDs else { return }

        for binding in rowBindings {
            binding.row.removeFromSuperview()
        }
        rowBindings.removeAll()

        for control in definition.tuningControls {
            let row = TuningSliderRow(
                title: control.title,
                hint: control.hint,
                min: control.min,
                max: control.max,
                format: control.format,
                displayScale: control.displayScale
            )

            row.onValueChanged = { [weak self] value in
                guard let self else { return }
                self.update { config in
                    control.writeValue(&config, value)
                }
            }

            row.onInteractionChanged = { [weak self] isInteracting in
                self?.handleRowInteractionChanged(isInteracting)
            }

            stackView.addArrangedSubview(row)
            rowBindings.append(RowBinding(control: control, row: row))
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
        apply(configuration: configuration, exerciseDefinition: exerciseDefinition)
        onConfigurationChanged?(configuration)
    }

    private func syncRows() {
        for binding in rowBindings {
            binding.row.setValue(binding.control.readValue(configuration))
        }
    }
}

private final class TuningSliderRow: UIView {
    var onValueChanged: ((Float) -> Void)?
    var onInteractionChanged: ((Bool) -> Void)?

    private let titleLabel = UILabel()
    private let hintLabel = UILabel()
    private let valueLabel = UILabel()
    private let slider = UISlider()
    private let format: String
    private let displayScale: Float
    private var isInteracting = false

    init(title: String, hint: String, min: Float, max: Float, format: String, displayScale: Float = 1) {
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

        hintLabel.text = hint
        hintLabel.textColor = UIColor.white.withAlphaComponent(0.78)
        hintLabel.font = .systemFont(ofSize: 11, weight: .regular)
        hintLabel.numberOfLines = 0

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

        let stack = UIStackView(arrangedSubviews: [top, hintLabel, slider])
        stack.axis = .vertical
        stack.spacing = 3
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
        fatalError("init(coder:) has not been implemented")
    }

    func setValue(_ value: Float) {
        slider.setValue(value, animated: false)
        updateValueLabel(value)
    }

    @objc private func sliderChanged() {
        let value = slider.value
        updateValueLabel(value)
        onValueChanged?(value)
    }

    @objc private func sliderTouchDown() {
        guard !isInteracting else { return }
        isInteracting = true
        onInteractionChanged?(true)
    }

    @objc private func sliderTouchUp() {
        guard isInteracting else { return }
        isInteracting = false
        onInteractionChanged?(false)
    }

    private func updateValueLabel(_ value: Float) {
        valueLabel.text = String(format: format, value * displayScale)
    }
}
