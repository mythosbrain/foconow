import Foundation
import UserNotifications

@main struct ReminderChecks {
    static func main() throws {
        var settings = NudgeSettings()
        func decision(hour: Int = 12, elapsed: Double = 5400, snoozed: Bool = false,
                      status: String = "ready", phase: String = "work", remaining: Int = 600,
                      focusElapsed: Double = 1800, unfinished: Int = 2, present: Bool = true) -> String? {
            NudgePolicy.kind(settings: settings, hour: hour, elapsed: elapsed, snoozed: snoozed,
                timerStatus: status, phase: phase, remaining: remaining, focusElapsed: focusElapsed,
                unfinished: unfinished, present: present)
        }
        assert(decision() == nil, "Existing users must opt into new nudges")
        settings.tasks = true
        assert(decision() == "tasks")
        assert(decision(elapsed: 5399) == nil, "Respect frequency")
        assert(decision(unfinished: 0) == nil, "No reminders after finishing tasks")
        assert(decision(present: false) == nil, "No idle/sleep nudges")
        assert(decision(snoozed: true) == nil, "Snooze takes precedence")
        assert(decision(hour: 8) == nil && decision(hour: 21) == nil, "Quiet hours")
        assert(decision(status: "running") == nil && decision(status: "paused") == nil, "Do not interrupt a timer with task reminders")
        settings.focus = true
        assert(decision(status: "running") == "focus")
        assert(decision(elapsed: 1799, status: "running") == nil, "No close-together check-ins")
        assert(decision(status: "running", focusElapsed: 1799) == nil)
        assert(decision(status: "running", remaining: 120) == nil, "Never near the alarm")
        assert(decision(status: "running", phase: "short") == nil && decision(status: "running", phase: "long") == nil)
        settings.startHour = 22; settings.endHour = 6
        assert(decision(hour: 23) == "tasks" && decision(hour: 3) == "tasks" && decision(hour: 12) == nil)
        settings.startHour = 6
        assert(!settings.valid && decision() == nil)
        settings.startHour = 9; settings.interval = 1
        assert(!settings.valid)
        for phase in ["work", "short", "long"] {
            let content = PomodoroEngine.completionContent(phase: phase, sounds: true)
            assert(content.sound != nil && content.userInfo["habitAction"] as? String == "tasks")
            assert(PomodoroEngine.completionContent(phase: phase, sounds: false).sound == nil)
            assert(!content.body.contains("private task"))
        }
        let audible = try DesktopPlannerReminders.requests(morning: "09:00", evening: "21:00")
        let silent = try DesktopPlannerReminders.requests(morning: "09:00", evening: "21:00", sounds: false)
        assert(audible.allSatisfy { $0.content.sound != nil })
        assert(silent.allSatisfy { $0.content.sound == nil })
        print("PASS: opt-in, completed tasks, idle, snooze, cooldown, quiet/overnight hours, focus/break suppression, valid settings, audible/silent timer and daily payloads")
    }
}
