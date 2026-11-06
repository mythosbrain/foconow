import Foundation

@main
struct WidgetChecks {
    static func main() throws {
        let now = Calendar.current.startOfDay(for: Date()).addingTimeInterval(12 * 3600)
        let ms = now.timeIntervalSince1970 * 1000, key = WidgetSummary.dayKey(now)
        let state: [String: Any] = ["activeId": "habit", "habits": [["id": "habit", "name": "Less scrolling", "startedAt": ms - 12 * 86400000, "entries": [["note": "PRIVATE JOURNAL"]]]], "planner": [key: ["focus": "Finish something important", "summary": "PRIVATE SUMMARY", "tasks": [["id": "a", "title": "Ordinary task", "notes": "PRIVATE TASK NOTE", "done": false], ["id": "b", "title": "Priority task", "priority": true, "done": false], ["id": "c", "title": "Completed task", "done": true]]]]]
        let timer: [String: Any] = ["phase": "work", "status": "running", "duration": 1500, "remaining": 1200, "endsAt": ms + 1200000, "focusStartedAt": ms - 300000, "focusSpans": [["start": ms - 3600000, "end": ms - 1800000]], "sessions": [["endedAt": ms - 1800000, "seconds": 1800.0, "tracked": true], ["endedAt": ms - 7200000, "seconds": 600.0]]]
        let value = WidgetSummary.make(state: state, timer: timer, now: now)
        precondition(value.valid && value.taskCount == 3 && value.completedTasks == 1)
        precondition(value.nextTasks.map(\.id) == ["b", "a"] && value.streak(at: now) == 12)
        precondition(value.focusSeconds == 2700, "Saved spans, legacy session, and active work must count exactly once")
        let encoded = try JSONEncoder().encode(value), text = String(decoding: encoded, as: UTF8.self)
        precondition(!text.contains("PRIVATE"), "Notes and journal data must never reach widgets")
        let dir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(WidgetSummary.filename)
        try encoded.write(to: file)
        precondition(WidgetSummary.read(file)?.focusSeconds == 2700)
        try Data("{}".utf8).write(to: file)
        precondition(WidgetSummary.read(file) == nil && FileManager.default.fileExists(atPath: file.path))
        try Data(repeating: 0, count: 131073).write(to: file)
        precondition(WidgetSummary.read(file) == nil)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        let next = value.at(tomorrow)
        precondition(next.taskCount == 0 && next.nextTasks.isEmpty && next.focusSeconds == 0 && next.dayFocus.isEmpty)
        precondition(next.streak(at: tomorrow) >= 12 && next.timerStatus == "completed")
        var paused = timer; paused["status"] = "paused"; paused.removeValue(forKey: "focusStartedAt"); paused.removeValue(forKey: "endsAt")
        precondition(WidgetSummary.make(state: state, timer: paused, now: now).focusSeconds == 2400)
        var breakTimer = timer; breakTimer["phase"] = "short"
        precondition(WidgetSummary.make(state: state, timer: breakTimer, now: now).focusSeconds == 2400)
        let empty = WidgetSummary.make(state: nil, timer: [:], now: now)
        precondition(empty.valid && empty.taskCount == 0 && empty.habitStartedAt == nil)
        print("PASS: widget priority, task completion, streak, current focus, pause/break exclusion, legacy sessions, private-field exclusion, safe decode, midnight rollover and timer expiry")
    }
}
