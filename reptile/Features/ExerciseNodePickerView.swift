import UIKit

struct ExerciseNodePickerLayout {
    struct Node {
        let id: String
        let center: CGPoint
        let radius: CGFloat
    }

    let nodes: [Node]

    func nearestNodeID(to point: CGPoint, extraHitRadius: CGFloat = 0) -> String? {
        guard let nearest = nodes.min(by: {
            distanceSquared(from: point, to: $0.center) < distanceSquared(from: point, to: $1.center)
        }) else {
            return nil
        }

        let hitRadius = max(0, nearest.radius + max(0, extraHitRadius))
        let hitRadiusSquared = hitRadius * hitRadius
        let nearestDistanceSquared = distanceSquared(from: point, to: nearest.center)
        return nearestDistanceSquared <= hitRadiusSquared ? nearest.id : nil
    }

    private func distanceSquared(from lhs: CGPoint, to rhs: CGPoint) -> CGFloat {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return dx * dx + dy * dy
    }
}

final class ExerciseNodePickerView: UIView {
    var onExerciseSelected: ((String) -> Void)?

    private let triggerButton = UIButton(type: .system)
    private let holdGesture = UILongPressGestureRecognizer()

    private var exercises: [ExerciseDefinition] = []
    private var selectedExerciseID: String = ""
    private var highlightedNodeID: String?
    private var nodeButtons: [String: UIButton] = [:]
    private var isExpanded = false

