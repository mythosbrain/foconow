import Foundation

/// A small read-only projection. Journals, task notes, and phone usage never enter this file.
struct WidgetSummary: Codable {
    static let filename = "widget-summary.json"
    var version = 1
    var updatedAt: Date
    var day: String
    var habitName: String
    var habitStartedAt: Date?
    var targetDays: Int
    var dayFocus: String
    var taskCount: Int
    var completedTasks: Int
    var nextTasks: [Task]
    var focusSeconds: Int
    var phase: String
    var timerStatus: String
    var timerDuration: Int
    var timerRemaining: Int
    var timerEnd: Date?
    var timerTask: String
    struct Task: Codable, Identifiable { var id: String; var title: String; var priority: Bool }

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
    static func make(state: [String: Any]?, timer: [String: Any], now: Date = Date(), calendar: Calendar = .current) -> WidgetSummary {
        let key = dayKey(now, calendar: calendar)
        let habits = state?["habits"] as? [[String: Any]] ?? []
        let habit = habits.first { $0["id"] as? String == state?["activeId"] as? String } ?? habits.first
        let plan = (state?["planner"] as? [String: [String: Any]])?[key] ?? [:]
        let tasks = plan["tasks"] as? [[String: Any]] ?? []
        let pending = tasks.filter { $0["done"] as? Bool != true }
        let ordered = pending.filter { $0["priority"] as? Bool == true } + pending.filter { $0["priority"] as? Bool != true }
        let start = calendar.startOfDay(for: now).timeIntervalSince1970 * 1000
        let end = min(now.timeIntervalSince1970 * 1000, (calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now).timeIntervalSince1970 * 1000)
        func overlap(_ a: Double, _ b: Double) -> Double { max(0, min(end, b) - max(start, a)) / 1000 }
        var seconds = (timer["focusSpans"] as? [[String: Any]] ?? []).reduce(0.0) { sum, span in sum + overlap(span["start"] as? Double ?? 0, span["end"] as? Double ?? 0) }
        for session in timer["sessions"] as? [[String: Any]] ?? [] where session["tracked"] as? Bool != true {
            let stop = session["endedAt"] as? Double ?? 0
            seconds += overlap(stop - (session["seconds"] as? Double ?? 0) * 1000, stop)
        }
        if timer["status"] as? String == "running", timer["phase"] as? String == "work", let anchor = timer["focusStartedAt"] as? Double, let deadline = timer["endsAt"] as? Double { seconds += overlap(anchor, deadline) }
        return WidgetSummary(updatedAt: now, day: key, habitName: habit?["name"] as? String ?? "Your habit", habitStartedAt: (habit?["startedAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }, targetDays: max(1, habit?["targetDays"] as? Int ?? 30), dayFocus: plan["focus"] as? String ?? "", taskCount: tasks.count, completedTasks: tasks.count - pending.count,
            nextTasks: ordered.prefix(5).map { Task(id: $0["id"] as? String ?? UUID().uuidString, title: $0["title"] as? String ?? "Task", priority: $0["priority"] as? Bool == true) }, focusSeconds: max(0, Int(seconds)), phase: timer["phase"] as? String ?? "work", timerStatus: timer["status"] as? String ?? "ready", timerDuration: timer["duration"] as? Int ?? 1500, timerRemaining: timer["remaining"] as? Int ?? 1500, timerEnd: (timer["endsAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }, timerTask: timer["taskTitle"] as? String ?? "")
    }
    func at(_ date: Date) -> WidgetSummary {
        var result = self
        if day != Self.dayKey(date) { result.dayFocus = ""; result.taskCount = 0; result.completedTasks = 0; result.nextTasks = []; result.focusSeconds = 0 }
        if timerStatus == "running", let timerEnd, timerEnd <= date { result.timerStatus = "completed"; result.timerRemaining = 0 }
        return result
    }
    func streak(at date: Date) -> Int { max(0, Int(date.timeIntervalSince(habitStartedAt ?? date) / 86400)) }
    var valid: Bool {
        version == 1 && day.count == 10 && habitName.count <= 160 && dayFocus.count <= 1000 && (1...100000).contains(targetDays) && (0...100).contains(taskCount) && (0...taskCount).contains(completedTasks) && nextTasks.count <= 5 && nextTasks.allSatisfy { $0.id.count <= 100 && $0.title.count <= 240 } && (0...172800).contains(focusSeconds) && ["work", "short", "long"].contains(phase) && ["ready", "running", "paused", "completed"].contains(timerStatus) && (1...10800).contains(timerDuration) && (0...timerDuration).contains(timerRemaining) && timerTask.count <= 240 && (timerStatus != "running" || timerEnd != nil)
    }
    static func read(_ url: URL) -> WidgetSummary? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 128 * 1024,
              let data = try? Data(contentsOf: url), data.count <= 128 * 1024,
              let value = try? JSONDecoder().decode(Self.self, from: data), value.valid else { return nil }
        return value
    }
}
