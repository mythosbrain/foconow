import SwiftUI
import WidgetKit
import Darwin

struct HabitWidgetEntry: TimelineEntry {
    var date: Date
    var summary: WidgetSummary?
}

struct HabitWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> HabitWidgetEntry { preview() }
    func getSnapshot(in context: Context, completion: @escaping (HabitWidgetEntry) -> Void) {
        completion(context.isPreview ? preview() : HabitWidgetEntry(date: Date(), summary: readSummary()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<HabitWidgetEntry>) -> Void) {
        let now = Date(), summary = readSummary()
        let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))!
        var dates = [now, midnight]
        if let end = summary?.timerEnd, summary?.timerStatus == "running", end > now { dates.append(end) }
        if let start = summary?.habitStartedAt {
            let nextDay = start.addingTimeInterval(Double((summary?.streak(at: now) ?? 0) + 1) * 86400)
            if nextDay > now { dates.append(nextDay) }
        }
        let entries = Set(dates).sorted().map { HabitWidgetEntry(date: $0, summary: summary?.at($0)) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(900))))
    }
    private func readSummary() -> WidgetSummary? {
        // Sandbox changes NSHomeDirectory(); resolve the user's home, then use the narrowly scoped
        // read-only file entitlement. No access to the main task/journal database is requested.
        guard let home = getpwuid(getuid())?.pointee.pw_dir else { return nil }
        let url = URL(fileURLWithPath: String(cString: home), isDirectory: true)
            .appendingPathComponent("Library/Application Support/com.yassine.habitcounter/" + WidgetSummary.filename)
        return WidgetSummary.read(url)
    }
    private func preview() -> HabitWidgetEntry {
        let now = Date(), key = WidgetSummary.dayKey(now)
        let summary = WidgetSummary.make(state: ["activeId": "preview", "habits": [["id": "preview", "name": "Less scrolling", "startedAt": now.addingTimeInterval(-12 * 86400).timeIntervalSince1970 * 1000]], "planner": [key: ["focus": "Make room for what matters", "tasks": [["id": "1", "title": "Finish the important work", "done": false, "priority": true], ["id": "2", "title": "Go for a walk", "done": false], ["id": "3", "title": "Plan the day", "done": true]]]]], timer: [:], now: now)
        return HabitWidgetEntry(date: now, summary: summary)
    }
}

struct WidgetSurface<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View { content.foregroundStyle(.white).containerBackground(.black, for: .widget).preferredColorScheme(.dark) }
}

struct EmptyHabitWidget: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: "scope").font(.title2)
            Spacer(minLength: 0)
            Text("Your day,\nwithin reach.").font(.system(size: 20, weight: .semibold))
            Text("Open FocoNow to get started.").font(.caption2).foregroundStyle(.white.opacity(0.55))
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct FocusWidgetView: View {
    let entry: HabitWidgetEntry
    var familyOverride: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var systemFamily
    private var family: WidgetFamily { familyOverride ?? systemFamily }
    var body: some View {
        WidgetSurface {
            if let value = entry.summary {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(value.phase == "work" ? "FOCUS" : "BREAK", systemImage: value.phase == "work" ? "circle.dotted" : "cup.and.saucer")
                            .font(.system(size: 10, weight: .semibold)).tracking(1)
                        Spacer(minLength: 0)
                        if value.timerStatus == "paused" { Image(systemName: "pause.fill").font(.caption2) }
                        if value.timerStatus == "completed" { Image(systemName: "checkmark").font(.caption2) }
                    }.foregroundStyle(.white.opacity(0.6))
                    Spacer(minLength: 0)
                    if value.timerStatus == "running", let end = value.timerEnd, end > entry.date {
                        Text(timerInterval: entry.date...end, countsDown: true)
                            .font(.system(size: family == .systemSmall ? 38 : 46, weight: .light, design: .rounded)).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                    } else {
                        Text(String(format: "%02d:%02d", value.timerRemaining / 60, value.timerRemaining % 60))
                            .font(.system(size: family == .systemSmall ? 38 : 46, weight: .light, design: .rounded)).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                    }
                    Text(value.timerStatus == "completed" ? "Interval complete. Take a moment." : value.timerTask.isEmpty ? "One thing at a time." : value.timerTask)
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).lineLimit(family == .systemSmall ? 2 : 1)
                    Spacer(minLength: 0)
                    if value.timerStatus == "running", let end = value.timerEnd, end > entry.date {
                        ProgressView(timerInterval: end.addingTimeInterval(-Double(value.timerDuration))...end, countsDown: false).labelsHidden().tint(.white)
                    } else {
                        ProgressView(value: max(0, min(1, 1 - Double(value.timerRemaining) / Double(value.timerDuration)))).tint(.white)
                    }
                    if family != .systemSmall { Text("Open Tasks & Focus  ↗").font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)) }
                }
            } else { EmptyHabitWidget() }
        }.widgetURL(URL(string: "habitcounter://tasks"))
    }
}

