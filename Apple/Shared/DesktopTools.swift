#if os(macOS)
import SwiftUI
import AppKit
import ServiceManagement
import UserNotifications
import WebKit

extension Notification.Name {
    static let habitCounterCommand = Notification.Name("HabitCounterCommand")
}

/// The menu bar reads the same successful saves as the main window; it never edits disk independently.
final class DesktopCounter: ObservableObject {
    static let shared = DesktopCounter()
    @Published private(set) var state: [String: Any]?
    @Published var now = Date()
    var pendingAction: String?
    var showMain: (() -> Void)?
    private var observer: NSObjectProtocol?

    private init() {
        state = NativeStore().state
        observer = NotificationCenter.default.addObserver(forName: NativeStore.didSave, object: nil, queue: .main) { [weak self] notification in
            self?.state = notification.userInfo?["state"] as? [String: Any]
        }
    }
    var active: [String: Any]? {
        let habits = state?["habits"] as? [[String: Any]] ?? []
        return habits.first { $0["id"] as? String == state?["activeId"] as? String } ?? habits.first
    }
    func days(at date: Date) -> Int {
        guard let start = active?["startedAt"] as? Double else { return 0 }
        return max(0, Int((date.timeIntervalSince1970 - start / 1000) / 86400))
    }
    func command(_ action: String) {
        pendingAction = action
        NotificationCenter.default.post(name: .habitCounterCommand, object: nil, userInfo: ["action": action])
    }
}

struct DesktopMenu: View {
    @ObservedObject var counter: DesktopCounter
    @ObservedObject private var preferences = DesktopPreferences.shared
    @ObservedObject private var pomodoro = PomodoroEngine.shared
    @ObservedObject private var widget = DesktopWidgetController.shared
    var onRun: (String) -> Void
    @AppStorage("habit-counter.menu-bar.show-days") private var showDays = false

