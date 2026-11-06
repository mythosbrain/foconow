#if os(macOS)
import AppKit
import WidgetKit

/// Only the containing app writes this projection; the sandboxed widgets have read-only access.
final class WidgetPublisher {
    static let shared = WidgetPublisher()
    private var observers: [NSObjectProtocol] = []
    private var scheduled: DispatchWorkItem?
    private let store = NativeStore()
    private init() {
        for name in [NativeStore.didSave, PomodoroEngine.didUpdate, Notification.Name.NSCalendarDayChanged] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] event in
                guard event.userInfo?["clockOnly"] as? Bool != true else { return }
                self?.schedule()
            })
        }
    }
    func schedule() {
        scheduled?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.publish() }
        scheduled = item; DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }
    @discardableResult func publish() -> Bool {
        let current = NativeStore(directory: store.directory)
        guard current.loadError == nil else { return false }
        let summary = WidgetSummary.make(state: current.state, timer: PomodoroEngine.shared.snapshot)
        guard summary.valid else { return false }
        do {
            let url = store.directory.appendingPathComponent(WidgetSummary.filename)
            try JSONEncoder().encode(summary).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            if DesktopLaunchCheck.directory == nil { WidgetCenter.shared.reloadAllTimelines() }
            return true
        } catch { return false }
    }
}
#endif
