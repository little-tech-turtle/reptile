import CameraKit
import UIKit

final class RepTuningPanelView: UIView {
    var onConfigurationChanged: ((RepCountingConfiguration) -> Void)?

    private var configuration = RepCountingConfiguration()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Rep Tuning"
        label.textColor = .white
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        return label
    }()

    private let resetButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Reset", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        button.backgroundColor = UIColor.white.withAlphaComponent(0.14)
        button.layer.cornerRadius = 8
        button.contentEdgeInsets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
        return button
    }()

    private let stackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        return stack
    }()

    private let armingRow = TuningSliderRow(title: "Arming", min: 0.10, max: 0.90, format: "%.2f")
    private let minAmplitudeRow = TuningSliderRow(title: "Min amplitude", min: 0.05, max: 0.55, format: "%.2f")
    private let minTimeRow = TuningSliderRow(title: "Min rep time", min: 0.20, max: 1.80, format: "%.2fs")
    private let idleResetRow = TuningSliderRow(title: "Idle reset", min: 1.00, max: 8.00, format: "%.1fs")
    private let activityDeltaRow = TuningSliderRow(title: "Activity delta", min: 0.005, max: 0.060, format: "%.3f")

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
        self.configuration = configuration
        syncRows()
    }

    @objc private func resetTapped() {
        applyAndPublish(LiveCameraCoordinator.defaultRepTuning)
    }

    private func setupUI() {
        backgroundColor = UIColor.black.withAlphaComponent(0.68)
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous

        let header = UIStackView(arrangedSubviews: [titleLabel, UIView(), resetButton])
        header.axis = .horizontal
        header.alignment = .center
        header.translatesAutoresizingMaskIntoConstraints = false

        stackView.addArrangedSubview(armingRow)
        stackView.addArrangedSubview(minAmplitudeRow)
        stackView.addArrangedSubview(minTimeRow)
        stackView.addArrangedSubview(idleResetRow)
        stackView.addArrangedSubview(activityDeltaRow)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(header)
        addSubview(stackView)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            stackView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])
    }

    private func wireEvents() {
        resetButton.addTarget(self, action: #selector(resetTapped), for: .touchUpInside)

        armingRow.onValueChanged = { [weak self] value in
            self?.update { $0.armingThreshold = CGFloat(value) }
        }
        minAmplitudeRow.onValueChanged = { [weak self] value in
            self?.update { $0.minAmplitude = CGFloat(value) }
        }
        minTimeRow.onValueChanged = { [weak self] value in
            self?.update { $0.minTimeBetweenReps = Double(value) }
        }
        idleResetRow.onValueChanged = { [weak self] value in
            self?.update { $0.inactivityResetSeconds = Double(value) }
        }
        activityDeltaRow.onValueChanged = { [weak self] value in
            self?.update { $0.activityDeltaThreshold = CGFloat(value) }
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
        armingRow.setValue(Float(configuration.armingThreshold))
        minAmplitudeRow.setValue(Float(configuration.minAmplitude))
        minTimeRow.setValue(Float(configuration.minTimeBetweenReps))
        idleResetRow.setValue(Float(configuration.inactivityResetSeconds))
        activityDeltaRow.setValue(Float(configuration.activityDeltaThreshold))
    }
}

private final class TuningSliderRow: UIView {
    var onValueChanged: ((Float) -> Void)?

    private let titleLabel = UILabel()
    private let valueLabel = UILabel()
    private let slider = UISlider()
    private let format: String

    init(title: String, min: Float, max: Float, format: String) {
        self.format = format
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
        valueLabel.text = String(format: format, value)
    }

    @objc private func sliderChanged() {
        valueLabel.text = String(format: format, slider.value)
        onValueChanged?(slider.value)
    }
}