struct TasksWidgetView: View {
    let entry: HabitWidgetEntry
    var familyOverride: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var systemFamily
    private var family: WidgetFamily { familyOverride ?? systemFamily }
    var body: some View {
        WidgetSurface {
            if let value = entry.summary {
                VStack(alignment: .leading, spacing: family == .systemLarge ? 16 : 9) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Today").font(.system(size: 22, weight: .semibold))
                        Spacer()
                        Text("\(value.completedTasks)/\(value.taskCount)").font(.system(size: 25, weight: .light)).monospacedDigit()
                    }
                    if family == .systemLarge, !value.dayFocus.isEmpty { Text(value.dayFocus).font(.system(size: 15, weight: .medium)).lineLimit(2) }
                    if value.nextTasks.isEmpty {
                        Spacer(minLength: 0)
                        Label(value.taskCount > 0 ? "All done. Make room for you." : "Choose what matters today.", systemImage: value.taskCount > 0 ? "checkmark.circle" : "plus.circle")
                            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
                    } else {
                        ForEach(value.nextTasks.prefix(family == .systemLarge ? 5 : 2)) { task in
                            HStack(spacing: 9) {
                                Image(systemName: task.priority ? "star" : "circle").font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                                Text(task.title).font(.system(size: 12)).lineLimit(family == .systemLarge ? 2 : 1)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    ProgressView(value: value.taskCount == 0 ? 0 : Double(value.completedTasks) / Double(value.taskCount)).tint(.white)
                    HStack {
                        Text("\(focusTime(value.focusSeconds)) focus tracked")
                        Spacer()
                        Text(value.updatedAt, style: .time)
                    }.font(.system(size: 9)).foregroundStyle(.white.opacity(0.45))
                }
            } else { EmptyHabitWidget() }
        }.widgetURL(URL(string: "habitcounter://tasks"))
    }
    private func focusTime(_ seconds: Int) -> String {
        seconds >= 3600 ? "\(seconds / 3600)h \((seconds % 3600) / 60)m" : "\(seconds / 60)m"
    }
}

struct StreakWidgetView: View {
    let entry: HabitWidgetEntry
    var body: some View {
        WidgetSurface {
            if let value = entry.summary {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Image(systemName: "leaf").font(.system(size: 20))
                        Spacer()
                        Text("STREAK").font(.system(size: 9, weight: .semibold)).tracking(1.2).foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer(minLength: 0)
                    Text("\(value.streak(at: entry.date))").font(.system(size: 54, weight: .light, design: .rounded)).monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                    Text("days & counting").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                    Text(value.habitName).font(.system(size: 11, weight: .medium)).lineLimit(1)
                }
            } else { EmptyHabitWidget() }
        }.widgetURL(URL(string: "habitcounter://overview"))
    }
}

struct HabitFocusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HabitCounter.Focus", provider: HabitWidgetProvider()) { FocusWidgetView(entry: $0) }
            .configurationDisplayName("Focus timer").description("Your current focus or break, counting down on your desktop.")
            .supportedFamilies([.systemSmall, .systemMedium]).containerBackgroundRemovable(false)
    }
}
struct HabitTasksWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HabitCounter.Tasks", provider: HabitWidgetProvider()) { TasksWidgetView(entry: $0) }
            .configurationDisplayName("Today's tasks").description("Your next tasks, daily progress, and recorded focus time.")
            .supportedFamilies([.systemMedium, .systemLarge]).containerBackgroundRemovable(false)
    }
}
struct HabitStreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HabitCounter.Streak", provider: HabitWidgetProvider()) { StreakWidgetView(entry: $0) }
            .configurationDisplayName("Bad habit streak").description("A little better, every day. Keep your current streak in sight.")
            .supportedFamilies([.systemSmall]).containerBackgroundRemovable(false)
    }
}

#if !WIDGET_PREVIEW_HARNESS
@main
struct HabitCounterWidgetBundle: WidgetBundle {
    var body: some Widget { HabitFocusWidget(); HabitTasksWidget(); HabitStreakWidget() }
}
#endif
