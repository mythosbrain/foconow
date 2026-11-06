#if os(macOS)
import AppKit
import ApplicationServices

struct SettingsAXNode: Codable {
    var role: String
    var title = ""
    var value = ""
    var label = ""
    var identifier = ""
    var children: [SettingsAXNode] = []
    var texts: [String] { [title,value,label].filter { !$0.isEmpty } }
    var flattened: [SettingsAXNode] { [self] + children.flatMap(\.flattened) }
}
struct SettingsUsageReport: Codable, Equatable {
    var deviceName: String
    var date: String
    var totalSeconds: Double
    var apps: [SettingsUsageApp]
    var capturedAt: Double
}
struct SettingsUsageApp: Codable, Equatable {
    var name: String
    var seconds: Double
}
struct SettingsReportFailure: Error {
    var status: String
    var message: String
}

/// Reads only System Settings' current Screen Time window, upon an explicit user request.
enum SettingsScreenTimeReader {
    static var trusted: Bool { AXIsProcessTrusted() }
    static func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String:true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
    }
    static func openSettings() {
        if let url = URL(string:"x-apple.systempreferences:com.apple.Screen-Time-Settings.extension") { NSWorkspace.shared.open(url) }
    }
    static func read() throws -> SettingsAXNode {
        guard trusted else { throw SettingsReportFailure(status:"accessibility",message:"Allow FocoNow in Privacy & Security → Accessibility, then try again. Full Disk Access is a different permission.") }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.systempreferences").first else { throw SettingsReportFailure(status:"settingsNotOpen",message:"Open System Settings → Screen Time → App & Website Activity. Choose your iPhone and the day you want, then read it here.") }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root,0.5)
        guard let windows = attribute(root,kAXWindowsAttribute) as? [AXUIElement], !windows.isEmpty else { throw SettingsReportFailure(status:"unavailable",message:"System Settings has no readable window. Open its Screen Time report, then try again.") }
        var count = 0, visited = Set<CFHashCode>()
        let deadline = Date().addingTimeInterval(10)
        func node(_ element: AXUIElement, depth: Int) -> SettingsAXNode? {
            guard depth <= 36, count < 4000, Date() < deadline, visited.insert(CFHash(element)).inserted else { return nil }
            count += 1
            let role = attribute(element,kAXRoleAttribute) as? String ?? ""
            if role == "AXSecureTextField" { return SettingsAXNode(role:role) }
            var result = SettingsAXNode(role:role,title:attribute(element,kAXTitleAttribute) as? String ?? "",value:attribute(element,kAXValueAttribute) as? String ?? "",label:attribute(element,kAXDescriptionAttribute) as? String ?? "",identifier:attribute(element,kAXIdentifierAttribute) as? String ?? "")
            var children = attribute(element,kAXChildrenAttribute) as? [AXUIElement] ?? []
            if role == kAXTableRole || role == kAXOutlineRole { children += attribute(element,kAXRowsAttribute) as? [AXUIElement] ?? [] }
            result.children = children.compactMap { node($0,depth:depth+1) }
            return result
        }
        let trees = windows.compactMap { node($0,depth:0) }
        guard Date() < deadline, count < 4000 else { throw SettingsReportFailure(status:"unavailable",message:"Reading the Settings report took too long. Keep only its Screen Time window open and retry.") }
        return SettingsAXNode(role:"ScreenTimeWindows",children:trees)
    }
    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element,name as CFString,&value) == .success ? value : nil
    }
    static func duration(_ text: String) -> Double? {
        let text = text.replacingOccurrences(of:"\u{00a0}",with:" ").replacingOccurrences(of:"\u{202f}",with:" ").replacingOccurrences(of:",",with:" ").trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
        guard let expression = try? NSRegularExpression(pattern:#"^(?:(\d+)\s*(?:h|hr|hrs|hour|hours)\s*)?(?:(\d+)\s*(?:m|min|mins|minute|minutes)\s*)?(?:(\d+)\s*(?:s|sec|secs|second|seconds)\s*)?$"#),
              let match = expression.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)), !text.isEmpty else { return nil }
        var seconds = 0.0, found = false
        for (index,multiplier) in [(1,3600.0),(2,60.0),(3,1.0)] {
            if let range = Range(match.range(at:index),in:text), let number = Double(text[range]) { seconds += number*multiplier; found = true }
        }
        return found && seconds <= 90000 ? seconds : nil
    }
    static func reportDate(_ text: String, now: Date, calendar: Calendar) -> Date? {
        let lower = text.lowercased().trimmingCharacters(in:.whitespacesAndNewlines)
        if lower == "today" { return calendar.startOfDay(for:now) }
        if lower == "yesterday" { return calendar.date(byAdding:.day,value:-1,to:calendar.startOfDay(for:now)) }
        guard !lower.contains("week"), !lower.contains("month"), !lower.contains("–"), !lower.contains("—") else { return nil }
        let pattern = #"^(?:(?:today|yesterday|monday|tuesday|wednesday|thursday|friday|saturday|sunday|mon|tue|wed|thu|fri|sat|sun),?\s*)?(?:(\d{1,2})\s+([a-z]+)|([a-z]+)\s+(\d{1,2}))(?:,?\s+(\d{4}))?$"#
        guard let regex = try? NSRegularExpression(pattern:pattern), let match = regex.firstMatch(in:lower,range:NSRange(lower.startIndex...,in:lower)) else { return nil }
        func group(_ index:Int) -> String? { Range(match.range(at:index),in:lower).map { String(lower[$0]) } }
        let names = ["january","february","march","april","may","june","july","august","september","october","november","december"]
        guard let day = Int(group(1) ?? group(4) ?? ""), let monthText = group(2) ?? group(3), let monthIndex = names.firstIndex(where: { $0 == monthText || String($0.prefix(3)) == monthText }) else { return nil }
        let month = monthIndex+1
        var year = Int(group(5) ?? "") ?? calendar.component(.year,from:now)
        if group(5) == nil && month > calendar.component(.month,from:now) { year -= 1 }
        guard let date = calendar.date(from:DateComponents(year:year,month:month,day:day)), calendar.component(.month,from:date) == month, calendar.component(.day,from:date) == day, date <= calendar.startOfDay(for:now) else { return nil }
        if lower.hasPrefix("today") && !calendar.isDate(date,inSameDayAs:now) { return nil }
        if lower.hasPrefix("yesterday"), let expected = calendar.date(byAdding:.day,value:-1,to:now), !calendar.isDate(date,inSameDayAs:expected) { return nil }
        return date
    }
    static func pressDateButton(_ label: String) throws {
        guard trusted, let app = NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.systempreferences").first else { throw SettingsReportFailure(status:"accessibility",message:"Accessibility access or the open Settings report is unavailable.") }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root,0.4)
        let windows = attribute(root,kAXWindowsAttribute) as? [AXUIElement] ?? []
        guard let window = windows.first(where: { (attribute($0,kAXTitleAttribute) as? String ?? "").contains("App & Website Activity") }) else { throw SettingsReportFailure(status:"wrongPage",message:"Keep Settings on the iPhone App & Website Activity report for automatic import.") }
        var visited = Set<CFHashCode>(), count = 0
        let deadline = Date().addingTimeInterval(5)
        func find(_ element:AXUIElement) -> AXUIElement? {
            guard count < 4000, Date() < deadline, visited.insert(CFHash(element)).inserted else { return nil }; count += 1
            let role = attribute(element,kAXRoleAttribute) as? String ?? ""
            if role == "AXButton", [kAXTitleAttribute,kAXDescriptionAttribute].contains(where: { attribute(element,$0) as? String == label }), attribute(element,kAXEnabledAttribute) as? Bool != false { return element }
            for child in attribute(element,kAXChildrenAttribute) as? [AXUIElement] ?? [] { if let found = find(child) { return found } }
            return nil
        }
        guard let button = find(window), AXUIElementPerformAction(button,kAXPressAction as CFString) == .success else { throw SettingsReportFailure(status:"navigation",message:"Settings did not allow changing the report day. Open its daily iPhone report and retry.") }
    }
    static func parse(_ tree: SettingsAXNode, now: Date = Date(), calendar: Calendar = .current) throws -> SettingsUsageReport {
        let nodes = tree.flattened
        let allText = nodes.flatMap(\.texts)
        guard allText.contains(where: { $0.localizedCaseInsensitiveContains("App & Website Activity") }) else { throw SettingsReportFailure(status:"wrongPage",message:"In System Settings, open Screen Time → App & Website Activity first.") }
        // Only controls can identify the selected device/date; sidebar labels are not evidence.
        let controls = nodes.filter { ["AXPopUpButton","AXMenuButton","AXComboBox"].contains($0.role) }.flatMap { $0.flattened.flatMap(\.texts) }
        guard let device = controls.first(where: { ($0.localizedCaseInsensitiveContains("iPhone") || $0.localizedCaseInsensitiveContains("iPad")) && !$0.localizedCaseInsensitiveContains("All Devices") }) else { throw SettingsReportFailure(status:"wrongDevice",message:"Select your iPhone in the Device menu in Settings. Mac and All Devices reports won’t be imported as iPhone usage.") }
        let dates = controls.compactMap { reportDate($0,now:now,calendar:calendar) }
        guard let date = dates.first else { throw SettingsReportFailure(status:"unverifiedDate",message:"Choose a single day in the Usage date menu in Settings. Week ranges cannot be imported as a day.") }
        var apps: [SettingsUsageApp] = [], total: Double?
        for row in nodes where row.role == "AXRow" {
            let texts = row.flattened.flatMap(\.texts).reduce(into:[String]()) { values,text in if !values.contains(text) { values.append(text) } }
            guard let timed = texts.compactMap({ text -> Double? in duration(text) }).first else { continue }
            if texts.contains(where: { $0.caseInsensitiveCompare("All Usage") == .orderedSame }) { total = timed; continue }
            guard let name = texts.first(where: { duration($0) == nil && !["Apps","Time","Limits","Limit"].contains($0) && !$0.isEmpty }) else { continue }
            if !apps.contains(where: { $0.name == name }) { apps.append(SettingsUsageApp(name:name,seconds:timed)) }
        }
        let header = nodes.first(where: { $0.identifier == "usageHeaderView" })?.texts.compactMap(duration).first
        if let header, let total, header != total { throw SettingsReportFailure(status:"unavailable",message:"Settings is still updating this day's report. Try again in a moment.") }
        guard let total = total ?? header else { throw SettingsReportFailure(status:"unavailable",message:"Settings did not expose a readable All Usage total. Keep the report open with its app table visible, then retry.") }
        return SettingsUsageReport(deviceName:device,date:PhoneScreenTimeController.dateKey(date,calendar:calendar),totalSeconds:total,apps:apps.sorted { $0.seconds > $1.seconds },capturedAt:now.timeIntervalSince1970*1000)
    }
}
#endif
