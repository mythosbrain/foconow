import Foundation

@main struct CompleteBackupChecks {
    static func main() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("foconow-full-backup-\(UUID().uuidString)")
        let defaults = UserDefaults(suiteName: "foconow.checks.\(UUID().uuidString)")!
        defer { try? FileManager.default.removeItem(at: root); for key in CompleteBackup.keys { defaults.removeObject(forKey: key) } }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let state: [String: Any] = ["version": 1, "activeId": "habit", "habits": [["id": "habit", "name": "Example"]], "planner": [:]]
        defaults.set("dark", forKey: "habit-counter.desktop-appearance")
        defaults.set(true, forKey: "habit-counter.planner-reminders.enabled")
        defaults.set("09:15", forKey: "habit-counter.planner-reminders.morning")
        defaults.set(try JSONEncoder().encode(NudgeSettings()), forKey: CompleteBackup.nudgeKey)
        var time = Date(timeIntervalSince1970: 1794571200)
        let engine = PomodoroEngine(directory: root, clock: { time }, ticking: false)
        try engine.start(); time.addTimeInterval(100)
        let timer = engine.backupRecord()
        assert(timer.status == "paused" && timer.focusSpans?.count == 1 && timer.remaining == 1400)
        assert(engine.record.status == "running", "Export must not pause the live timer")
        let reports: [[String: Any]] = [["deviceName": "Sample phone", "date": "2026-11-13", "totalSeconds": 1200, "capturedAt": time.timeIntervalSince1970*1000, "apps": [["name": "Reader", "seconds": 1200]]]]
        try CompleteBackup.write(try CompleteBackup.json(reports), to: root.appendingPathComponent("iphone-settings-reports.json"))
        let backup = try CompleteBackup.make(state: state, timer: timer, directory: root, defaults: defaults)
        let roundTrip = try JSONSerialization.jsonObject(with: CompleteBackup.json(backup)) as! [String: Any]
        try CompleteBackup.validate(roundTrip)
        let oldState = try CompleteBackup.json(["version": 1, "habits": [["id":"old"]]])
        try CompleteBackup.write(oldState, to: root.appendingPathComponent("state.json"))
        defaults.set("light", forKey: "habit-counter.desktop-appearance")
        let originalTimer = try Data(contentsOf: root.appendingPathComponent("pomodoro.json"))
        do {
            try CompleteBackup.restore(roundTrip, validatedState: state, directory: root, defaults: defaults) { index in
                if index == 1 { throw CompleteBackup.failure("Injected disk failure") }
            }
            fatalError("Injected failure was ignored")
        } catch { }
        let afterFailedState = try Data(contentsOf: root.appendingPathComponent("state.json")); assert(afterFailedState == oldState)
        let afterFailedTimer = try Data(contentsOf: root.appendingPathComponent("pomodoro.json")); assert(afterFailedTimer == originalTimer)
        assert(defaults.string(forKey: "habit-counter.desktop-appearance") == "light")
        assert(!FileManager.default.fileExists(atPath: root.appendingPathComponent("restore-journal.json").path))
        try CompleteBackup.restore(roundTrip, validatedState: state, directory: root, defaults: defaults)
        assert(defaults.string(forKey: "habit-counter.desktop-appearance") == "dark")
        let restored = PomodoroEngine(directory: root, clock: { time }, ticking: false)
        assert(restored.record.status == "paused" && restored.remaining == 1400 && restored.record.focusSpans?.count == 1)
        let restoredReports = try Data(contentsOf: root.appendingPathComponent("iphone-settings-reports.json")); let expectedReports = try CompleteBackup.json(reports); assert(restoredReports == expectedReports)
        // Simulate power loss after overwriting one file, then recover at startup.
        var images: [String: Any] = [:]
        for name in CompleteBackup.files { let path=root.appendingPathComponent(name);images[name]=FileManager.default.fileExists(atPath:path.path) ? try Data(contentsOf:path).base64EncodedString() : NSNull() }
        try CompleteBackup.write(try CompleteBackup.json(["files":images,"preferences":CompleteBackup.preferences(defaults)]), to:root.appendingPathComponent("restore-journal.json"))
        try CompleteBackup.write(Data("broken".utf8),to:root.appendingPathComponent("state.json"))
        let reopened = NativeStore(directory:root,backupDefaults:defaults)
        assert(reopened.loadError == nil && reopened.state?["activeId"] as? String == "habit")
        var invalid = roundTrip; invalid["screenTime"] = ["../../escape": [:]]
        do { try CompleteBackup.validate(invalid); fatalError("Accepted an arbitrary path") } catch { }
        invalid=roundTrip; invalid["preferences"]=["habit-counter.desktop-widget.dock":"yes"]
        do { try CompleteBackup.validate(invalid); fatalError("Accepted malformed preferences") } catch { }
        invalid=roundTrip;invalid["pomodoro"]=try JSONSerialization.jsonObject(with:JSONEncoder().encode(engine.record))
        do { try CompleteBackup.validate(invalid); fatalError("Accepted a running import") } catch { }
        let future = Date().addingTimeInterval(3600), formatter=DateFormatter();formatter.dateFormat="yyyy-MM-dd"
        let date=formatter.string(from:future);formatter.dateFormat="HH:mm";let dueTime=formatter.string(from:future)
        let task: [String:Any] = ["originId":"carried","done":false,"remindAtDeadline":true,"dueDate":date,"dueTime":dueTime]
        let duplicate: [String:Any] = ["planner":["2026-11-12":["tasks":[task]],"2026-11-13":["tasks":[task]]]]
        assert(TaskDeadlineAlerts.candidates(duplicate).count == 1)
        var done=task;done["done"]=true
        assert(TaskDeadlineAlerts.candidates(["planner":["2026-11-12":["tasks":[task]],"2026-11-13":["tasks":[done]]]]).isEmpty)
        print("PASS: complete round trip; focus snapshot; preferences and Screen Time; failed-write rollback; crash recovery; invalid paths/preferences/timers rejected; carried deadline deduplication and completion cancellation")
    }
}
