#if os(iOS)
import Foundation
import FamilyControls
import ManagedSettings
import DeviceActivity
import Darwin

/// All tokens and policy state remain in the signed app/extension's shared container.
enum FocusMode: String, Codable { case off, block, dailyLimit }

struct FocusConfiguration: Codable, Equatable {
    var version = 1
    var selection = FamilyActivitySelection(includeEntireCategory: true)
    var mode: FocusMode = .off
    var dailyMinutes = 30
    var generation = UUID().uuidString.lowercased()
    var reachedDay: String?

    var selectedCount: Int {
        selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count
    }
    var activityName: DeviceActivityName { DeviceActivityName(FocusPolicy.activityPrefix + generation) }
    var eventName: DeviceActivityEvent.Name { DeviceActivityEvent.Name("limit." + generation) }
}

enum FocusStateError: LocalizedError {
    case missingContainer, unreadableState, invalidSelection, invalidBudget, cannotLock
    var errorDescription: String? {
        switch self {
        case .missingContainer:
            return "This build cannot access its Screen Time shared container. Sign the app and monitoring extension with matching Family Controls and App Group profiles."
        case .unreadableState:
            return "Your saved app-limit settings could not be read. They have been left untouched."
        case .invalidSelection:
            return "Choose at least one app, category, or website first."
        case .invalidBudget:
            return "Choose a daily allowance between 1 and 1,440 minutes."
        case .cannotLock:
            return "Your app-limit settings are busy or unavailable. Please try again."
        }
    }
}

enum FocusPolicy {
    static let appGroup = "group.com.yassine.habitcounter"
    static let activityPrefix = "habit-focus.daily."
    static let storeName = ManagedSettingsStore.Name("habit-focus")

    static func dayKey(_ date: Date = Date()) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let c = calendar.dateComponents(in: .current, from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func authorized(_ status: AuthorizationStatus) -> Bool {
        if status == .approved { return true }
        if #available(iOS 26.4, *), status == .approvedWithDataAccess { return true }
        return false
    }

    static func applyShield(_ selection: FamilyActivitySelection) {
        let store = ManagedSettingsStore(named: storeName)
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        store.shield.webDomainCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
    }

    static func clearShield() { ManagedSettingsStore(named: storeName).clearAllSettings() }

    static func stopOwnedMonitors() {
        let center = DeviceActivityCenter()
        let names = center.activities.filter { $0.rawValue.hasPrefix(activityPrefix) }
        if !names.isEmpty { center.stopMonitoring(names) }
    }

    @available(iOS 17.4, *)
    static func startMonitor(_ config: FocusConfiguration) throws {
        guard config.selectedCount > 0 else { throw FocusStateError.invalidSelection }
        guard (1...1440).contains(config.dailyMinutes) else { throw FocusStateError.invalidBudget }
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0, second: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59, second: 59),
            repeats: true
        )
        let event = DeviceActivityEvent(
            applications: config.selection.applicationTokens,
            categories: config.selection.categoryTokens,
            webDomains: config.selection.webDomainTokens,
            threshold: DateComponents(minute: config.dailyMinutes),
            includesPastActivity: true
        )
        try DeviceActivityCenter().startMonitoring(config.activityName, during: schedule, events: [config.eventName: event])
    }
}

/// The advisory file lock serializes policy checks AND shield writes across the host and extension.
/// A late callback cannot interleave a shield write after a newer explicit Stop operation.
enum FocusStateStorage {
    static func container() throws -> URL {
        guard let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: FocusPolicy.appGroup) else {
            throw FocusStateError.missingContainer
        }
        let directory = root.appendingPathComponent("FocusPolicy", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return directory
    }

    struct LockedState {
        let file: URL
        func read() throws -> FocusConfiguration {
            guard FileManager.default.fileExists(atPath: file.path) else { return FocusConfiguration() }
            let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 2 * 1024 * 1024 else { throw FocusStateError.unreadableState }
            do {
                let value = try JSONDecoder().decode(FocusConfiguration.self, from: Data(contentsOf: file))
                guard value.version == 1, UUID(uuidString: value.generation) != nil,
                      (1...1440).contains(value.dailyMinutes), value.selectedCount <= 2000,
                      value.reachedDay == nil || value.reachedDay!.count == 10 else { throw FocusStateError.unreadableState }
                return value
            } catch { throw FocusStateError.unreadableState }
        }
        func write(_ config: FocusConfiguration) throws {
            let data = try JSONEncoder().encode(config)
            guard data.count <= 2 * 1024 * 1024 else { throw FocusStateError.unreadableState }
            try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
    }

    static func withLock<T>(_ operation: (LockedState) throws -> T) throws -> T {
        let directory = try container()
        let lockPath = directory.appendingPathComponent("policy.lock").path
        let fd = Darwin.open(lockPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw FocusStateError.cannotLock }
        defer { Darwin.close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw FocusStateError.cannotLock }
        defer { flock(fd, LOCK_UN) }
        return try operation(LockedState(file: directory.appendingPathComponent("policy.json")))
    }
}
#endif
