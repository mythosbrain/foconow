import AppKit
import SwiftUI
import WidgetKit

@main
struct WidgetPreview {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = PreviewRunner(); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
final class PreviewRunner: NSObject, NSApplicationDelegate {
    var windows: [NSWindow] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        let now = Date(), key = WidgetSummary.dayKey(now)
        let state: [String: Any] = ["activeId": "p", "habits": [["id": "p", "name": "Less scrolling", "startedAt": now.addingTimeInterval(-12 * 86400).timeIntervalSince1970 * 1000]], "planner": [key: ["focus": "Make room for what matters", "tasks": [["id": "1", "title": "Finish the important work", "done": false, "priority": true], ["id": "2", "title": "Go for a long walk", "done": false], ["id": "3", "title": "Plan my morning", "done": true]]]]]
        let summary = WidgetSummary.make(state: state, timer: ["phase": "work", "status": "paused", "remaining": 1350, "duration": 1500, "taskTitle": "Finish the important work"], now: now)
        let entry = HabitWidgetEntry(date: now, summary: summary)
        render(StreakWidgetView(entry: entry), name: "streak-small", size: NSSize(width: 170, height: 170), family: .systemSmall)
        render(FocusWidgetView(entry: entry, familyOverride: .systemSmall), name: "focus-small", size: NSSize(width: 170, height: 170), family: .systemSmall)
        render(FocusWidgetView(entry: entry, familyOverride: .systemMedium), name: "focus-medium", size: NSSize(width: 360, height: 170), family: .systemMedium)
        render(TasksWidgetView(entry: entry, familyOverride: .systemMedium), name: "tasks-medium", size: NSSize(width: 360, height: 170), family: .systemMedium)
        render(TasksWidgetView(entry: entry, familyOverride: .systemLarge), name: "tasks-large", size: NSSize(width: 360, height: 376), family: .systemLarge)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            for (index, window) in self.windows.enumerated() {
                guard let view = window.contentView, let image = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("Widget preview could not render") }
                view.cacheDisplay(in: view.bounds, to: image)
                let name = window.title
                try! image.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(name + ".png"))
                print("Rendered \(index + 1): \(name)")
            }
            NSApplication.shared.terminate(nil)
        }
    }
    private func render<Content: View>(_ view: Content, name: String, size: NSSize, family: WidgetFamily) {
        let root = view.padding(16).frame(width: size.width, height: size.height).background(.black).clipShape(RoundedRectangle(cornerRadius: 24))
        let host = NSHostingView(rootView: root); host.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.title = name; window.contentView = host; window.orderFront(nil); windows.append(window)
    }
}
