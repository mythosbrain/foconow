#if os(macOS)
import Foundation
import AppKit
import UserNotifications

struct PomodoroSettings: Codable {
    var work = 25
    var short = 5
    var long = 15
    var every = 4
    var notifications = false
    var sounds: Bool? = nil // Missing in older saves means alarms are on.
}
struct PomodoroSession: Codable {
    var id: String
    var endedAt: Double
    var seconds: Int
    var taskId: String
    var taskDate: String
    var taskTitle: String
    var tracked: Bool? = nil
}
struct FocusSpan: Codable {
    var start: Double
    var end: Double
    var taskId: String
    var taskTitle: String
}
struct PomodoroRecord: Codable {
    var version = 1
    var settings = PomodoroSettings()
    var phase = "work"
    var status = "ready"
    var duration = 1500
    var remaining = 1500
    var endsAt: Double? = nil
    var taskId = ""
    var taskDate = ""
    var taskTitle = ""
    var cycle = 0
    var sessions: [PomodoroSession] = []
    var focusSpans: [FocusSpan]? = nil
    var focusStartedAt: Double? = nil
}

/// This clock lives in the Mac process, independently of the page or window.
final class PomodoroEngine: ObservableObject {
    static let shared = PomodoroEngine()
    static let didUpdate = Notification.Name("HabitCounterPomodoroUpdated")
    static let notificationId = "habit-counter.pomodoro.finished"
    @Published private(set) var record = PomodoroRecord()
    @Published private(set) var now = Date()
    @Published private(set) var storageError: String?
    private let url: URL
    private let clock: () -> Date
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var unreadable = false
    private let alarm: (String) -> Void
    private var alarmSound: NSSound?

