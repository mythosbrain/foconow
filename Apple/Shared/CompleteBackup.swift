#if os(macOS)
import Foundation
import CoreFoundation

/// Portable app-owned records only. macOS permissions and login registration stay on this Mac.
enum CompleteBackup {
    static let format = "foconow.complete-backup"
    private static var inProgress = false
    static let limit = 50 * 1024 * 1024
    static let files = ["state.json", "pomodoro.json", "iphone-settings-reports.json", "iphone-screen-time-latest.json"]
    static let boolKeys = ["habit-counter.menu-bar.show-days", "habit-counter.desktop-widget.visible", "habit-counter.desktop-widget.pinned", "habit-counter.desktop-widget.dock", "habit-counter.planner-reminders.enabled", "foconow.planner-reminders.sounds", "habit-counter.reminder.enabled", "habit-counter.phone-settings-auto"]
    static let textKeys = ["habit-counter.desktop-appearance", "habit-counter.planner-reminders.morning", "habit-counter.planner-reminders.evening", "habit-counter.reminder.time", "habit-counter.phone-settings-device"]
    static let nudgeKey = "foconow.nudges.v1"
    static var keys: [String] { boolKeys + textKeys + [nudgeKey] }
    static func failure(_ text: String) -> NSError { NSError(domain: "FocoNow.Backup", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
    static func json(_ object: Any) throws -> Data { try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) }
    static func read(_ url: URL, max: Int = limit) throws -> Any {
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= max else { throw failure("This backup is too large.") }
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    }
    static func preferences(_ defaults: UserDefaults) -> [String: Any] {
        var result: [String: Any] = [:]
        for key in boolKeys + textKeys { if let value = defaults.object(forKey: key) { result[key] = value } }
        if let data = defaults.data(forKey: nudgeKey), let value = try? JSONSerialization.jsonObject(with: data) { result[nudgeKey] = value }
        return result
    }
    static func make(state: [String: Any], timer: PomodoroRecord, directory: URL, defaults: UserDefaults) throws -> [String: Any] {
        var reports: [String: Any] = [:]
        for name in files.dropFirst(2) {
            let url = directory.appendingPathComponent(name)
            reports[name] = FileManager.default.fileExists(atPath: url.path) ? try read(url) : NSNull()
        }
        let value: [String: Any] = ["format": format, "version": 1, "exportedAt": Date().timeIntervalSince1970 * 1000,
            "state": state, "pomodoro": try JSONSerialization.jsonObject(with: JSONEncoder().encode(timer)),
            "preferences": preferences(defaults), "screenTime": reports]
        try validate(value)
        guard try json(value).count <= limit else { throw failure("The complete backup exceeds 50 MB.") }
        return value
    }
    static func validate(_ value: [String: Any]) throws {
        guard value["format"] as? String == format, value["version"] as? Int == 1,
              let state = value["state"] as? [String: Any], state["version"] as? Int == 1,
              let habits = state["habits"] as? [[String: Any]], !habits.isEmpty,
              let rawTimer = value["pomodoro"], let prefs = value["preferences"] as? [String: Any],
              let reports = value["screenTime"] as? [String: Any], Set(reports.keys) == Set(files.dropFirst(2)),
              Set(prefs.keys).isSubset(of: Set(keys)) else { throw failure("This complete backup is incomplete or uses an unsupported format.") }
        let timer = try JSONDecoder().decode(PomodoroRecord.self, from: json(rawTimer))
        guard PomodoroEngine.valid(timer), timer.status != "running", timer.focusStartedAt == nil else { throw failure("The backup contains an invalid focus timer.") }
        for (key, object) in prefs {
            if boolKeys.contains(key) {
                guard let number = object as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { throw failure("Invalid preference in backup.") }
            } else if textKeys.contains(key) {
                guard let text = object as? String, text.count <= 240 else { throw failure("Invalid preference in backup.") }
                if key == "habit-counter.desktop-appearance", !["light", "dark", "system"].contains(text) { throw failure("Invalid appearance in backup.") }
                if key.hasSuffix(".morning") || key.hasSuffix(".evening") || key.hasSuffix(".time") {
                    guard text.range(of: #"^([01]\d|2[0-3]):[0-5]\d$"#, options: .regularExpression) != nil else { throw failure("Invalid reminder time in backup.") }
                }
            } else {
                let config = try JSONDecoder().decode(NudgeSettings.self, from: json(object))
                guard config.valid else { throw failure("Invalid reminder preferences in backup.") }
            }
        }
        if let object = reports["iphone-settings-reports.json"], !(object is NSNull) {
            let reports = try JSONDecoder().decode([SettingsUsageReport].self, from: json(object))
            guard reports.count <= 10000, reports.allSatisfy({ $0.deviceName.count <= 240 && $0.date.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil && $0.totalSeconds.isFinite && $0.totalSeconds >= 0 && $0.totalSeconds <= 86400 && $0.capturedAt.isFinite && $0.apps.count <= 10000 && $0.apps.allSatisfy { $0.name.count <= 1000 && $0.seconds.isFinite && $0.seconds >= 0 } }) else { throw failure("Invalid Screen Time history in backup.") }
        }
        if let object = reports["iphone-screen-time-latest.json"], !(object is NSNull), !(object is [String: Any]) { throw failure("Invalid Screen Time snapshot in backup.") }
        guard try json(value).count <= limit, try json(reports).count <= 14*1024*1024, try json(state).count <= 10*1024*1024, try json(rawTimer).count <= 25*1024*1024 else { throw failure("A record in the backup is too large.") }
    }
    private static func applyPreferences(_ prefs: [String: Any], defaults: UserDefaults) throws {
        for key in keys {
            if let value = prefs[key] {
                defaults.set(key == nudgeKey ? try json(value) : value, forKey: key)
            } else { defaults.removeObject(forKey: key) }
        }
        defaults.synchronize()
    }
    static func recoverIfNeeded(directory: URL, defaults: UserDefaults) throws {
        guard !inProgress else { return }
        let journalURL = directory.appendingPathComponent("restore-journal.json")
        guard FileManager.default.fileExists(atPath: journalURL.path) else { return }
        guard let journal = try read(journalURL, max: 100*1024*1024) as? [String: Any],
              let previous = journal["files"] as? [String: Any], Set(previous.keys) == Set(files),
              let prefs = journal["preferences"] as? [String: Any], Set(prefs.keys).isSubset(of: Set(keys)) else { throw failure("The interrupted restore needs recovery. Your files have been left untouched.") }
        // Decode every preimage before changing any file, including malformed journals.
        var decoded: [String: Data] = [:]
        for name in files {
            if let encoded = previous[name] as? String, let data = Data(base64Encoded: encoded) { decoded[name] = data }
            else if !(previous[name] is NSNull) { throw failure("Invalid restore recovery file.") }
        }
        for name in files {
            let url = directory.appendingPathComponent(name)
            if let data = decoded[name] { try write(data, to: url) }
            else if previous[name] is NSNull { if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) } }
            else { throw failure("Invalid restore recovery file.") }
        }
        try applyPreferences(prefs, defaults: defaults)
        try FileManager.default.removeItem(at: journalURL)
    }
    static func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    /// Journal first; any failed/interrupted restore rolls back on this call or next launch.
    static func restore(_ value: [String: Any], validatedState: [String: Any], directory: URL, defaults: UserDefaults,
                        afterWrite: ((Int) throws -> Void)? = nil) throws {
        var value = value; value["state"] = validatedState
        try validate(value)
        try recoverIfNeeded(directory: directory, defaults: defaults)
        inProgress = true
        defer { inProgress = false }
        var previous: [String: Any] = [:]
        for name in files {
            let url = directory.appendingPathComponent(name)
            previous[name] = FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url).base64EncodedString() : NSNull()
        }
        let journal: [String: Any] = ["files": previous, "preferences": preferences(defaults)]
        let journalURL = directory.appendingPathComponent("restore-journal.json")
        let safety = directory.appendingPathComponent("RestoreSafety", isDirectory: true)
        try FileManager.default.createDirectory(at: safety, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try write(try json(journal), to: safety.appendingPathComponent("before-restore-\(UUID().uuidString).json"))
        try write(try json(journal), to: journalURL)
        do {
            let reports = value["screenTime"] as! [String: Any]
            for (index, name) in files.enumerated() {
                let object: Any = name == "state.json" ? validatedState : name == "pomodoro.json" ? value["pomodoro"]! : reports[name] ?? NSNull()
                let url = directory.appendingPathComponent(name)
                if object is NSNull { if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) } }
                else { try write(try json(object), to: url) }
                try afterWrite?(index)
            }
            try applyPreferences(value["preferences"] as! [String: Any], defaults: defaults)
            try FileManager.default.removeItem(at: journalURL)
        } catch {
            inProgress = false
            try recoverIfNeeded(directory: directory, defaults: defaults)
            throw error
        }
    }
}
#endif