    private let nodeDiameter: CGFloat = 52
    private let nodeSpacing: CGFloat = 12
    private let nodeSelectionSlop: CGFloat = 22

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        setupGestures()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
        setupGestures()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutNodeButtons()
    }

    func apply(exercises: [ExerciseDefinition], selectedExerciseID: String) {
        self.exercises = exercises
        rebuildNodes()
        selectExercise(selectedExerciseID, notify: false)
        setExpanded(false, animated: false)
    }

    private func setupUI() {
        triggerButton.configuration = makeTriggerConfiguration(title: "Exercise")
        triggerButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        triggerButton.translatesAutoresizingMaskIntoConstraints = false
        triggerButton.accessibilityLabel = "Hold to switch exercise"

        addSubview(triggerButton)

        NSLayoutConstraint.activate([
            triggerButton.topAnchor.constraint(equalTo: topAnchor),
            triggerButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            triggerButton.heightAnchor.constraint(equalToConstant: 40),
            triggerButton.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor),
            triggerButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 170),
        ])
    }

    private func setupGestures() {
        holdGesture.minimumPressDuration = 0.22
        holdGesture.allowableMovement = 180
        holdGesture.addTarget(self, action: #selector(handleHold(_:)))
        triggerButton.addGestureRecognizer(holdGesture)
    }

    private func rebuildNodes() {
        for button in nodeButtons.values {
            button.removeFromSuperview()
        }
        nodeButtons.removeAll()

        for exercise in exercises {
            let button = UIButton(type: .system)
            button.setTitle(exercise.shortTitle, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
            button.setTitleColor(.white, for: .normal)
            button.backgroundColor = UIColor.black.withAlphaComponent(0.62)
            button.layer.cornerRadius = nodeDiameter / 2
            button.layer.cornerCurve = .continuous
            button.layer.borderWidth = 1
            button.layer.borderColor = UIColor.white.withAlphaComponent(0.32).cgColor
            button.isHidden = true
            button.alpha = 0
            addSubview(button)
            nodeButtons[exercise.id] = button
        }
    }

    private func layoutNodeButtons() {
        guard !exercises.isEmpty else { return }

        let totalWidth = CGFloat(exercises.count) * nodeDiameter + CGFloat(max(exercises.count - 1, 0)) * nodeSpacing
        let startX = bounds.midX - totalWidth / 2 + nodeDiameter / 2
        let centerY = triggerButton.frame.maxY + 10 + nodeDiameter / 2

        for (index, exercise) in exercises.enumerated() {
            guard let button = nodeButtons[exercise.id] else { continue }
            button.bounds = CGRect(x: 0, y: 0, width: nodeDiameter, height: nodeDiameter)
            button.center = CGPoint(
                x: startX + CGFloat(index) * (nodeDiameter + nodeSpacing),
                y: centerY
            )
        }
    }

    @objc private func handleHold(_ gesture: UILongPressGestureRecognizer) {
        let location = gesture.location(in: self)

        switch gesture.state {
        case .began:
            setExpanded(true, animated: true)
            updateHighlightedNode(at: location)
        case .changed:
            updateHighlightedNode(at: location)
        case .ended:
            if let highlightedNodeID {
                selectExercise(highlightedNodeID, notify: true)
            }
            setExpanded(false, animated: true)
        case .cancelled, .failed:
            setExpanded(false, animated: true)
        default:
            break
        }
    }

    private func setExpanded(_ expanded: Bool, animated: Bool) {
        guard expanded != isExpanded || !animated else { return }
        isExpanded = expanded
        if !expanded {
            highlightedNodeID = nil
        }
        updateNodeStyles()

        let animations = {
            for exercise in self.exercises {
                guard let button = self.nodeButtons[exercise.id] else { continue }
                button.alpha = expanded ? 1 : 0
                button.transform = expanded ? .identity : CGAffineTransform(scaleX: 0.82, y: 0.82)
            }
        }

        if expanded {
            for exercise in exercises {
                guard let button = nodeButtons[exercise.id] else { continue }
                button.isHidden = false
                button.transform = CGAffineTransform(scaleX: 0.82, y: 0.82)
            }
        }

        if animated {
            UIView.animate(withDuration: 0.16, delay: 0, options: [.curveEaseInOut], animations: animations) { _ in
                if !expanded {
                    for exercise in self.exercises {
                        self.nodeButtons[exercise.id]?.isHidden = true
                    }
                }
            }
        } else {
            animations()
            if !expanded {
                for exercise in exercises {
                    nodeButtons[exercise.id]?.isHidden = true
                }
            }
        }
    }

    private func updateHighlightedNode(at point: CGPoint) {
        guard isExpanded else { return }
        let layout = currentLayout()
        highlightedNodeID = layout.nearestNodeID(to: point, extraHitRadius: nodeSelectionSlop)
        updateNodeStyles()
    }

    private func currentLayout() -> ExerciseNodePickerLayout {
        let nodes = exercises.compactMap { exercise -> ExerciseNodePickerLayout.Node? in
            guard let button = nodeButtons[exercise.id], !button.isHidden else { return nil }
            return ExerciseNodePickerLayout.Node(
                id: exercise.id,
                center: button.center,
                radius: nodeDiameter / 2
            )
        }
        return ExerciseNodePickerLayout(nodes: nodes)
    }

    private func selectExercise(_ exerciseID: String, notify: Bool) {
        guard exercises.contains(where: { $0.id == exerciseID }) else { return }
        selectedExerciseID = exerciseID

        let selectedTitle = exercises.first(where: { $0.id == exerciseID })?.title ?? "Exercise"
        triggerButton.configuration = makeTriggerConfiguration(title: "\(selectedTitle) (hold)")
        updateNodeStyles()

        if notify {
            onExerciseSelected?(exerciseID)
        }
    }

    private func updateNodeStyles() {
        for exercise in exercises {
            guard let button = nodeButtons[exercise.id] else { continue }

            if exercise.id == selectedExerciseID {
                button.backgroundColor = UIColor.white.withAlphaComponent(0.95)
                button.setTitleColor(.black, for: .normal)
                button.layer.borderColor = UIColor.white.cgColor
                button.layer.borderWidth = 1.5
                continue
            }

            if isExpanded, exercise.id == highlightedNodeID {
                button.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.92)
                button.setTitleColor(.black, for: .normal)
                button.layer.borderColor = UIColor.white.withAlphaComponent(0.9).cgColor
                button.layer.borderWidth = 1.5
                continue
            }

            button.backgroundColor = UIColor.black.withAlphaComponent(0.62)
            button.setTitleColor(.white, for: .normal)
            button.layer.borderColor = UIColor.white.withAlphaComponent(0.32).cgColor
            button.layer.borderWidth = 1
        }
    }

    private func makeTriggerConfiguration(title: String) -> UIButton.Configuration {
        var config = UIButton.Configuration.filled()
        config.title = title
        config.image = UIImage(systemName: "dot.circle.and.hand.point.up.left.fill")
        config.imagePadding = 6
        config.cornerStyle = .capsule
        config.baseBackgroundColor = UIColor.black.withAlphaComponent(0.55)
        config.baseForegroundColor = .white
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        return config
    }
}
