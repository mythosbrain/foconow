import SwiftUI
#if os(macOS)
import AppKit

@main
struct HabitCounterApp: App {
    @NSApplicationDelegateAdaptor(DesktopLifecycle.self) private var lifecycle
    @StateObject private var desktop = DesktopCounter.shared
    @AppStorage("habit-counter.desktop-appearance") private var appearance = "dark"
    private var selectedColorScheme: ColorScheme? {
        appearance == "dark" ? .dark : appearance == "light" ? .light : nil
    }
    var body: some Scene {
        Window("FocoNow", id: "main") {
            DesktopWindowContent()
                .frame(minWidth: 760, minHeight: 600)
                .preferredColorScheme(selectedColorScheme)
        }
        .defaultSize(width: 1280, height: 850)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Bad Habit…") { send("addHabit") }.keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Import Backup…") { send("import") }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                Button("Export Backup…") { send("export") }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { send("settings") }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(after: .sidebar) {
                Button("My Day") { send("planner") }.keyboardShortcut("4", modifiers: .command)
                Button("Tasks & Focus") { send("tasks") }.keyboardShortcut("5", modifiers: .command)
                Button("Show / Hide Mini Panel") { DesktopWidgetController.shared.setVisible(!DesktopWidgetController.shared.visible) }.keyboardShortcut("w", modifiers: [.command, .shift])
                Button("Start / Pause Pomodoro") { send("pomodoroToggle") }.keyboardShortcut("f", modifiers: [.command, .shift])
                Button("Plan My Morning…") { send("morning") }
                Button("Daily Summary…") { send("summary") }.keyboardShortcut("j", modifiers: [.command, .shift])
                Button("Bad Habits") { send("overview") }.keyboardShortcut("1", modifiers: .command)
                Button("My Journal") { send("journal") }.keyboardShortcut("2", modifiers: .command)
                Button("Insights") { send("insights") }.keyboardShortcut("3", modifiers: .command)
                Button("iPhone Screen Time") { send("phone") }.keyboardShortcut("6", modifiers: .command)
                Divider()
                Button("Quick Actions…") { send("quickActions") }.keyboardShortcut("k", modifiers: .command)
                Button("Check In…") { send("checkin") }.keyboardShortcut("d", modifiers: .command)
                Button("Write a Reflection…") { send("reflect") }.keyboardShortcut("n", modifiers: .command)
                Button("Log an Urge…") { send("urge") }.keyboardShortcut("u", modifiers: [.command, .shift])
                Button("Take a Breath…") { send("breathe") }.keyboardShortcut("b", modifiers: [.command, .shift])
            }
        }

    }

    private func send(_ action: String) {
        if action == "pomodoroToggle" {
            let timer = PomodoroEngine.shared
            do { if timer.record.status == "running" { try timer.pause() } else { try timer.start() } }
            catch { desktop.showMain?(); desktop.command("tasks") }
            return
        }
        desktop.command(action)
    }
}

private struct DesktopWindowContent: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        WebHost().onOpenURL { url in
            guard url.scheme == "habitcounter", let action = url.host, ["tasks", "overview", "planner"].contains(action) else { return }
            DesktopCounter.shared.showMain?()
            NSApplication.shared.activate(ignoringOtherApps: true)
            DesktopCounter.shared.command(action)
        }.onAppear {
            let action = openWindow
            DesktopCounter.shared.showMain = { action(id: "main") }
        }
    }
}
#else
@main
struct HabitCounterApp: App {
    @AppStorage("habit-counter.appearance") private var appearance = "system"
    private var selectedColorScheme: ColorScheme? {
        appearance == "dark" ? .dark : appearance == "light" ? .light : nil
    }
    var body: some Scene {
        WindowGroup {
            WebHost()
                .background(AppearanceBackground())
                .preferredColorScheme(selectedColorScheme)
        }
    }
}
#endif

private struct AppearanceBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        (colorScheme == .dark
            ? Color(red: 15/255, green: 22/255, blue: 18/255)
            : Color(red: 245/255, green: 244/255, blue: 239/255)).ignoresSafeArea()
    }
}
