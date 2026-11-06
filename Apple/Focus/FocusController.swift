#if os(iOS)
import Foundation
import Combine
import FamilyControls
import ManagedSettings
import DeviceActivity

@MainActor
final class FocusController: ObservableObject {
    @Published private(set) var configuration = FocusConfiguration()
    @Published private(set) var authorizationStatus: AuthorizationStatus = .notDetermined
    @Published private(set) var errorMessage: String?
    @Published private(set) var statusMessage: String?
    @Published private(set) var isBusy = false
    @Published private(set) var sharedStorageAvailable = false
    @Published private(set) var hasReadableConfiguration = false
    private var authorizationObserver: AnyCancellable?

    var isAuthorized: Bool { FocusPolicy.authorized(authorizationStatus) }
    var selectedCount: Int { configuration.selectedCount }
    var dailyLimitAvailable: Bool { if #available(iOS 17.4, *) { return true }; return false }
    var isDailyLimitReached: Bool { configuration.mode == .dailyLimit && configuration.reachedDay == FocusPolicy.dayKey() }
    var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    init() {
        refresh()
        authorizationObserver = AuthorizationCenter.shared.$authorizationStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in Task { @MainActor [weak self] in self?.refresh() } }
    }

    func refresh() {
        authorizationStatus = AuthorizationCenter.shared.authorizationStatus
        do {
            let value = try FocusStateStorage.withLock { storage -> FocusConfiguration in
                var current = try storage.read()
                // Apple initializes this property as notDetermined in each process. It is not
                // evidence that the user revoked an already active, persisted policy.
                if authorizationStatus == .notDetermined { return current }
                if authorizationStatus == .denied {
                    // Revoked authorization invalidates the privacy-preserving selection tokens.
                    if current.mode != .off || current.selectedCount > 0 || current.reachedDay != nil {
                        current.mode = .off
                        current.selection = FamilyActivitySelection(includeEntireCategory: true)
                        current.generation = UUID().uuidString.lowercased()
                        current.reachedDay = nil
                        try storage.write(current)
                        FocusPolicy.stopOwnedMonitors()
                        if !isSimulator { FocusPolicy.clearShield() }
                    }
                    return current
                }
                guard isAuthorized else { return current }
                if current.mode != .off && current.selectedCount == 0 {
                    current.mode = .off
                    current.generation = UUID().uuidString.lowercased()
                    current.reachedDay = nil
                    try storage.write(current)
                    FocusPolicy.stopOwnedMonitors()
                    FocusPolicy.clearShield()
                    return current
                }
                switch current.mode {
                case .off: FocusPolicy.clearShield()
                case .block: FocusPolicy.applyShield(current.selection)
                case .dailyLimit:
                    guard #available(iOS 17.4, *) else {
                        current.mode = .off; current.reachedDay = nil
                        try storage.write(current)
                        FocusPolicy.stopOwnedMonitors(); FocusPolicy.clearShield()
                        return current
                    }
                    // The extension's reached marker is authoritative for the current local day.
                    // Reopening this screen must never reset a reached allowance.
                    if current.reachedDay == FocusPolicy.dayKey() { FocusPolicy.applyShield(current.selection) }
                    else {
                        if current.reachedDay != nil { current.reachedDay = nil; try storage.write(current) }
                        FocusPolicy.clearShield()
                    }
                    if !DeviceActivityCenter().activities.contains(current.activityName) {
                        do { try FocusPolicy.startMonitor(current) }
                        catch {
                            current.mode = .off
                            current.generation = UUID().uuidString.lowercased()
                            current.reachedDay = nil
                            try storage.write(current)
                            FocusPolicy.stopOwnedMonitors(); FocusPolicy.clearShield()
                            throw error
                        }
                    }
                }
                return current
            }
            configuration = value
            hasReadableConfiguration = true
            sharedStorageAvailable = true
            errorMessage = nil
        } catch {
            hasReadableConfiguration = false
            sharedStorageAvailable = (try? FocusStateStorage.container()) != nil
            errorMessage = error.localizedDescription
            // Do not advertise previously cached restrictions as active after a failed refresh.
            configuration.mode = .off
        }
    }

    func requestAuthorization() async {
        guard !isBusy else { return }
        errorMessage = nil; statusMessage = nil
        guard !isSimulator else {
            errorMessage = "Screen Time authorization and enforcement need an appropriately signed app on a physical iPhone. The simulator can preview this screen."
            return
        }
        guard sharedStorageAvailable else { errorMessage = FocusStateError.missingContainer.localizedDescription; return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            refresh()
            if isAuthorized { statusMessage = "Screen Time access is ready. Choose the apps you want to manage." }
        } catch {
            let message = "Screen Time access wasn’t granted. \(error.localizedDescription)"
            refresh()
            errorMessage = message
        }
    }

    @discardableResult
    func saveSelection(_ selection: FamilyActivitySelection) -> Bool {
        guard !isBusy else { return false }
        errorMessage = nil; statusMessage = nil
        guard isAuthorized else { errorMessage = "Verify Screen Time access before changing your app selection."; return false }
        do {
            var stopped = false
            let value = try FocusStateStorage.withLock { storage -> FocusConfiguration in
                var current = try storage.read()
                guard current.selection != selection else { return current }
                stopped = current.mode != .off
                current.selection = selection
                current.mode = .off
                current.reachedDay = nil
                current.generation = UUID().uuidString.lowercased()
                try storage.write(current)
                FocusPolicy.stopOwnedMonitors()
                if !isSimulator { FocusPolicy.clearShield() }
                return current
            }
            configuration = value
            hasReadableConfiguration = true
            statusMessage = stopped ? "Selection saved. Your previous restriction is off; apply your updated choice below." : "Selection saved on this iPhone."
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func startBlocking() { apply(mode: .block, minutes: configuration.dailyMinutes) }
    func startDailyLimit(minutes: Int) {
        guard dailyLimitAvailable else { errorMessage = "Daily limits require iOS 17.4 or later."; return }
        apply(mode: .dailyLimit, minutes: minutes)
    }

    private func apply(mode: FocusMode, minutes: Int) {
        guard !isBusy else { return }
        errorMessage = nil; statusMessage = nil
        authorizationStatus = AuthorizationCenter.shared.authorizationStatus
        guard !isSimulator else { errorMessage = "Real app blocking must be tested on a signed physical iPhone."; return }
        guard isAuthorized else { errorMessage = "Allow Screen Time access before applying app restrictions."; return }
        guard (1...1440).contains(minutes) else { errorMessage = FocusStateError.invalidBudget.localizedDescription; return }
        isBusy = true
        defer { isBusy = false }
        do {
            configuration = try FocusStateStorage.withLock { storage -> FocusConfiguration in
                let previous = try storage.read()
                guard previous.selectedCount > 0 else { throw FocusStateError.invalidSelection }
                // No-op preserves both the event accounting and today's reached marker.
                if previous.mode == mode && (mode != .dailyLimit || previous.dailyMinutes == minutes) { return previous }
                var next = previous
                next.mode = mode
                next.dailyMinutes = minutes
                next.generation = UUID().uuidString.lowercased()
                next.reachedDay = nil
                try storage.write(next)
                FocusPolicy.stopOwnedMonitors()
                do {
                    if mode == .block { FocusPolicy.applyShield(next.selection) }
                    else if #available(iOS 17.4, *) {
                        // Count activity already used in today's interval when installing/reconfiguring.
                        FocusPolicy.clearShield()
                        try FocusPolicy.startMonitor(next)
                    }
                } catch {
                    next.mode = .off
                    next.reachedDay = nil
                    next.generation = UUID().uuidString.lowercased()
                    try storage.write(next)
                    FocusPolicy.stopOwnedMonitors(); FocusPolicy.clearShield()
                    throw error
                }
                return next
            }
            hasReadableConfiguration = true
            statusMessage = mode == .block ? "Blocking is applied to your selection. You can turn it off here." : "Daily allowance is monitored across your selection. The allowance resets each day."
        } catch {
            errorMessage = error.localizedDescription
            if let current = try? FocusStateStorage.withLock({ try $0.read() }) { configuration = current; hasReadableConfiguration = true } else { hasReadableConfiguration = false }
        }
    }

    func stop() {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        errorMessage = nil; statusMessage = nil
        do {
            configuration = try FocusStateStorage.withLock { storage -> FocusConfiguration in
                var current = try storage.read()
                current.mode = .off
                current.reachedDay = nil
                current.generation = UUID().uuidString.lowercased()
                // Persist the disabled generation before touching monitors/shields.
                try storage.write(current)
                FocusPolicy.stopOwnedMonitors()
                if !isSimulator { FocusPolicy.clearShield() }
                return current
            }
            hasReadableConfiguration = true
            statusMessage = "App restrictions are off."
        } catch {
            // A missing/corrupt shared container should not prevent this explicit recovery action.
            FocusPolicy.stopOwnedMonitors()
            if !isSimulator { FocusPolicy.clearShield() }
            hasReadableConfiguration = false
            errorMessage = "Requested app restrictions to stop, but the saved policy couldn’t be updated. Please retry or disable this app’s Screen Time access in Settings. \(error.localizedDescription)"
        }
    }
}
#endif
