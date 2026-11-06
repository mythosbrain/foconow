#if os(macOS)
import AppKit
import SwiftUI

/// An in-process desktop panel: shares the canonical state and timer, with no second data store.
/// This is deliberately separate from WidgetKit's system widget gallery.
final class DesktopWidgetController: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = DesktopWidgetController()
    static let didChange = Notification.Name("HabitCounterDesktopWidgetChanged")
    @Published private(set) var visible: Bool
    @Published private(set) var pinned: Bool
    @Published private(set) var dockEnabled: Bool
    private(set) var panel: DesktopWidgetPanel?
    private let defaults: UserDefaults
    private let prefix = "habit-counter.desktop-widget."
    private var observers: [NSObjectProtocol] = []
    private var moveSave: DispatchWorkItem?
    private var positioning = false

    override private init() {
        if DesktopLaunchCheck.directory != nil {
            let name = "com.yassine.habitcounter.widget-diagnostics"
            defaults = UserDefaults(suiteName: name)!
            defaults.removePersistentDomain(forName: name)
        } else { defaults = .standard }
        visible = defaults.bool(forKey: "habit-counter.desktop-widget.visible")
        pinned = defaults.bool(forKey: "habit-counter.desktop-widget.pinned")
        dockEnabled = defaults.object(forKey: "habit-counter.desktop-widget.dock") as? Bool ?? true
        super.init()
        for name in [NativeStore.didSave, PomodoroEngine.didUpdate, Notification.Name.NSCalendarDayChanged] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                DispatchQueue.main.async { self?.updateDock() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.placePanel() })
    }
    var configuration: [String: Any] { ["widgetVisible": visible, "widgetPinned": pinned, "dockBadge": dockEnabled] }
    func restore() { setVisible(visible); updateDock() }
    func setVisible(_ value: Bool) {
        if visible != value { visible = value }
        defaults.set(value, forKey: prefix + "visible")
        if value {
            if panel == nil { makePanel() }
            applyLevel(); placePanel(); panel?.orderFrontRegardless()
        } else { panel?.orderOut(nil) }
        changed()
    }
    func setPinned(_ value: Bool) {
        if pinned != value { pinned = value }
        defaults.set(value, forKey: prefix + "pinned")
        applyLevel(); changed()
    }
    func setDockEnabled(_ value: Bool) {
        if dockEnabled != value { dockEnabled = value }
        defaults.set(value, forKey: prefix + "dock")
        updateDock(); changed()
    }
    func resetPosition() {
        defaults.removeObject(forKey: prefix + "x"); defaults.removeObject(forKey: prefix + "y")
        placePanel()
    }
    private func changed() { NotificationCenter.default.post(name: Self.didChange, object: self) }
    private func makePanel() {
        let window = DesktopWidgetPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 410), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.title = "FocoNow — Mini panel"
        window.identifier = NSUserInterfaceItemIdentifier("habit-counter.desktop-widget")
        window.backgroundColor = .clear; window.isOpaque = false; window.hasShadow = true
        window.hidesOnDeactivate = false; window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.delegate = self
        let host = NSHostingView(rootView: DesktopWidgetView(controller: self))
        // Explicit bounds prevent SwiftUI/AppKit intrinsic-size feedback on timer updates.
        host.sizingOptions = []; host.frame = NSRect(x: 0, y: 0, width: 320, height: 410)
        window.contentView = host
        panel = window
    }
    private func applyLevel() {
        panel?.level = pinned ? .floating : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    }
    func placePanel() {
        guard let panel, let primary = NSScreen.main ?? NSScreen.screens.first else { return }
        let width = panel.frame.width, height = panel.frame.height
        let proposed = NSPoint(x: defaults.object(forKey: prefix + "x") as? Double ?? primary.visibleFrame.maxX - width - 24,
                               y: defaults.object(forKey: prefix + "y") as? Double ?? primary.visibleFrame.maxY - height - 24)
        let rect = NSRect(origin: proposed, size: panel.frame.size)
        let screen = NSScreen.screens.max { a, b in
            let ai = a.visibleFrame.intersection(rect), bi = b.visibleFrame.intersection(rect)
            return (ai.isNull ? 0 : ai.width * ai.height) < (bi.isNull ? 0 : bi.width * bi.height)
        } ?? primary
        let bounds = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        let origin = NSPoint(x: max(bounds.minX, min(proposed.x, bounds.maxX - width)), y: max(bounds.minY, min(proposed.y, bounds.maxY - height)))
        positioning = true; panel.setFrameOrigin(origin); positioning = false
    }
    func windowDidMove(_ notification: Notification) {
        guard !positioning else { return }
        moveSave?.cancel()
        let save = DispatchWorkItem { [weak self] in
            guard let self, let origin = self.panel?.frame.origin else { return }
            self.defaults.set(origin.x, forKey: self.prefix + "x"); self.defaults.set(origin.y, forKey: self.prefix + "y")
        }
        moveSave = save; DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: save)
    }
    func open(_ action: String) {
        DesktopCounter.shared.showMain?(); NSApplication.shared.activate(ignoringOtherApps: true)
        DesktopCounter.shared.command(action)
    }
    func toggleFocus() {
        do { let timer = PomodoroEngine.shared; if timer.record.status == "running" { try timer.pause() } else { try timer.start() } }
        catch { open("tasks") }
    }
    func focus(_ task: [String: Any]) {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        do { try PomodoroEngine.shared.focusTask(id: task["id"] as? String ?? "", date: formatter.string(from: Date()), title: task["title"] as? String ?? "") }
        catch { open("tasks") }
    }
    func updateDock() {
        let timer = PomodoroEngine.shared
        let tasks = DesktopCounter.shared.plan(at: Date())["tasks"] as? [[String: Any]] ?? []
        let remaining = tasks.filter { $0["done"] as? Bool != true }.count
        let label: String? = !dockEnabled ? nil : timer.record.status == "running" ? "\(max(1, Int(ceil(Double(timer.remaining) / 60))))m" : timer.record.status == "paused" ? "Ⅱ" : timer.record.status == "completed" ? "✓" : remaining > 0 ? "\(remaining)" : nil
        // Minute precision is legible in the Dock and avoids redrawing its icon every second.
        if NSApplication.shared.dockTile.badgeLabel != label { NSApplication.shared.dockTile.badgeLabel = label }
    }
    func dockMenu() -> NSMenu {
        let menu = NSMenu()
        func item(_ title: String, _ selector: Selector) {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: ""); item.target = self; menu.addItem(item)
        }
        item("Open Tasks & Focus", #selector(openTasks))
        item(PomodoroEngine.shared.record.status == "running" ? "Pause focus" : PomodoroEngine.shared.record.status == "paused" ? "Resume focus" : "Start next interval", #selector(dockFocus))
        menu.addItem(.separator())
        item(visible ? "Hide mini panel" : "Show mini panel", #selector(dockWidget))
        item("Write today's summary", #selector(openSummary))
        return menu
    }
    @objc private func openTasks() { open("tasks") }
    @objc private func openSummary() { open("summary") }
    @objc private func dockFocus() { toggleFocus() }
    @objc private func dockWidget() { setVisible(!visible) }
}

final class DesktopWidgetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct DesktopWidgetView: View {
    @ObservedObject var controller: DesktopWidgetController
    @ObservedObject private var counter = DesktopCounter.shared
    @ObservedObject private var timer = PomodoroEngine.shared
    private let muted = Color.white.opacity(0.52)
    private var tasks: [[String: Any]] { counter.plan(at: counter.now)["tasks"] as? [[String: Any]] ?? [] }
    private var unfinished: [[String: Any]] {
        let pending = tasks.filter { $0["done"] as? Bool != true }
        return pending.filter { $0["priority"] as? Bool == true } + pending.filter { $0["priority"] as? Bool != true }
    }
    private var completed: Int { tasks.count - unfinished.count }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "scope").font(.system(size: 14, weight: .medium))
                Text("FocoNow").font(.system(size: 12, weight: .medium))
                Spacer(minLength: 0)
                icon(controller.pinned ? "pin.fill" : "pin", controller.pinned ? "Keep on desktop" : "Keep above windows") { controller.setPinned(!controller.pinned) }
                icon("xmark", "Hide widget") { controller.setVisible(false) }
            }
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(counter.now.formatted(.dateTime.weekday(.wide))).font(.system(size: 23, weight: .semibold))
                    Text(counter.now.formatted(.dateTime.month(.wide).day())).font(.system(size: 11)).foregroundStyle(muted)
                }
                Spacer()
                Button { controller.open("planner") } label: {
                    Label("My Day", systemImage: "arrow.up.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(muted)
                }.buttonStyle(.plain).help("Open My Day")
            }
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    Text(timer.record.phase == "work" ? "TIME TO FOCUS" : timer.record.phase == "long" ? "LONG BREAK" : "TAKE A BREATHER").font(.system(size: 9, weight: .semibold)).tracking(1.7).foregroundStyle(muted)
                    Spacer()
                    if timer.record.status == "paused" { Text("PAUSED").font(.system(size: 9)).foregroundStyle(muted) }
                    if timer.record.status == "completed" { Text("DONE").font(.system(size: 9)).foregroundStyle(muted) }
                }
                HStack(alignment: .center) {
                    Text(timer.displayTime).font(.system(size: 48, weight: .light, design: .rounded)).monospacedDigit().minimumScaleFactor(0.7).lineLimit(1)
                    Spacer(minLength: 6)
                    Button { controller.toggleFocus() } label: {
                        Image(systemName: timer.record.status == "running" ? "pause.fill" : "play.fill")
                            .font(.system(size: 17, weight: .semibold)).frame(width: 46, height: 46).background(.white, in: Circle()).foregroundStyle(.black)
                    }.buttonStyle(.plain).help(timer.record.status == "running" ? "Pause timer" : timer.record.status == "paused" ? "Resume timer" : "Start interval")
                    .accessibilityLabel(timer.record.status == "running" ? "Pause timer" : "Start or resume timer")
                }
                Text(timer.record.taskTitle.isEmpty ? "One thing at a time." : timer.record.taskTitle).font(.system(size: 11)).foregroundStyle(muted).lineLimit(1)
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.1))
                        Capsule().fill(.white).frame(width: geometry.size.width * max(0, min(1, 1 - Double(timer.remaining) / Double(max(1, timer.record.duration)))))
                    }
                }.frame(height: 3)
            }.padding(16).background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.white.opacity(0.08)))
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("UP NEXT").font(.system(size: 9, weight: .semibold)).tracking(1.6).foregroundStyle(muted)
                    Spacer()
                    Button("\(completed)/\(tasks.count) done") { controller.open("tasks") }.font(.system(size: 10)).foregroundStyle(muted).buttonStyle(.plain)
                }
                if unfinished.isEmpty {
                    Button { controller.open("tasks") } label: {
                        Label(tasks.isEmpty ? "Choose your first task" : "All done. Make room for you.", systemImage: tasks.isEmpty ? "plus.circle" : "checkmark.circle")
                            .font(.system(size: 12)).frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                    }.buttonStyle(.plain)
                } else {
                    ForEach(Array(unfinished.prefix(2).enumerated()), id: \.offset) { _, task in
                        Button { controller.focus(task) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "play.circle").font(.system(size: 16)).foregroundStyle(muted)
                                Text(task["title"] as? String ?? "Task").font(.system(size: 12)).lineLimit(1)
                                Spacer(minLength: 0)
                            }.frame(height: 24).contentShape(Rectangle())
                        }.buttonStyle(.plain).help("Focus on this task")
                    }
                    if unfinished.count == 1 { Spacer().frame(height: 10) }
                }
            }
            Spacer(minLength: 0)
            Button { controller.open("tasks") } label: {
                HStack { Text("Open your space"); Spacer(); Image(systemName: "arrow.up.right") }.font(.system(size: 11, weight: .medium)).foregroundStyle(muted)
            }.buttonStyle(.plain)
        }.padding(20).frame(width: 320, height: 410).foregroundStyle(.white)
            .background(Color(red: 0.025, green: 0.025, blue: 0.025), in: RoundedRectangle(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(Color.white.opacity(0.14)))
            .preferredColorScheme(.dark)
    }
    private func icon(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(muted).frame(width: 24, height: 24).contentShape(Rectangle()) }
            .buttonStyle(.plain).help(title).accessibilityLabel(title)
    }
}
#endif