    var body: some View {
        Group {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Label("Your day, within reach", systemImage: "circle.dotted.circle").font(.headline)
                    Spacer()
                    Button { run("settings") } label: { Image(systemName: "gearshape") }.buttonStyle(.plain).help("Settings")
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(pomodoro.displayTime).font(.system(size: 38, weight: .light, design: .rounded)).monospacedDigit()
                        Spacer()
                        Text(pomodoro.record.phase == "work" ? "FOCUS" : "BREAK").font(.caption2).foregroundStyle(.secondary)
                    }
                    if !pomodoro.record.taskTitle.isEmpty { Text(pomodoro.record.taskTitle).font(.caption).lineLimit(2).foregroundStyle(.secondary) }
                    HStack {
                        Button(pomodoro.record.status == "running" ? "Pause" : pomodoro.record.status == "paused" ? "Resume" : pomodoro.record.status == "completed" ? "Next interval" : "Start focus") {
                            do { if pomodoro.record.status == "running" { try pomodoro.pause() } else { try pomodoro.start() } } catch { run("tasks") }
                        }.buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
                        Button("Open Tasks & Focus") { run("tasks") }.buttonStyle(.bordered)
                    }.controlSize(.small)
                    if let error = pomodoro.storageError { Text(error).font(.caption2).foregroundStyle(.secondary) }
                }
                Divider()
                let plan = counter.plan(at: counter.now)
                let tasks = plan["tasks"] as? [[String: Any]] ?? []
                let done = tasks.filter { $0["done"] as? Bool == true }.count
                VStack(alignment: .leading, spacing: 8) {
                    Text(counter.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())).font(.caption).foregroundStyle(.secondary)
                    Text((plan["focus"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "What matters today?")
                        .font(.system(size: 23, weight: .medium)).lineLimit(3)
                    Text("\(done) of \(tasks.count) tasks complete").font(.caption).foregroundStyle(.secondary)
                    ProgressView(value: tasks.isEmpty ? 0 : Double(done) / Double(tasks.count)).tint(.white)
                }
                HStack(spacing: 8) {
                    action("My tasks", "checklist", "tasks")
                    action("Summary", "square.and.pencil", "summary")
                    action("Breathe", "wind", "breathe")
                }
                Button { run("morning") } label: { HStack { Text("Plan my morning"); Spacer(); Image(systemName: "arrow.up.right") }.padding(7) }
                    .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
                HStack {
                    Image(systemName: (plan["summarySavedAt"] as? Double ?? 0) > 0 ? "checkmark.circle.fill" : "square.and.pencil")
                    Text((plan["summarySavedAt"] as? Double ?? 0) > 0 ? "Today's summary is saved" : "A few words about today are waiting")
                }.font(.caption).foregroundStyle(.secondary)
                if showDays, counter.active != nil {
                    Divider()
                    Button { run("overview") } label: {
                        HStack { Image(systemName: "flame"); Text("\(counter.days(at: counter.now)) days & counting"); Spacer(); Image(systemName: "arrow.up.right") }
                    }.buttonStyle(.plain).font(.caption)
                }
                Divider()
                Button { widget.setVisible(!widget.visible) } label: {
                    Label(widget.visible ? "Hide mini panel" : "Show mini panel", systemImage: "rectangle.inset.filled")
                }.buttonStyle(.bordered).font(.caption)
                Toggle("Show bad habit streak in menu bar", isOn: $showDays).font(.caption)
                Toggle("Open at login", isOn: Binding(get: { preferences.enabled }, set: { preferences.setEnabled($0) })).font(.caption)
                if preferences.requiresApproval {
                    Button("Approve in Login Items…") { SMAppService.openSystemSettingsLoginItems() }.font(.caption)
                }
                if let message = preferences.message { Text(message).font(.caption2).foregroundStyle(.secondary) }
                HStack {
                    Text("Runs here when the window is closed").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Button("Quit") { NSApplication.shared.terminate(nil) }.buttonStyle(.plain).font(.caption)
                }
            }.padding(22).frame(width: 350).background(Color.black).foregroundStyle(.white)
        }.onAppear { preferences.refresh() }.preferredColorScheme(.dark)
    }
    private func action(_ title: String, _ icon: String, _ command: String) -> some View {
        Button { run(command) } label: {
            VStack(spacing: 8) { Image(systemName: icon).font(.title3); Text(title).font(.caption) }
                .frame(maxWidth: .infinity).padding(.vertical, 10)
        }.buttonStyle(.bordered)
    }
    private func run(_ action: String) {
        onRun(action)
    }
}

extension DesktopCounter {
    func plan(at date: Date) -> [String: Any] {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        return (state?["planner"] as? [String: [String: Any]])?[formatter.string(from: date)] ?? [:]
    }
}

/// A fixed bitmap in AppKit avoids SwiftUI's menu-label layout feedback during launch.
final class DesktopStatusController: NSObject {
    private(set) var item: NSStatusItem
    private(set) var popover: NSPopover?
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?

