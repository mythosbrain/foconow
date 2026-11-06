import AppKit
import UserNotifications

@main
struct PlannerNativeChecks {
    static func main() throws {
        let requests = try DesktopPlannerReminders.requests(morning: "08:45", evening: "22:10")
        assert(requests.count == 2)
        let am = requests[0].trigger as! UNCalendarNotificationTrigger
        let pm = requests[1].trigger as! UNCalendarNotificationTrigger
        assert(am.repeats && pm.repeats)
        assert(am.dateComponents.hour == 8 && am.dateComponents.minute == 45)
        assert(pm.dateComponents.hour == 22 && pm.dateComponents.minute == 10)
        assert(requests[0].identifier != requests[1].identifier)
        assert(requests[0].content.userInfo["habitAction"] as? String == "morning")
        assert(requests[1].content.userInfo["habitAction"] as? String == "summary")
        for invalid in ["25:00", "09:99", "wrong", "-1:30"] {
            do { _ = try DesktopPlannerReminders.requests(morning: invalid, evening: "21:00"); fatalError("Invalid time accepted") }
            catch { }
        }
        assert(DesktopLifecycle().applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared) == false)
        print("PASS: two repeating private reminders use chosen times and correct planner actions; invalid times rejected; closing the last window keeps the app running")
    }
}
