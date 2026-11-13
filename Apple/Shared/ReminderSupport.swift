#if os(macOS)
import Foundation
import AppKit
import UserNotifications

struct NudgeSettings: Codable {
    var tasks = false
    var focus = false
    var sounds = true
    var interval = 90
    var startHour = 9
    var endHour = 21
    var valid: Bool { [60, 90, 120, 180].contains(interval) && (0...23).contains(startHour) && (0...23).contains(endHour) && startHour != endHour }
    func permits(hour: Int) -> Bool {
        startHour < endHour ? (startHour..<endHour).contains(hour) : hour >= startHour || hour < endHour
    }
}

/// Pure decision rules shared by the running reminder service and its clock tests.
enum NudgePolicy {
    static func kind(settings: NudgeSettings, hour: Int, elapsed: TimeInterval, snoozed: Bool,
                     timerStatus: String, phase: String, remaining: Int, focusElapsed: TimeInterval,
                     unfinished: Int, present: Bool) -> String? {
        guard settings.valid, settings.permits(hour: hour), !snoozed, present else { return nil }
        if timerStatus == "running" {
            return settings.focus && phase == "work" && focusElapsed >= 30 * 60 && remaining > 120 && elapsed >= 30 * 60 ? "focus" : nil
        }
        // Paused sessions are intentional: don't nudge the user to do another task.
        guard timerStatus != "paused", settings.tasks, unfinished > 0, elapsed >= Double(settings.interval * 60) else { return nil }
        return "tasks"
    }
}

final class GentleReminders {
    static let shared = GentleReminders()
    static let category = "foconow.gentle-reminder"
    static let snoozeAction = "foconow.snooze-hour"
    private static let key = "foconow.nudges.v1"
    private static let requestID = "foconow.gentle-reminder.current"
    private let defaults = UserDefaults.standard
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var present = true
    private var delivering = false
    private var lastTimerStatus = "ready"
    private var lastPrompt = Date()
    private var focusDeadline: Double?
    private var lastFocusDeadline: Double?
    private var focusBegan = Date()
    private var settings = NudgeSettings()
    private init() {
        guard DesktopLaunchCheck.directory == nil else { return }
        if let data = defaults.data(forKey: Self.key), let value = try? JSONDecoder().decode(NudgeSettings.self, from: data), value.valid { settings = value }
    }
    var configuration: [String: Any] {
        var result = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(settings))) as? [String: Any] ?? [:]
        result["snoozedUntil"] = defaults.double(forKey: "foconow.nudges.snoozedUntil") * 1000
        return result
    }
    func start() {
        guard timer == nil, DesktopLaunchCheck.directory == nil else { return }
        let center = UNUserNotificationCenter.current()
        center.setNotificationCategories([UNNotificationCategory(identifier: Self.category, actions: [
            UNNotificationAction(identifier: "foconow.open-tasks", title: "Open Tasks & Focus", options: .foreground),
            UNNotificationAction(identifier: Self.snoozeAction, title: "Snooze for 1 hour", options: [])
        ], intentIdentifiers: [], options: [])])
        observers.append(NotificationCenter.default.addObserver(forName: PomodoroEngine.didUpdate, object: nil, queue: .main) { [weak self] event in
            guard let self, event.userInfo?["clockOnly"] as? Bool != true else { return }
            let status = PomodoroEngine.shared.record.status
            if self.lastTimerStatus != status { self.lastPrompt = Date(); self.lastTimerStatus = status; self.clearStaleReminder() }
        })
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.tick() }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.present = false })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.present = true; self?.lastPrompt = Date(); self?.focusBegan = Date()
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NativeStore.didSave, object: nil, queue: .main) { [weak self] _ in self?.clearStaleReminder() })
    }
    private func clearStaleReminder() {
        guard DesktopLaunchCheck.directory == nil else { return }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Self.requestID])
    }
    func reloadPreferences() {
        settings = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(NudgeSettings.self, from: $0) } ?? NudgeSettings()
        lastPrompt = Date(); clearStaleReminder()
    }
    func snooze() {
        defaults.set(Date().addingTimeInterval(3600).timeIntervalSince1970, forKey: "foconow.nudges.snoozedUntil")
        clearStaleReminder()
    }
    func configure(_ body: [String: Any], completion: @escaping ([String: Any]) -> Void) {
        guard let data = try? JSONSerialization.data(withJSONObject: body), let value = try? JSONDecoder().decode(NudgeSettings.self, from: data), value.valid else {
            completion(["type": "nudges", "success": false, "configuration": configuration, "message": "Choose different start and end hours and a valid reminder interval."]); return
        }
        Task { @MainActor in
            do {
                if value.tasks || value.focus {
                    guard DesktopLaunchCheck.directory == nil else { throw CocoaError(.userCancelled) }
                    guard try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) else { throw CocoaError(.userCancelled) }
                }
                self.settings = value
                if DesktopLaunchCheck.directory == nil { self.defaults.set(try JSONEncoder().encode(value), forKey: Self.key) }
                self.lastPrompt = Date(); self.clearStaleReminder()
                completion(["type": "nudges", "success": true, "configuration": self.configuration, "message": "Your reminder preferences are saved."])
            } catch {
                completion(["type": "nudges", "success": false, "configuration": self.configuration, "message": "Allow FocoNow notifications in System Settings, then save again."])
            }
        }
    }
    func test(completion: @escaping (String?) -> Void) {
        guard DesktopLaunchCheck.directory == nil else { completion("Test alerts are disabled in diagnostic mode."); return }
        Task { @MainActor in
            do {
                let center = UNUserNotificationCenter.current()
                guard try await center.requestAuthorization(options: [.alert, .sound]) else { throw CocoaError(.userCancelled) }
                let content = UNMutableNotificationContent()
                content.title = "FocoNow is here for you"
                content.body = "Your test alert is working. One small step at a time."
                content.sound = self.settings.sounds ? .default : nil
                content.userInfo = ["habitAction": "tasks"]
                try await center.add(UNNotificationRequest(identifier: "foconow.test-alert", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)))
                completion(nil)
            } catch { completion("Couldn’t send the test alert. Check FocoNow in macOS Notification Settings.") }
        }
    }
    private func tick() {
        guard !delivering else { return }
        let now = Date(), engine = PomodoroEngine.shared
        if engine.record.endsAt != focusDeadline {
            focusDeadline = engine.record.endsAt; focusBegan = now
        }
        let tasks = DesktopCounter.shared.plan(at: now)["tasks"] as? [[String: Any]] ?? []
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null)
        guard let kind = NudgePolicy.kind(settings: settings, hour: Calendar.current.component(.hour, from: now),
            elapsed: now.timeIntervalSince(lastPrompt), snoozed: now.timeIntervalSince1970 < defaults.double(forKey: "foconow.nudges.snoozedUntil"),
            timerStatus: engine.record.status, phase: engine.record.phase, remaining: engine.remaining,
            focusElapsed: now.timeIntervalSince(focusBegan), unfinished: tasks.filter { $0["done"] as? Bool != true }.count,
            present: present && idle < 300) else { return }
        if kind == "focus", lastFocusDeadline == focusDeadline { return }
        delivering = true
        let content = UNMutableNotificationContent()
        content.title = kind == "focus" ? "Still with your focus?" : "One small step is enough"
        content.body = kind == "focus" ? "Keep going if it feels right, or pause your timer for a breather." : "You have unfinished tasks today. Pick one when you’re ready."
        content.sound = settings.sounds ? .default : nil
        content.categoryIdentifier = Self.category
        content.userInfo = ["habitAction": "tasks"]
        let deadline = focusDeadline
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: Self.requestID, content: content, trigger: nil)) { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.delivering = false
                // Back off even on denial/failure; never hammer the notification service.
                self.lastPrompt = now
                if error == nil && kind == "focus" { self.lastFocusDeadline = deadline }
            }
        }
    }
}
#endif