    override init() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        if let button = item.button {
            button.image = Self.icon()
            button.imagePosition = .imageLeading
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            button.target = self
            button.action = #selector(toggle)
            button.toolTip = "FocoNow — your daily planner"
            button.setAccessibilityLabel("FocoNow")
        }
        for name in [NativeStore.didSave, UserDefaults.didChangeNotification, PomodoroEngine.didUpdate] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                DispatchQueue.main.async { self?.updateTitle() }
            })
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            DesktopCounter.shared.now = Date()
            self?.updateTitle()
        }
        updateTitle()
    }
    deinit {
        timer?.invalidate()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        NSStatusBar.system.removeStatusItem(item)
    }
    private static func icon() -> NSImage? {
        guard let context = CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setStrokeColor(CGColor(gray: 1, alpha: 1))
        context.setLineWidth(2.5)
        context.strokeEllipse(in: CGRect(x: 4, y: 4, width: 24, height: 24))
        context.setLineCap(.round)
        context.move(to: CGPoint(x: 10, y: 16)); context.addLine(to: CGPoint(x: 14, y: 12)); context.addLine(to: CGPoint(x: 23, y: 21)); context.strokePath()
        guard let bitmap = context.makeImage() else { return nil }
        let image = NSImage(cgImage: bitmap, size: NSSize(width: 16, height: 16))
        image.isTemplate = true
        return image
    }
    func updateTitle() {
        let value = UserDefaults.standard.object(forKey: "habit-counter.menu-bar.show-days") as? Bool ?? false
        let engine = PomodoroEngine.shared
        let title = engine.isActive ? " \(engine.displayTime)" : engine.record.status == "completed" ? " ✓" : value && DesktopCounter.shared.active != nil ? " \(DesktopCounter.shared.days(at: Date()))d" : ""
        if item.button?.title != title { item.button?.title = title }
    }
    @objc func toggle() {
        if popover?.isShown == true { popover?.performClose(nil) }
        else { show() }
    }
    func show() {
        guard let button = item.button else { return }
        if popover == nil {
            let popup = NSPopover()
            popup.behavior = .transient
            popup.animates = false
            let height = min(680, (NSScreen.main?.visibleFrame.height ?? 800) - 80)
            let controller = NSViewController()
            controller.view = NSView(frame: NSRect(x: 0, y: 0, width: 350, height: height))
            let hosting = NSHostingView(rootView: ScrollView {
                DesktopMenu(counter: DesktopCounter.shared, onRun: { [weak self] action in self?.run(action) })
            }.background(Color.black).preferredColorScheme(.dark))
            hosting.sizingOptions = []
            hosting.frame = controller.view.bounds
            hosting.autoresizingMask = [.width, .height]
            controller.view.addSubview(hosting)
            popup.contentViewController = controller
            popup.contentSize = controller.view.bounds.size
            popover = popup
        }
        DesktopCounter.shared.now = Date()
        popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
    func run(_ action: String) {
        popover?.performClose(nil)
        DesktopCounter.shared.showMain?()
        NSApplication.shared.activate(ignoringOtherApps: true)
        DesktopCounter.shared.command(action)
    }
}

final class DesktopPreferences: ObservableObject {
    static let shared = DesktopPreferences()
    @Published private(set) var enabled = false
    @Published private(set) var requiresApproval = false
    @Published private(set) var message: String?
    init() { refresh() }
    static func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }
    func refresh() {
        let status = SMAppService.mainApp.status
        let isEnabled = status == .enabled || status == .requiresApproval
        let needsApproval = status == .requiresApproval
        if enabled != isEnabled { enabled = isEnabled }
        if requiresApproval != needsApproval { requiresApproval = needsApproval }
    }
    @discardableResult func setEnabled(_ value: Bool) -> Bool {
        do {
            if value && SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            else if !value && SMAppService.mainApp.status != .notRegistered { try SMAppService.mainApp.unregister() }
            message = nil; refresh(); return true
        } catch {
            message = "Couldn’t change login settings. Move FocoNow to Applications, then try again."
            refresh(); return false
        }
    }
    var configuration: [String: Any] {
        return ["launchAtLogin": enabled, "requiresApproval": requiresApproval].merging(DesktopWidgetController.shared.configuration) { _, new in new }
    }
}

enum MacPermissionSetup {
    private static let completionKey = "habit-counter.mac-permissions-introduced"
    private static let stepKey = "habit-counter.mac-permission-setup-step"
    private static var diagnosticCompleted = false
    private static var diagnosticStep = 0

