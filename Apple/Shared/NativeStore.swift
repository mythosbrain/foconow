import Foundation
import UserNotifications

/// The app's canonical copy lives outside WebKit's cache and survives web-data cleanup.
final class NativeStore {
    let directory: URL
    let stateURL: URL
    private(set) var state: [String: Any]?
    private(set) var loadError: String?
    private(set) var recoveryWarning: String?

    #if os(macOS)
    static let didSave = Notification.Name("HabitCounterStateSaved")
    var recoveryDirectory: URL { directory.appendingPathComponent("Recovery", isDirectory: true) }

    func recoveryCopies() throws -> [[String: Any]] {
        guard FileManager.default.fileExists(atPath: recoveryDirectory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: recoveryDirectory, includingPropertiesForKeys: [.fileSizeKey])
            .filter { $0.lastPathComponent.range(of: #"^recovery-\d{4}-\d{2}-\d{2}\.json$"#, options: .regularExpression) != nil }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .map { ["name": $0.lastPathComponent, "date": String($0.lastPathComponent.dropFirst(9).prefix(10))] }
    }

    func recoveryCopy(named name: String) throws -> [String: Any] {
        guard try recoveryCopies().contains(where: { $0["name"] as? String == name }) else { throw CocoaError(.fileReadNoSuchFile) }
        let url = recoveryDirectory.appendingPathComponent(name)
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 10 * 1024 * 1024,
              let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else { throw CocoaError(.fileReadCorruptFile) }
        return object
    }

    private func preserveDailyRecovery(before data: Data) throws {
        guard FileManager.default.fileExists(atPath: stateURL.path), try Data(contentsOf: stateURL) != data else { return }
        try FileManager.default.createDirectory(at: recoveryDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        let destination = recoveryDirectory.appendingPathComponent("recovery-\(formatter.string(from: Date())).json")
        if !FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.copyItem(at: stateURL, to: destination)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        }
        for copy in try recoveryCopies().dropFirst(14) {
            if let name = copy["name"] as? String { try FileManager.default.removeItem(at: recoveryDirectory.appendingPathComponent(name)) }
        }
    }
    #endif

    init(directory overrideDirectory: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        #if os(macOS)
        directory = overrideDirectory ?? DesktopLaunchCheck.directory?.appendingPathComponent("isolated-data", isDirectory: true) ?? support.appendingPathComponent("com.yassine.habitcounter", isDirectory: true)
        #else
        directory = overrideDirectory ?? support.appendingPathComponent("com.yassine.habitcounter", isDirectory: true)
        #endif
        stateURL = directory.appendingPathComponent("state.json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            if FileManager.default.fileExists(atPath: stateURL.path) {
                let size = try stateURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 10 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
                let data = try Data(contentsOf: stateURL)
                guard data.count <= 10 * 1024 * 1024,
                      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      (object["version"] as? Int) == 1,
                      let habits = object["habits"] as? [[String: Any]], !habits.isEmpty else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                state = object
            }
        } catch {
            loadError = "Your saved data couldn’t be loaded. It has been left untouched. Restore a backup in Settings to continue saving."
        }
    }

    func save(_ object: [String: Any], replacingUnreadable: Bool = false) throws {
        if loadError != nil && !replacingUnreadable { throw CocoaError(.fileReadCorruptFile) }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard data.count <= 10 * 1024 * 1024, (object["version"] as? Int) == 1,
              let habits = object["habits"] as? [[String: Any]], !habits.isEmpty else {
            throw CocoaError(.fileWriteUnknown)
        }
        // Keep the prior data for recovery whenever the user confirms a restore.
        if replacingUnreadable && FileManager.default.fileExists(atPath: stateURL.path) {
            let preserved = directory.appendingPathComponent("before-restore-\(UUID().uuidString).json")
            try FileManager.default.copyItem(at: stateURL, to: preserved)
        }
        #if os(macOS)
        // Recovery is best-effort: a full recovery folder must not prevent saving today's work.
        do { try preserveDailyRecovery(before: data); recoveryWarning = nil }
        catch { recoveryWarning = "Your progress is saved, but the recovery copy couldn’t be updated. Export a backup in Settings." }
        #endif
        try data.write(to: stateURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateURL.path)
        state = object
        loadError = nil
        #if os(macOS)
        NotificationCenter.default.post(name: Self.didSave, object: nil, userInfo: ["state": object])
        #endif
    }

    var appearance: String {
        #if os(macOS)
        let value = UserDefaults.standard.string(forKey: "habit-counter.desktop-appearance") ?? "dark"
        #else
        let value = UserDefaults.standard.string(forKey: "habit-counter.appearance") ?? "system"
        #endif
        return ["light", "dark", "system"].contains(value) ? value : "system"
    }
    func setAppearance(_ value: String) {
        guard ["light", "dark", "system"].contains(value) else { return }
        #if os(macOS)
        UserDefaults.standard.set(value, forKey: "habit-counter.desktop-appearance")
        #else
        UserDefaults.standard.set(value, forKey: "habit-counter.appearance")
        #endif
    }

    var bootstrap: [String: Any] {
        #if os(iOS)
        let platform = "iOS"
        #else
        let platform = "macOS"
        #endif
        var result: [String: Any] = ["platform": platform, "syncEnabled": false, "appearance": appearance, "reminder": DailyReminder.configuration]
        #if os(macOS)
        result["showPermissionSetup"] = MacPermissionSetup.shouldShow
        result["permissionSetupStep"] = MacPermissionSetup.step
        result["desktop"] = DesktopPreferences.shared.configuration
        result["plannerReminders"] = DesktopPlannerReminders.configuration
        result["pomodoro"] = PomodoroEngine.shared.snapshot
        #endif
        if let state { result["state"] = state }
        if let loadError { result["loadError"] = loadError }
        return result
    }
}

/// Reminders stay on this device; habit names never appear in notifications.
enum DailyReminder {
    private static let identifier = "habit-counter.daily-checkin"
    static var configuration: [String: Any] {
        ["enabled": UserDefaults.standard.bool(forKey: "habit-counter.reminder.enabled"),
         "time": UserDefaults.standard.string(forKey: "habit-counter.reminder.time") ?? "20:00"]
    }
    static func configure(enabled: Bool, time: String, completion: @escaping ([String: Any]) -> Void) {
        let pieces = time.split(separator: ":")
        guard pieces.count == 2, let hour = Int(pieces[0]), let minute = Int(pieces[1]), (0...23).contains(hour), (0...59).contains(minute) else {
            completion(["type": "reminder", "success": false, "message": "Choose a valid reminder time."]); return
        }
        let center = UNUserNotificationCenter.current()
        func finish(_ success: Bool, _ message: String = "") {
            DispatchQueue.main.async {
                if success {
                    UserDefaults.standard.set(enabled, forKey: "habit-counter.reminder.enabled")
                    UserDefaults.standard.set(time, forKey: "habit-counter.reminder.time")
                }
                completion(["type": "reminder", "success": success, "reminder": configuration, "message": message])
            }
        }
        if !enabled {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            center.removeDeliveredNotifications(withIdentifiers: [identifier])
            finish(true); return
        }
        center.requestAuthorization(options: [.alert]) { granted, error in
            guard granted, error == nil else {
                finish(false, "Notifications are off. Allow notifications for this app in your device’s Settings, then try again."); return
            }
            let content = UNMutableNotificationContent()
            content.title = "A moment for you"
            content.body = "Take a breath and check in with yourself."
            let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: hour, minute: minute), repeats: true)
            center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)) { error in
                finish(error == nil, error == nil ? "" : "Couldn’t schedule your reminder. Please try again.")
            }
        }
    }
}