#if os(macOS)
/// Deadline alerts are deduplicated across carried copies of the same task.
final class TaskDeadlineAlerts {
    static let shared = TaskDeadlineAlerts()
    private var observer: NSObjectProtocol?
    private var timer: Timer?
    private var generation = 0
    static func candidates(_ state: [String: Any], now: Date = Date()) -> [(id: String, date: String, due: Date)] {
        let planner = state["planner"] as? [String: [String: Any]] ?? [:]
        var seen = Set<String>(), result: [(id: String, date: String, due: Date)] = []
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"; formatter.isLenient = false
        for day in planner.keys.sorted(by: >) {
            for task in planner[day]?["tasks"] as? [[String: Any]] ?? [] {
                guard let id = task["originId"] as? String, !seen.contains(id) else { continue }
                seen.insert(id)
                guard task["done"] as? Bool != true, task["remindAtDeadline"] as? Bool == true,
                      let date = task["dueDate"] as? String, let time = task["dueTime"] as? String,
                      let due = formatter.date(from: "\(date) \(time)"), due > now.addingTimeInterval(-120) else { continue }
                result.append((id: "foconow.deadline." + id, date: day, due: due))
            }
        }
        return result.sorted { $0.due < $1.due }
    }
    func start() {
        guard observer == nil, DesktopLaunchCheck.directory == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: NativeStore.didSave, object: nil, queue: .main) { [weak self] event in
            if let state = event.userInfo?["state"] as? [String: Any] { self?.refresh(state) }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            if let state = DesktopCounter.shared.state { self?.refresh(state) }
        }
        if let state = DesktopCounter.shared.state { refresh(state) }
    }
    func authorize(completion: @escaping (Bool) -> Void) {
        guard DesktopLaunchCheck.directory == nil else { completion(false); return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { allowed, _ in
            DispatchQueue.main.async { if let state = DesktopCounter.shared.state { self.refresh(state) }; completion(allowed) }
        }
    }
    func refresh(_ state: [String: Any]) {
        guard DesktopLaunchCheck.directory == nil else { return }
        generation += 1; let current = generation, now = Date()
        let values = Array(Self.candidates(state, now: now).prefix(32)), ids = Set(values.map(\.id))
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            DispatchQueue.main.async {
                guard current == self.generation else { return }
                let obsolete = requests.filter { $0.identifier.hasPrefix("foconow.deadline.") && !ids.contains($0.identifier) }.map(\.identifier)
                center.removePendingNotificationRequests(withIdentifiers: obsolete)
                for value in values where value.due > Date() {
                    let content = UNMutableNotificationContent()
                    content.title = "A task deadline is here"
                    content.body = "Open Tasks & Focus to finish it or give yourself a new deadline."
                    content.sound = GentleReminders.shared.configuration["sounds"] as? Bool != false ? .default : nil
                    content.userInfo = ["habitAction": "taskDay:" + value.date]
                    let parts = Calendar.current.dateComponents([.year,.month,.day,.hour,.minute], from: value.due)
                    center.add(UNNotificationRequest(identifier: value.id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
                }
            }
        }
    }
}
#endif