    static var isDiagnostic: Bool { DesktopLaunchCheck.directory != nil }
    static var shouldShow: Bool {
        if isDiagnostic {
            return CommandLine.arguments.contains("--show-permission-setup") && !diagnosticCompleted
        }
        return !UserDefaults.standard.bool(forKey: completionKey)
    }
    static var step: Int {
        let value = isDiagnostic ? diagnosticStep : UserDefaults.standard.integer(forKey: stepKey)
        return (0...2).contains(value) ? value : 0
    }
    static func advance(to step: Int) {
        guard shouldShow, (0...2).contains(step) else { return }
        if isDiagnostic { diagnosticStep = step }
        else { UserDefaults.standard.set(step, forKey: stepKey) }
    }
    static func finish() {
        if isDiagnostic { diagnosticCompleted = true }
        else {
            UserDefaults.standard.set(true, forKey: completionKey)
            UserDefaults.standard.removeObject(forKey: stepKey)
        }
    }
    static func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
    static func status(checkSyncedAccess: Bool, _ completion: @escaping ([String: Any]) -> Void) {
        if isDiagnostic {
            var status: [String: Any] = ["type": "permissionStatus", "notifications": "available", "timerAlerts": false,
                                         "accessibility": false, "launchAtLogin": false, "loginApproval": false]
            if checkSyncedAccess { status["syncedAccess"] = SyncedScreenTimeAccess.accessible.rawValue }
            completion(status)
            return
        }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                let status: String
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral: status = "allowed"
                case .denied: status = "denied"
                case .notDetermined: status = "available"
                @unknown default: status = "available"
                }
                let login = DesktopPreferences.shared
                login.refresh()
                let result: [String: Any] = ["type": "permissionStatus", "notifications": status,
                                             "timerAlerts": PomodoroEngine.shared.record.settings.notifications,
                                             "accessibility": SettingsScreenTimeReader.trusted,
                                             "launchAtLogin": login.enabled, "loginApproval": login.requiresApproval]
                guard checkSyncedAccess else { completion(result); return }
                DispatchQueue.global(qos: .utility).async {
                    let access = IPhoneScreenTimeReader().checkAccess()
                    DispatchQueue.main.async {
                        completion(result.merging(["syncedAccess": access.rawValue]) { _, access in access })
                    }
                }
            }
        }
    }
}

final class DesktopLifecycle: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var statusController: DesktopStatusController?
    private var launchCheck: DesktopLaunchCheck?
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        statusController = DesktopStatusController()
        DesktopWidgetController.shared.restore()
        WidgetPublisher.shared.schedule()
        if let directory = DesktopLaunchCheck.directory, let statusController {
            launchCheck = DesktopLaunchCheck(directory: directory, status: statusController)
            launchCheck?.start()
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        DesktopCounter.shared.showMain?()
        return true
    }
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? { DesktopWidgetController.shared.dockMenu() }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async {
            DesktopCounter.shared.showMain?()
            NSApplication.shared.activate(ignoringOtherApps: true)
            DesktopCounter.shared.command(response.notification.request.content.userInfo["habitAction"] as? String ?? "planner")
            completionHandler()
        }
    }
}