    init(directory: URL? = nil, clock: @escaping () -> Date = Date.init, ticking: Bool = true, alarm: ((String) -> Void)? = nil) {
        self.clock = clock
        self.alarm = alarm ?? { _ in }
        url = (directory ?? NativeStore().directory).appendingPathComponent("pomodoro.json")
        now = clock()
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 25 * 1024 * 1024 else { throw CocoaError(.fileReadCorruptFile) }
                let value = try JSONDecoder().decode(PomodoroRecord.self, from: Data(contentsOf: url))
                guard Self.valid(value) else { throw CocoaError(.fileReadCorruptFile) }
                record = value
            }
        } catch {
            unreadable = true
            storageError = "The saved timer couldn’t be read. Your timer file has been left untouched."
        }
        if ticking {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.tick() })
            observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.tick() })
            // Observers may read .shared; settle an expired restored timer after singleton construction.
            DispatchQueue.main.async { [weak self] in self?.tick() }
        }
    }
    deinit {
        timer?.invalidate()
        observers.forEach { NotificationCenter.default.removeObserver($0); NSWorkspace.shared.notificationCenter.removeObserver($0) }
    }
    static func valid(_ r: PomodoroRecord) -> Bool {
        guard r.version == 1, (1...180).contains(r.settings.work), (1...60).contains(r.settings.short), (1...120).contains(r.settings.long), (2...8).contains(r.settings.every),
              ["work", "short", "long"].contains(r.phase), ["ready", "running", "paused", "completed"].contains(r.status), (1...10800).contains(r.duration), (0...r.duration).contains(r.remaining), r.cycle >= 0, r.cycle < 1000000,
              r.taskId.count <= 100, r.taskDate.count <= 10, r.taskTitle.count <= 240, r.sessions.count <= 10000 else { return false }
        if r.status == "running" { guard let end = r.endsAt, end.isFinite, end > 0, end < 4102444800000 else { return false } }
        else if r.endsAt != nil { return false }
        if r.status == "completed" && r.remaining != 0 { return false }
        if r.status == "ready" && r.remaining != r.duration { return false }
        if ["paused", "running"].contains(r.status) && r.remaining == 0 { return false }
        if let start = r.focusStartedAt {
            guard r.status == "running", r.phase == "work", start.isFinite, start > 0, let end = r.endsAt, start <= end, end - start <= 10800000 else { return false }
        }
        guard (r.focusSpans?.count ?? 0) <= 50000, (r.focusSpans ?? []).allSatisfy({ $0.start.isFinite && $0.end.isFinite && $0.start > 0 && $0.end >= $0.start && $0.end < 4102444800000 && $0.end - $0.start <= 10800000 && $0.taskId.count <= 100 && $0.taskTitle.count <= 240 }) else { return false }
        return Set(r.sessions.map(\.id)).count == r.sessions.count && r.sessions.allSatisfy { !$0.id.isEmpty && $0.id.count <= 100 && $0.endedAt.isFinite && $0.endedAt > 0 && $0.endedAt < 4102444800000 && (60...10800).contains($0.seconds) && $0.taskId.count <= 100 && $0.taskDate.count <= 10 && $0.taskTitle.count <= 240 }
    }
    var remaining: Int {
        if record.status == "running", let end = record.endsAt { return min(record.duration, max(0, Int(ceil((end - clock().timeIntervalSince1970 * 1000) / 1000)))) }
        return record.remaining
    }
    var nextPhase: String { record.phase == "work" ? (record.cycle % record.settings.every == 0 ? "long" : "short") : "work" }
    var displayTime: String { String(format: "%02d:%02d", remaining / 60, remaining % 60) }
    var isActive: Bool { record.status == "running" || record.status == "paused" }
    var snapshot: [String: Any] {
        var value = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(record))) as? [String: Any] ?? [:]
        value["remaining"] = remaining
        value["nextPhase"] = nextPhase
        value["now"] = clock().timeIntervalSince1970 * 1000
        if record.phase == "work", record.status == "running", let end = record.endsAt {
            value["focusStartedAt"] = record.focusStartedAt ?? end - Double(record.remaining) * 1000
        }
        value["focusSpans"] = (record.focusSpans ?? []).map { ["start": $0.start, "end": $0.end, "taskId": $0.taskId, "taskTitle": $0.taskTitle] as [String: Any] }
        if let storageError { value["error"] = storageError }
        return value
    }
    private func duration(_ phase: String, _ settings: PomodoroSettings) -> Int { (phase == "work" ? settings.work : phase == "short" ? settings.short : settings.long) * 60 }
    private func commit(_ value: PomodoroRecord) throws {
        guard !unreadable, Self.valid(value) else { throw failure(storageError ?? "This timer setting isn’t valid.") }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(value).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            record = value; storageError = nil; now = clock(); broadcast()
        } catch { storageError = "Couldn’t save the timer on this Mac. Try again before closing the app."; broadcast(); throw error }
    }
    private func failure(_ message: String) -> NSError { NSError(domain: "HabitCounter.Pomodoro", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    private func broadcast(clockOnly: Bool = false) { NotificationCenter.default.post(name: Self.didUpdate, object: self, userInfo: ["clockOnly": clockOnly]) }
    private func settleFocus(_ value: inout PomodoroRecord, until end: Double) {
        guard value.phase == "work", value.status == "running", let deadline = value.endsAt else { value.focusStartedAt = nil; return }
        // An already-running older timer can recover its elapsed unpaused portion.
        let start = value.focusStartedAt ?? (deadline - Double(value.remaining) * 1000)
        let stop = max(start, min(end, deadline))
        if stop > start {
            var spans = value.focusSpans ?? []
            spans.append(FocusSpan(start: start, end: stop, taskId: value.taskId, taskTitle: value.taskTitle))
            value.focusSpans = Array(spans.suffix(50000))
        }
        value.focusStartedAt = nil
    }
    func tick() {
        guard !unreadable else { return }
        if record.status == "running", let end = record.endsAt, clock().timeIntervalSince1970 * 1000 >= end {
            var value = record
            settleFocus(&value, until: end)
            value.status = "completed"; value.remaining = 0; value.endsAt = nil
            if value.phase == "work" {
                value.cycle += 1
                value.sessions.append(PomodoroSession(id: UUID().uuidString, endedAt: end, seconds: value.duration, taskId: value.taskId, taskDate: value.taskDate, taskTitle: value.taskTitle, tracked: true))
                value.sessions = Array(value.sessions.suffix(10000))
            }
            do {
                try commit(value)
                if clock().timeIntervalSince1970 * 1000 - end < 120000 { playAlarm(value.phase) }
            } catch { }
        } else if record.status == "running" { now = clock(); broadcast(clockOnly: true) }
    }
    func start() throws {
        tick()
        if record.status == "running" { return }
        var value = record
        if value.status == "completed" { value.phase = nextPhase; value.duration = duration(value.phase, value.settings); value.remaining = value.duration }
        value.status = "running"
        value.endsAt = clock().timeIntervalSince1970 * 1000 + Double(value.remaining) * 1000
        value.focusStartedAt = value.phase == "work" ? clock().timeIntervalSince1970 * 1000 : nil
        try commit(value); scheduleAlert()
    }
    func pause() throws {
        tick()
        guard record.status == "running" else { return }
        var value = record; settleFocus(&value, until: clock().timeIntervalSince1970 * 1000)
        value.remaining = remaining; value.endsAt = nil; value.status = "paused"
        try commit(value); cancelAlert()
    }
    func reset() throws {
        tick()
        var value = record; value.phase = "work"; value.status = "ready"; value.endsAt = nil; value.duration = duration("work", value.settings); value.remaining = value.duration
        var tracked = record; settleFocus(&tracked, until: clock().timeIntervalSince1970 * 1000)
        value.focusSpans = tracked.focusSpans; value.focusStartedAt = nil
        try commit(value); cancelAlert()
    }
    func choosePhase(_ phase: String) throws {
        tick()
        guard !isActive, ["work", "short", "long"].contains(phase) else { throw failure("End the current session before changing its type.") }
        var value = record; value.phase = phase; value.status = "ready"; value.duration = duration(phase,value.settings); value.remaining = value.duration; value.endsAt = nil
        try commit(value); cancelAlert()
    }
    func selectTask(id: String, date: String, title: String) throws {
        tick()
        guard !isActive else { throw failure("End this session before focusing on another task.") }
        guard id.count <= 100, date.count <= 10, title.count <= 240 else { throw failure("Choose a valid task.") }
        var value = record; value.taskId = id; value.taskDate = date; value.taskTitle = title
        try commit(value)
    }
    func focusTask(id: String, date: String, title: String) throws {
        tick()
        if isActive && record.taskId == id && record.taskDate == date && record.phase == "work" {
            if record.status == "paused" { try start() }
            return
        }
        guard !isActive else { throw failure("End this session before starting another task.") }
        guard id.count <= 100, date.count <= 10, title.count <= 240 else { throw failure("Choose a valid task.") }
        var value = record
        value.taskId = id; value.taskDate = date; value.taskTitle = title; value.phase = "work"
        value.duration = duration("work",value.settings); value.remaining = value.duration; value.status = "running"
        value.endsAt = clock().timeIntervalSince1970 * 1000 + Double(value.duration) * 1000
        value.focusStartedAt = clock().timeIntervalSince1970 * 1000
        try commit(value); scheduleAlert()
    }
    func configure(work: Int, short: Int, long: Int, every: Int) throws {
        tick()
        guard !isActive else { throw failure("End the current session before changing durations.") }
        var value = record
        value.settings.work = work; value.settings.short = short; value.settings.long = long; value.settings.every = every
        guard Self.valid(value) else { throw failure("Choose work of 1–180 minutes, short breaks of 1–60, long breaks of 1–120, and a long break every 2–8 sessions.") }
        value.status = "ready"; value.duration = duration(value.phase,value.settings); value.remaining = value.duration; value.endsAt = nil
        try commit(value)
    }
    func setNotifications(_ enabled: Bool, completion: @escaping (String?) -> Void) {
        if !enabled {
            let wasEnabled = record.settings.notifications
            var value = record; value.settings.notifications = false
            do { try commit(value); cancelAlert(force: wasEnabled); completion(nil) } catch { completion(error.localizedDescription) }
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async {
                guard granted else { completion("Allow FocoNow notifications in System Settings, then try again."); return }
                var value = self.record; value.settings.notifications = true
                do { try self.commit(value); self.scheduleAlert(); completion(nil) } catch { completion(error.localizedDescription) }
            }
        }
    }
    func setSounds(_ enabled: Bool) throws {
        var value = record; value.settings.sounds = enabled
        try commit(value)
        if !enabled { alarmSound?.stop() }
        scheduleAlert()
    }
    func playAlarm(_ phase: String) {
        guard record.settings.sounds != false else { return }
        let kind = phase == "work" ? "FocusFinished" : "BreakFinished"
        alarm(kind)
        // Diagnostic and clock-only tests must stay silent.
        guard timer != nil, DesktopLaunchCheck.directory == nil else { return }
        alarmSound?.stop()
        if let path = Bundle.main.path(forResource: kind, ofType: "wav", inDirectory: "WebContent"), let sound = NSSound(contentsOfFile: path, byReference: false) {
            alarmSound = sound; sound.volume = 0.75; sound.play()
        }
    }
    private func cancelAlert(force: Bool = false) {
        guard record.settings.notifications || force else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notificationId])
    }
    private func scheduleAlert() {
        guard record.settings.notifications, record.status == "running" else { return }
        let content = UNMutableNotificationContent()
        content.title = record.phase == "work" ? "Time for a little break" : "Ready for your next focus session?"
        content.body = "Your timer has finished. Open Tasks & Focus when you’re ready."
        // The native alarm plays independently of notification permission.
        content.sound = nil
        content.userInfo = ["habitAction": "tasks"]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: Self.notificationId, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: Double(max(1, remaining)), repeats: false)))
    }
}
#endif
