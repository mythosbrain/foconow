#if os(macOS)
import Foundation

struct SettingsHistorySource {
    var read: () throws -> SettingsUsageReport
    var today: () throws -> Void
    var previous: () throws -> Void
    static func live(diagnosticsDirectory: URL? = nil) -> SettingsHistorySource {
        SettingsHistorySource(read: {
            let tree=try SettingsScreenTimeReader.read()
            do { return try SettingsScreenTimeReader.parse(tree) }
            catch {
                if let directory=diagnosticsDirectory,tree.flattened.flatMap(\.texts).contains(where:{$0.contains("App & Website Activity")}),let data=try? JSONEncoder().encode(tree) {
                    let url=directory.appendingPathComponent("iphone-settings-report-tree.json")
                    try? data.write(to:url,options:.atomic);try? FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
                }
                throw error
            }
        },today: { try SettingsScreenTimeReader.pressDateButton("Today") },previous: { try SettingsScreenTimeReader.pressDateButton("Back") })
    }
}
enum SettingsHistoryImporter {
    static func run(days: Int, source: SettingsHistorySource, now: Date = Date(), calendar: Calendar = .current, expectedDevice: String? = nil, pause: (Double)->Void = { Thread.sleep(forTimeInterval:$0) }, cancelled: ()->Bool = { false }, saved: (SettingsUsageReport,Int,Int)throws->Void) throws {
        guard (1...30).contains(days) else { throw SettingsReportFailure(status:"error",message:"Choose up to 30 days to import.") }
        func checkCancel() throws { if cancelled() { throw SettingsReportFailure(status:"cancelled",message:"Import stopped. Days already read stay saved.") } }
        let initial = try source.read(), device = expectedDevice ?? initial.deviceName
        guard initial.deviceName == device else { throw SettingsReportFailure(status:"wrongDevice",message:"Select \(device) in Settings before automatic refresh.") }
        let today = calendar.startOfDay(for:now), todayKey = PhoneScreenTimeController.dateKey(today,calendar:calendar)
        defer {
            // Only restore the day when the user has left this same device/report open.
            if let current = try? source.read(), current.deviceName == device, current.date != todayKey { try? source.today() }
        }
        try checkCancel()
        if initial.date != todayKey { try source.today(); pause(0.3) }
        for index in 0..<days {
            try checkCancel()
            let expected = PhoneScreenTimeController.dateKey(calendar.date(byAdding:.day,value:-index,to:today)!,calendar:calendar)
            var prior: SettingsUsageReport?, accepted: SettingsUsageReport?
            var lastFailure: Error?
            // Wait for date and payload to settle before attributing a total to a new day.
            for _ in 0..<12 {
                try checkCancel()
                do {
                    let current = try source.read()
                    guard current.deviceName == device else { throw SettingsReportFailure(status:"wrongDevice",message:"The selected device changed in Settings. Import stopped to keep devices separate.") }
                    if current.date == expected {
                        if let prior, prior.date == current.date, prior.totalSeconds == current.totalSeconds, prior.apps == current.apps { accepted = current; break }
                        prior = current
                    } else { prior = nil }
                } catch let failure as SettingsReportFailure {
                    if ["wrongDevice","accessibility","wrongPage","settingsNotOpen","unverifiedDate"].contains(failure.status) { throw failure }
                    lastFailure = failure
                } catch { lastFailure = error }
                pause(0.2)
            }
            guard let report = accepted else { throw lastFailure ?? SettingsReportFailure(status:"navigation",message:"Settings didn’t expose a stable report for \(expected). Days already imported are saved.") }
            try saved(report,index+1,days)
            if index+1 < days {
                try checkCancel()
                let before = try source.read()
                guard before.deviceName == device, before.date == expected else { throw SettingsReportFailure(status:"navigation",message:"Settings changed during the import. No totals were assigned to the wrong day.") }
                try source.previous(); pause(0.3)
            }
        }
    }
}
#endif
