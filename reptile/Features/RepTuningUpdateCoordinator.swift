import CameraKit
import Foundation

@MainActor
final class RepTuningUpdateCoordinator {
    typealias CancelSave = () -> Void
    typealias Scheduler = (_ delay: TimeInterval, _ action: @escaping () -> Void) -> CancelSave

    private let saveDebounceInterval: TimeInterval
    private let scheduler: Scheduler
    private var cancelPendingSave: CancelSave?

    init(
        saveDebounceInterval: TimeInterval = 0.12,
        scheduler: Scheduler? = nil
    ) {
        self.saveDebounceInterval = saveDebounceInterval
        self.scheduler = scheduler ?? { delay, action in
            let work = DispatchWorkItem(block: action)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            return {
                work.cancel()
            }
        }
    }

    deinit {
        cancelPendingSave?()
    }

    func apply(
        configuration: RepCountingConfiguration,
        for exerciseID: String,
        shouldPersist: @escaping (String) -> Bool,
        applyNow: (RepCountingConfiguration, String) -> Void,
        persist: @escaping (RepCountingConfiguration, String) -> Void
    ) {
        applyNow(configuration, exerciseID)

        cancelPendingSave?()
        cancelPendingSave = scheduler(saveDebounceInterval) {
            guard shouldPersist(exerciseID) else { return }
            persist(configuration, exerciseID)
        }
    }

}