/// Explicit command-line diagnostics exercise the actual release app without using personal records.
final class DesktopLaunchCheck {
    static var directory: URL? {
        guard let index = CommandLine.arguments.firstIndex(of: "--startup-check"), CommandLine.arguments.count > index + 1 else { return nil }
        let path = CommandLine.arguments[index + 1]
        guard path.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
    private let directory: URL
    private let status: DesktopStatusController
    private var checks: [String] = []
    private var attempts = 0
    init(directory: URL, status: DesktopStatusController) { self.directory = directory; self.status = status }
    func start() {
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { fail("Could not create diagnostic directory"); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.waitForWindow { window, web in self.checkLaunch(window, web) } }
    }
    private func webView(in view: NSView) -> WKWebView? {
        if let web = view as? WKWebView { return web }
        for child in view.subviews { if let web = webView(in: child) { return web } }
        return nil
    }
    private func waitForWindow(_ next: @escaping (NSWindow, WKWebView) -> Void) {
        for window in NSApplication.shared.windows where window.isVisible {
            if let view = window.contentView, let web = webView(in: view) {
                web.evaluateJavaScript("document.querySelector('.local-chip')?.textContent === 'Saved on this Mac'") { value, _ in
                    if value as? Bool == true { self.attempts = 0; next(window, web) }
                    else { self.retry(next) }
                }
                return
            }
        }
        retry(next)
    }
    private func retry(_ next: @escaping (NSWindow, WKWebView) -> Void) {
        attempts += 1
        guard attempts < 50 else { fail("Actual release window did not become responsive"); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.waitForWindow(next) }
    }
    private func checkLaunch(_ window: NSWindow, _ web: WKWebView) {
        guard status.item.button?.image != nil else { fail("Native menu bar icon is missing"); return }
        checks.append("Release app launches with a visible responsive planner and a native menu bar icon")
        web.evaluateJavaScript("""
        document.querySelector('#day-focus').value='Release startup check';document.querySelector('#day-focus').dispatchEvent(new Event('input'));
        document.querySelector('#new-task').value='Launch verification task';document.querySelector('#add-task-form').requestSubmit();
        document.querySelector('#day-summary').value='The complete app opens and saves correctly.';document.querySelector('#day-summary').dispatchEvent(new Event('input'));document.querySelector('#finish-day').click();
        """) { _, error in
            guard error == nil else { self.fail("Actual release planner could not save test records"); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.status.show()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    guard self.status.popover?.isShown == true else { self.fail("Native menu bar panel did not open"); return }
                    self.checks.append("Real menu bar panel opens without the SwiftUI menu-label startup path")
                    self.status.popover?.performClose(nil)
                    window.performClose(nil)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        guard NSApplication.shared.isRunning, self.status.item.button != nil else { self.fail("Closing the window removed the running menu bar app"); return }
                        self.checks.append("Closing the main window leaves the app running")
                        self.status.run("summary")
                        self.waitForWindow { _, reopened in self.checkReopen(reopened) }
                    }
                }
            }
        }
    }
    private func checkReopen(_ web: WKWebView) {
        web.evaluateJavaScript("document.querySelector('#day-focus')?.value === 'Release startup check' && document.querySelector('#day-summary')?.value === 'The complete app opens and saves correctly.' && document.querySelectorAll('.task-row').length === 1 && document.activeElement?.id === 'day-summary'") { value, _ in
            guard value as? Bool == true else { self.fail("Menu bar did not reopen the saved planner at its daily summary"); return }
            self.checks.append("Menu bar reopens the daily summary with saved target, tasks, and writing intact")
            self.checkTasks(web)
        }
    }
    private func checkTasks(_ web: WKWebView) {
        status.run("tasks")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            web.evaluateJavaScript("""
            if(document.querySelector('#tasks-view').hidden || !document.querySelector('#planner-view').hidden) throw new Error('Tasks were not separated');
            const taskInput=document.querySelector('#new-task');taskInput.focus();if(getComputedStyle(taskInput).outlineStyle!=='none'||getComputedStyle(taskInput).borderTopWidth!=='0px')throw new Error('Inner task input still has a boxed focus outline');
            document.querySelector('[data-edit-task]').click();document.querySelector('#edit-task-notes').value='A clear first step';document.querySelector('#edit-task-estimate').value='3';document.querySelector('#edit-task-form').requestSubmit();
            document.querySelector('#task-search').value='clear first';document.querySelector('#task-search').dispatchEvent(new Event('input'));
            document.querySelectorAll('.task-row').length === 1
            """) { found, error in
                guard found as? Bool == true, error == nil else { self.fail("Dedicated tasks page, notes, estimates or search failed"); return }
                self.checks.append("Tasks have a separate page with editable notes, estimates, and search")
                web.evaluateJavaScript("document.querySelector('#task-search').value='';document.querySelector('#task-search').dispatchEvent(new Event('input'));document.querySelector('#pomo-settings').click();const workInput=document.querySelector('#pomo-setting-work');const before=Number(workInput.value);workInput.parentElement.querySelectorAll('.stepper-button')[1].click();if(Number(workInput.value)!==before+1)throw new Error('Number stepper failed');const picker=document.querySelector('#pomo-setting-every').parentElement.querySelector('.select-trigger');picker.click();if(!document.querySelector('.select-menu'))throw new Error('Custom dropdown did not open');picker.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',bubbles:true}));if(!document.querySelector('#modal').open||document.querySelector('.select-menu'))throw new Error('Escape closed the dialog or left its dropdown open');picker.click();for(const key of ['Home','ArrowDown','Enter'])picker.dispatchEvent(new KeyboardEvent('keydown',{key,bubbles:true}));if(document.querySelector('#pomo-setting-every').value!=='3')throw new Error('Keyboard dropdown selection failed');document.querySelector('#pomo-setting-work').value='30';document.querySelector('#pomo-setting-short').value='6';document.querySelector('#pomo-setting-long').value='20';document.querySelector('#pomo-setting-every').value='3';document.querySelector('#pomo-settings-form').requestSubmit();document.querySelector('[data-focus-task]').click()") { _, _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        guard PomodoroEngine.shared.record.status == "running", !PomodoroEngine.shared.record.taskId.isEmpty else { self.fail("Task did not start the native Pomodoro"); return }
                        guard PomodoroEngine.shared.record.settings.work == 30, PomodoroEngine.shared.record.settings.every == 3 else { self.fail("Custom Pomodoro durations did not reach native storage"); return }
                        self.checks.append("Inputs have no inner focus box; custom dropdown keyboard selection and Escape preserve form behavior; number steppers work")
                        self.checks.append("Custom Pomodoro settings save through the real interface")
                        self.checks.append("A task starts a real native Pomodoro session")
                        let remaining = PomodoroEngine.shared.remaining
                        web.window?.performClose(nil)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            guard PomodoroEngine.shared.record.status == "running", PomodoroEngine.shared.remaining < remaining else { self.fail("Closing the window interrupted the timer"); return }
                            self.checks.append("Pomodoro keeps counting after the main window closes")
                            self.status.run("tasks")
                            self.waitForWindow { _, reopened in
                                reopened.evaluateJavaScript("document.querySelector('#pomo-start').click()") { _, _ in
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                        guard PomodoroEngine.shared.record.status == "paused" else { self.fail("Reopened timer could not pause"); return }
                                        self.checks.append("Reopening Tasks restores the active timer and pause control")
                                        self.checkFocusInsights(reopened)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    private func checkFocusInsights(_ web: WKWebView) {
        guard let spans = PomodoroEngine.shared.record.focusSpans, spans.reduce(0, { $0 + $1.end-$1.start }) > 1000 else { fail("Partial focus time was not saved after closing and reopening the window"); return }
        for name in ["FocusFinished", "BreakFinished"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "WebContent"), NSSound(contentsOf: url, byReference: false) != nil else { fail("Bundled completion alarm cannot be decoded"); return }
        }
        checks.append("Distinct bundled focus and break alarms decode successfully without network or notification permissions")
        web.evaluateJavaScript("location.hash='insights'") { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                web.evaluateJavaScript("document.querySelectorAll('[data-focus-day]').length === 7 && document.querySelector('#insight-total').textContent !== '0m' && document.querySelector('#focus-session-count').textContent === '0'") { result, _ in
                    guard result as? Bool == true else { self.fail("Real partial focus was not reflected in Insights"); return }
                    self.checks.append("Insights displays saved unfinished focus time without inventing a completed session")
                    self.checkPhoneImport(web)
                }
            }
        }
    }
    private func checkPhoneImport(_ web: WKWebView) {
        web.evaluateJavaScript("location.hash='phone'") { _, _ in
            DispatchQueue.main.asyncAfter(deadline:.now()+0.5) {
                web.evaluateJavaScript("!document.querySelector('#phone-view').hidden && !document.querySelector('#phone-access-settings').hidden && document.querySelector('#phone-data').hidden && document.querySelector('#phone-import-error').value.includes('No personal Apple records')") { value, _ in
                    guard value as? Bool == true else { self.fail("The iPhone permission screen did not become ready"); return }
                    guard PomodoroEngine.shared.record.status == "paused" else { self.fail("iPhone import changed the focus timer"); return }
                    self.checks.append("The iPhone permission screen is responsive; diagnostics exclude personal Apple files; Pomodoro remains unchanged")
                    self.checkDesktopWidget(web)
                }
            }
        }
    }
    private func checkDesktopWidget(_ web: WKWebView) {
        web.evaluateJavaScript("document.querySelector('#new-task').value='A second task with a longer title that should stay inside the compact desktop widget';document.querySelector('#add-task-form').requestSubmit();document.querySelector('#settings-button').click();document.querySelector('#desktop-widget-visible').click()") { _, error in
            guard error == nil else { self.fail("Desktop widget settings did not render"); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let widget = DesktopWidgetController.shared
                guard let panel = widget.panel, panel.isVisible, !panel.canBecomeKey, !panel.canBecomeMain,
                      panel.level.rawValue < NSWindow.Level.normal.rawValue else { self.fail("Desktop widget did not open behind normal windows"); return }
                widget.setPinned(true)
                guard panel.level == .floating else { self.fail("Widget could not be pinned above windows"); return }
                widget.setPinned(false)
                for _ in 0..<5 { widget.setVisible(false); widget.setVisible(true) }
                guard widget.panel === panel, panel.isVisible else { self.fail("Widget toggling lost its window"); return }
                widget.resetPosition()
                guard NSScreen.screens.contains(where: { $0.visibleFrame.contains(panel.frame) }) else { self.fail("Desktop widget was placed off screen"); return }
                self.checks.append("Desktop settings show a bounded native widget; pinning, repeated show/hide, and position reset work")
                widget.updateDock()
                guard NSApplication.shared.dockTile.badgeLabel == "Ⅱ" else { self.fail("Dock did not reflect the paused timer"); return }
                widget.setDockEnabled(false)
                guard NSApplication.shared.dockTile.badgeLabel == nil else { self.fail("Dock badge could not be disabled"); return }
                widget.setDockEnabled(true)
                web.window?.performClose(nil)
                self.pressWidgetTimer(panel)
                let remaining = PomodoroEngine.shared.remaining
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    guard panel.isVisible, PomodoroEngine.shared.record.status == "running", PomodoroEngine.shared.remaining < remaining,
                          NSApplication.shared.dockTile.badgeLabel?.hasSuffix("m") == true else { self.fail("Widget timer or Dock countdown stopped with the main window closed"); return }
                    self.pressWidgetTimer(panel)
                    guard PomodoroEngine.shared.record.status == "paused" else { self.fail("Widget's timer button could not pause focus"); return }
                    if let view = panel.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                        view.cacheDisplay(in: view.bounds, to: bitmap)
                        if let png = bitmap.representation(using: .png, properties: [:]) { try? png.write(to: self.directory.appendingPathComponent("desktop-widget.png")) }
                    }
                    do { try PomodoroEngine.shared.reset() } catch { self.fail("Widget focus session could not reset"); return }
                    widget.updateDock()
                    guard NSApplication.shared.dockTile.badgeLabel == "2", widget.dockMenu().items.count >= 4 else { self.fail("Dock did not return to remaining tasks or expose quick actions"); return }
                    self.checks.append("Widget starts and pauses the shared timer with the window closed; Dock switches between countdown, pause, and task count and can be turned off")
                    guard WidgetPublisher.shared.publish(), let summary = WidgetSummary.read(NativeStore().directory.appendingPathComponent(WidgetSummary.filename)), summary.taskCount == 2, summary.completedTasks == 0 else { self.fail("Native WidgetKit summary did not follow the saved tasks"); return }
                    guard let plugin = Bundle.main.builtInPlugInsURL?.appendingPathComponent("HabitCounterWidgets.appex"), FileManager.default.fileExists(atPath: plugin.appendingPathComponent("Contents/MacOS/HabitCounterWidgets").path) else { self.fail("Native macOS widget extension was not embedded in the app"); return }
                    self.checks.append("WidgetKit extension is embedded; its read-only summary follows saved tasks and the shared focus timer")
                    widget.setVisible(false)
                    widget.open("tasks")
                    self.waitForWindow { _, reopened in
                        self.checks.append("Widget reopens the main app after it has been closed")
                        self.captureTasks(reopened)
                    }
                }
            }
        }
    }
    private func pressWidgetTimer(_ panel: NSPanel) {
        // Exercise the rendered SwiftUI button with local AppKit events; no system-wide input access.
        let point = NSPoint(x: 260, y: panel.frame.height - 184)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0) { NSApplication.shared.sendEvent(event) }
        }
    }
    private func captureTasks(_ web: WKWebView) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                web.takeSnapshot(with: nil) { snapshot, _ in
                    if let tiff = snapshot?.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) {
                        try? png.write(to: self.directory.appendingPathComponent("release-window.png"))
                    }
                    try? PomodoroEngine.shared.reset()
                    self.finish(passed: true)
                }
            }
    }
    private func fail(_ message: String) { checks.append(message); finish(passed: false) }
    private func finish(passed: Bool) {
        if let data = try? JSONSerialization.data(withJSONObject: ["passed": passed, "checks": checks], options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: directory.appendingPathComponent("release-launch-result.json"), options: .atomic)
            print(String(decoding: data, as: UTF8.self))
        }
        NSApplication.shared.terminate(nil)
    }
}

