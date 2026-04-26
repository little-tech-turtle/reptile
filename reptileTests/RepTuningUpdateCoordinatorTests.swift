import CameraKit
import Foundation
import Testing
@testable import reptile

@MainActor
struct RepTuningUpdateCoordinatorTests {
    @Test func applyUpdatesImmediatelyWithoutWaitingForSaveDebounce() {
        let scheduler = TestScheduler()
        let coordinator = RepTuningUpdateCoordinator(
            saveDebounceInterval: 0.12,
            scheduler: scheduler.schedule
        )

        var appliedDownThresholds: [CGFloat] = []
        var persistedDownThresholds: [CGFloat] = []

        var config = LiveCameraCoordinator.defaultRepTuning(for: "bicepCurl")
        config.gates.downThreshold = 0.41

        coordinator.apply(
            configuration: config,
            for: "bicepCurl",
            shouldPersist: { _ in true },
            applyNow: { appliedConfig, _ in
                appliedDownThresholds.append(appliedConfig.gates.downThreshold)
            },
            persist: { persistedConfig, _ in
                persistedDownThresholds.append(persistedConfig.gates.downThreshold)
            }
        )

        #expect(appliedDownThresholds == [0.41])
        #expect(persistedDownThresholds.isEmpty)

        scheduler.runPending()
        #expect(persistedDownThresholds == [0.41])
    }

    @Test func applyDebouncesPersistenceAndSavesLatestConfiguration() {
        let scheduler = TestScheduler()
        let coordinator = RepTuningUpdateCoordinator(
            saveDebounceInterval: 0.12,
            scheduler: scheduler.schedule
        )

        var persistedDownThresholds: [CGFloat] = []

        var first = LiveCameraCoordinator.defaultRepTuning(for: "bicepCurl")
        first.gates.downThreshold = 0.28
        var second = LiveCameraCoordinator.defaultRepTuning(for: "bicepCurl")
        second.gates.downThreshold = 0.45

        coordinator.apply(
            configuration: first,
            for: "bicepCurl",
            shouldPersist: { _ in true },
            applyNow: { _, _ in },
            persist: { persistedConfig, _ in
                persistedDownThresholds.append(persistedConfig.gates.downThreshold)
            }
        )

        coordinator.apply(
            configuration: second,
            for: "bicepCurl",
            shouldPersist: { _ in true },
            applyNow: { _, _ in },
            persist: { persistedConfig, _ in
                persistedDownThresholds.append(persistedConfig.gates.downThreshold)
            }
        )

        scheduler.runPending()
        #expect(persistedDownThresholds == [0.45])
    }

    @Test func applySkipsPersistenceWhenExerciseChangedBeforeSaveRuns() {
        let scheduler = TestScheduler()
        let coordinator = RepTuningUpdateCoordinator(
            saveDebounceInterval: 0.12,
            scheduler: scheduler.schedule
        )

        var persistCallCount = 0
        let config = LiveCameraCoordinator.defaultRepTuning(for: "bicepCurl")

        coordinator.apply(
            configuration: config,
            for: "bicepCurl",
            shouldPersist: { _ in false },
            applyNow: { _, _ in },
            persist: { _, _ in
                persistCallCount += 1
            }
        )

        scheduler.runPending()
        #expect(persistCallCount == 0)
    }
}

@MainActor
private final class TestScheduler {
    private final class ScheduledItem {
        var isCancelled = false
        let action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }
    }

    private var items: [ScheduledItem] = []

    func schedule(_ delay: TimeInterval, _ action: @escaping () -> Void) -> () -> Void {
        _ = delay
        let item = ScheduledItem(action: action)
        items.append(item)
        return { [weak item] in
            item?.isCancelled = true
        }
    }

    func runPending() {
        let queued = items
        items.removeAll()

        for item in queued where !item.isCancelled {
            item.action()
        }
    }
}
