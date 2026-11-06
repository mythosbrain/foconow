import DeviceActivity
import FamilyControls
import Foundation

/// iOS invokes this extension independently of the app when selected usage reaches the allowance.
final class HabitFocusMonitor: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        handle(activity: activity, thresholdEvent: nil)
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        handle(activity: activity, thresholdEvent: event)
    }

    private func handle(activity: DeviceActivityName, thresholdEvent: DeviceActivityEvent.Name?) {
        do {
            try FocusStateStorage.withLock { storage in
                var config = try storage.read()
                guard config.mode == .dailyLimit,
                      config.selectedCount > 0,
                      config.activityName == activity else { return }
                if let thresholdEvent, thresholdEvent != config.eventName { return }
                let today = FocusPolicy.dayKey()
                if thresholdEvent != nil {
                    config.reachedDay = today
                    try storage.write(config)
                    FocusPolicy.applyShield(config.selection)
                } else if config.reachedDay == today {
                    // Duplicate start callbacks (or re-registering the same monitor) cannot unlock it.
                    FocusPolicy.applyShield(config.selection)
                } else {
                    config.reachedDay = nil
                    try storage.write(config)
                    FocusPolicy.clearShield()
                }
            }
        } catch {
            // Never invent a replacement state or clear an unrelated/newer policy on a read failure.
            // A correctly entitled app can recover using its explicit Turn Off action.
            NSLog("Habit Counter focus monitor could not access its shared policy: %@", error.localizedDescription)
        }
    }
}