enum DesktopPlannerReminders {
    private static let identifiers = ["habit-counter.planner.morning", "habit-counter.planner.evening"]
    static var configuration: [String: Any] {
        ["enabled": UserDefaults.standard.bool(forKey: "habit-counter.planner-reminders.enabled"),
         "morning": UserDefaults.standard.string(forKey: "habit-counter.planner-reminders.morning") ?? "09:00",
         "evening": UserDefaults.standard.string(forKey: "habit-counter.planner-reminders.evening") ?? "21:00"]
    }
    static func requests(morning: String, evening: String) throws -> [UNNotificationRequest] {
        func components(_ time: String) throws -> DateComponents {
            let parts = time.split(separator: ":")
            guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]), (0...23).contains(hour), (0...59).contains(minute) else { throw CocoaError(.validationMissingMandatoryProperty) }
            return DateComponents(hour: hour, minute: minute)
        }
        return try [morning, evening].enumerated().map { index, time in
            let content = UNMutableNotificationContent()
            content.title = index == 0 ? "A little direction for today" : "A few words, just for you"
            content.body = index == 0 ? "Choose your main target and a few things to do." : "Pause and write a little about your day."
            content.userInfo = ["habitAction": index == 0 ? "morning" : "summary"]
            return UNNotificationRequest(identifier: identifiers[index], content: content, trigger: UNCalendarNotificationTrigger(dateMatching: try components(time), repeats: true))
        }
    }
    static func configure(enabled: Bool, morning: String, evening: String, completion: @escaping ([String: Any]) -> Void) {
        guard let pending = try? requests(morning: morning, evening: evening) else {
            completion(["type": "plannerReminders", "success": false, "configuration": configuration, "message": "Choose valid morning and evening times."]); return
        }
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            do {
                if enabled {
                    guard try await center.requestAuthorization(options: [.alert]) else { throw CocoaError(.userCancelled) }
                    for request in pending { try await center.add(request) }
                } else {
                    center.removePendingNotificationRequests(withIdentifiers: identifiers)
                    center.removeDeliveredNotifications(withIdentifiers: identifiers)
                }
                UserDefaults.standard.set(enabled, forKey: "habit-counter.planner-reminders.enabled")
                UserDefaults.standard.set(morning, forKey: "habit-counter.planner-reminders.morning")
                UserDefaults.standard.set(evening, forKey: "habit-counter.planner-reminders.evening")
                completion(["type": "plannerReminders", "success": true, "configuration": configuration])
            } catch {
                center.removePendingNotificationRequests(withIdentifiers: identifiers)
                UserDefaults.standard.set(false, forKey: "habit-counter.planner-reminders.enabled")
                completion(["type": "plannerReminders", "success": false, "configuration": configuration, "message": "Reminders are off. Allow FocoNow notifications in System Settings, then try again."])
            }
        }
    }
}
#endif
