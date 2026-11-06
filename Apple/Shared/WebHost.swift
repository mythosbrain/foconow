import SwiftUI
import WebKit
import UniformTypeIdentifiers
#if os(macOS)
import AppKit

struct WebHost: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "habitCounter")
        configuration.userContentController.addUserScript(WKUserScript(
            source: context.coordinator.bootstrapScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        context.coordinator.webView = webView
        if let directory = Bundle.main.resourceURL?.appendingPathComponent("WebContent"),
           FileManager.default.fileExists(atPath: directory.appendingPathComponent("index.html").path) {
            context.coordinator.contentDirectory = directory
            webView.loadFileURL(directory.appendingPathComponent("index.html"), allowingReadAccessTo: directory)
        } else {
            webView.loadHTMLString("<body style='background:#111613;color:#c2e9ac;font:18px system-ui;padding:40px'>FocoNow’s bundled files are missing. Please rebuild the app.</body>", baseURL: nil)
        }
        return webView
    }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "habitCounter")
        coordinator.stop()
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
        weak var webView: WKWebView?
        var contentDirectory: URL?
        private let store: NativeStore
        private lazy var phoneScreenTime = PhoneScreenTimeController.shared(store: store)
        private var commandObserver: NSObjectProtocol?
        private var pomodoroObserver: NSObjectProtocol?
        private var activeObserver: NSObjectProtocol?
        private var phoneSyncObserver: NSObjectProtocol?
        private var widgetObserver: NSObjectProtocol?
        private var ready = false
        private var permissionSetupStep: Int?
        private var permissionStatusRequest = 0

        init(store: NativeStore = NativeStore()) {
            self.store = store
            super.init()
            widgetObserver = NotificationCenter.default.addObserver(forName: DesktopWidgetController.didChange, object: nil, queue: .main) { [weak self] _ in
                self?.send(["type": "desktopPreferences", "preferences": DesktopPreferences.shared.configuration, "success": true])
            }
            phoneSyncObserver=NotificationCenter.default.addObserver(forName:PhoneScreenTimeController.didSync,object:phoneScreenTime,queue:.main){[weak self] event in
                guard let data=event.userInfo as? [String:Any] else{return};self?.send(data)
            }
            activeObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                guard self?.ready == true else { return }
                self?.send(["type":"phoneScreenTimeRefresh"])
                self?.sendPermissionStatus()
            }
            commandObserver = NotificationCenter.default.addObserver(forName: .habitCounterCommand, object: nil, queue: .main) { [weak self] notification in
                guard let self, let action = notification.userInfo?["action"] as? String else { return }
                if !self.ready { DesktopCounter.shared.pendingAction = action; return }
                DesktopCounter.shared.pendingAction = nil
                if action == "import" { self.importBackup() }
                else if action == "pomodoroToggle" { self.handlePomodoro(["operation": PomodoroEngine.shared.record.status == "running" ? "pause" : "start"]) }
                else { self.send(["type": "command", "action": action]) }
            }
            pomodoroObserver = NotificationCenter.default.addObserver(forName: PomodoroEngine.didUpdate, object: nil, queue: .main) { [weak self] event in
                let engine = PomodoroEngine.shared
                if event.userInfo?["clockOnly"] as? Bool == true { self?.send(["type": "pomodoroTick", "remaining": engine.remaining]) }
                else { self?.send(["type": "pomodoro", "snapshot": engine.snapshot]) }
            }
        }

        func stop() {
            if let widgetObserver { NotificationCenter.default.removeObserver(widgetObserver) }
            widgetObserver = nil
            if let commandObserver { NotificationCenter.default.removeObserver(commandObserver) }
            commandObserver = nil
            if let pomodoroObserver { NotificationCenter.default.removeObserver(pomodoroObserver) }
            pomodoroObserver = nil
            if let activeObserver { NotificationCenter.default.removeObserver(activeObserver) }
            activeObserver = nil
            if let phoneSyncObserver {NotificationCenter.default.removeObserver(phoneSyncObserver)}
            phoneSyncObserver=nil
        }
        deinit { stop() }

        var bootstrapScript: String {
            let data = (try? JSONSerialization.data(withJSONObject: store.bootstrap)) ?? Data("{}".utf8)
            let encoded = data.base64EncodedString()
            return """
            window.__HABIT_NATIVE__ = JSON.parse(new TextDecoder().decode(Uint8Array.from(atob('\(encoded)'), c => c.charCodeAt(0))));
            if (!crypto.randomUUID) crypto.randomUUID = function () {
              const bytes = crypto.getRandomValues(new Uint8Array(16)); bytes[6] = (bytes[6] & 15) | 64; bytes[8] = (bytes[8] & 63) | 128;
              const h = Array.from(bytes, b => b.toString(16).padStart(2, '0')).join('');
              return h.slice(0,8)+'-'+h.slice(8,12)+'-'+h.slice(12,16)+'-'+h.slice(16,20)+'-'+h.slice(20);
            };
            """
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, let url = message.frameInfo.request.url,
                  isBundledURL(url), let body = message.body as? [String: Any], let action = body["action"] as? String else { return }
            if action == "pomodoro" { handlePomodoro(body); return }
            if action == "permissionSetup", let operation = body["operation"] as? String {
                handlePermissionSetup(operation, step: body["step"] as? Int)
                return
            }
            if action == "phoneScreenTime" {
                phoneScreenTime.refresh { [weak self] event in self?.send(event) }
                return
            }
            if action == "phoneAccessSettings" { PhoneScreenTimeController.openAccessSettings(); return }
            if action == "phoneSettingsRead" { phoneScreenTime.readSettings { [weak self] event in self?.send(event) }; return }
            if action == "phoneSettingsImport" { phoneScreenTime.importSettings(days:body["days"] as? Int ?? 7){[weak self] event in self?.send(event)};return }
            if action == "phoneSettingsCancel" {phoneScreenTime.cancelSettingsImport();return}
            if action == "phoneSettingsAuto",let enabled=body["enabled"] as? Bool {phoneScreenTime.configureSettingsSync(enabled);return}
            if action == "phoneSettingsHistory" { phoneScreenTime.settingsHistory { [weak self] event in self?.send(event) }; return }
            if action == "phoneSettingsAccess" { SettingsScreenTimeReader.requestAccess(); return }
            if action == "phoneOpenSettings" { SettingsScreenTimeReader.openSettings(); return }
            if action == "reloadNativeWidgets" {
                let success = WidgetPublisher.shared.publish()
                send(["type": "notice", "message": success ? "Desktop widgets refresh requested." : "Couldn’t update the widgets. Your saved records are unchanged.", "error": !success])
                return
            }
            if action == "desktopWidget" {
                let widget = DesktopWidgetController.shared
                if let visible = body["visible"] as? Bool { widget.setVisible(visible) }
                if let pinned = body["pinned"] as? Bool { widget.setPinned(pinned) }
                if let badge = body["dockBadge"] as? Bool { widget.setDockEnabled(badge) }
                if body["resetPosition"] as? Bool == true { widget.resetPosition() }
                send(["type": "desktopPreferences", "preferences": DesktopPreferences.shared.configuration, "success": true])
                return
            }
            if action == "desktopPreferences" || action == "launchAtLogin" {
                let preferences = DesktopPreferences.shared
                preferences.refresh()
                let success = action != "launchAtLogin" || preferences.setEnabled(body["enabled"] as? Bool == true)
                refreshBootstrap()
                send(["type": "desktopPreferences", "preferences": preferences.configuration, "success": success, "message": success ? "" : preferences.message ?? "Couldn’t change login settings."])
                return
            }
            if action == "loginSettings" { DesktopPreferences.openLoginSettings(); return }
            if action == "plannerReminders", let enabled = body["enabled"] as? Bool, let morning = body["morning"] as? String, let evening = body["evening"] as? String {
                DesktopPlannerReminders.configure(enabled: enabled, morning: morning, evening: evening) { [weak self] event in
                    self?.refreshBootstrap(); self?.send(event)
                }
                return
            }
            if action == "reminder", let enabled = body["enabled"] as? Bool, let time = body["time"] as? String {
                DailyReminder.configure(enabled: enabled, time: time) { [weak self] event in
                    guard let self else { return }
                    if let controller = self.webView?.configuration.userContentController {
                        controller.removeAllUserScripts()
                        controller.addUserScript(WKUserScript(source: self.bootstrapScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
                    }
                    self.send(event)
                }
                return
            }
            if action == "recoveryList" {
                do { send(["type": "recoveryList", "copies": try store.recoveryCopies()]) }
                catch { send(["type": "notice", "message": "Couldn’t read recovery copies. You can still import an exported backup.", "error": true]) }
                return
            }
            if action == "recoveryOpen", let name = body["name"] as? String {
                do { send(["type": "import", "state": try store.recoveryCopy(named: name)]) }
                catch { send(["type": "notice", "message": "This recovery copy couldn’t be opened. Try another copy.", "error": true]) }
                return
            }
            if action == "appearance", let preference = body["preference"] as? String {
                store.setAppearance(preference)
                userContentController.removeAllUserScripts()
                userContentController.addUserScript(WKUserScript(source: bootstrapScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
                return
            }
            if action == "save", let state = body["state"] as? [String: Any] {
                do {
                    try store.save(state, replacingUnreadable: body["replaceUnreadable"] as? Bool == true)
                    // A WebKit reload must never replay a stale launch snapshot.
                    if let controller = webView?.configuration.userContentController {
                        controller.removeAllUserScripts()
                        controller.addUserScript(WKUserScript(source: bootstrapScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
                    }
                    send(["type": "saved", "success": true, "requestId": body["requestId"] ?? 0])
                    if let warning = store.recoveryWarning { send(["type": "notice", "message": warning, "error": true]) }
                } catch {
                    send(["type": "saved", "success": false, "requestId": body["requestId"] ?? 0, "error": "Couldn’t save to your Mac. Export a backup before closing."])
                }
            } else if action == "export", let state = body["state"] as? [String: Any] { exportBackup(state) }
            else if action == "import" { importBackup() }
        }

        private func isBundledURL(_ url: URL) -> Bool {
            guard url.isFileURL, let directory = contentDirectory else { return false }
            return url.standardizedFileURL.path.hasPrefix(directory.standardizedFileURL.path + "/")
        }

        private func handlePomodoro(_ body: [String: Any]) {
            let engine = PomodoroEngine.shared
            do {
                switch body["operation"] as? String {
                case "start": try engine.start()
                case "pause": try engine.pause()
                case "reset": try engine.reset()
                case "phase": try engine.choosePhase(body["phase"] as? String ?? "")
                case "task": try engine.selectTask(id: body["taskId"] as? String ?? "", date: body["taskDate"] as? String ?? "", title: body["taskTitle"] as? String ?? "")
                case "focusTask": try engine.focusTask(id: body["taskId"] as? String ?? "", date: body["taskDate"] as? String ?? "", title: body["taskTitle"] as? String ?? "")
                case "settings": try engine.configure(work: body["work"] as? Int ?? 0, short: body["short"] as? Int ?? 0, long: body["long"] as? Int ?? 0, every: body["every"] as? Int ?? 0)
                case "sounds": try engine.setSounds(body["enabled"] as? Bool == true)
                case "previewSound": engine.playAlarm(body["phase"] as? String ?? "work")
                case "notifications":
                    engine.setNotifications(body["enabled"] as? Bool == true) { [weak self] error in
                        self?.send(["type": "pomodoro", "snapshot": engine.snapshot, "error": error ?? ""])
                    }
                    return
                default: break
                }
                send(["type": "pomodoro", "snapshot": engine.snapshot])
            } catch { send(["type": "pomodoro", "snapshot": engine.snapshot, "error": error.localizedDescription]) }
        }

        private func refreshBootstrap() {
            guard let controller = webView?.configuration.userContentController else { return }
            controller.removeAllUserScripts()
            controller.addUserScript(WKUserScript(source: bootstrapScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            ready = true
            send(["type": "pomodoro", "snapshot": PomodoroEngine.shared.snapshot])
            if let action = DesktopCounter.shared.pendingAction {
                DesktopCounter.shared.pendingAction = nil
                if action == "import" { importBackup() }
                else { send(["type": "command", "action": action]) }
            }
        }

        func send(_ event: [String: Any]) {
            guard let data = try? JSONSerialization.data(withJSONObject: event) else { return }
            let encoded = data.base64EncodedString()
            let script = "window.dispatchEvent(new CustomEvent('habit-native-event', {detail: JSON.parse(new TextDecoder().decode(Uint8Array.from(atob('\(encoded)'), c => c.charCodeAt(0))))}));"
            webView?.evaluateJavaScript(script, completionHandler: nil)
        }

        private func sendPermissionStatus() {
            guard let permissionSetupStep else { return }
            permissionStatusRequest += 1
            let request = permissionStatusRequest
            MacPermissionSetup.status(checkSyncedAccess: permissionSetupStep == 2) { [weak self] status in
                guard let self, self.permissionSetupStep != nil, self.permissionStatusRequest == request else { return }
                self.send(status)
            }
        }

        private func handlePermissionSetup(_ operation: String, step: Int?) {
            switch operation {
            case "show":
                permissionSetupStep = step ?? 0
                sendPermissionStatus()
            case "dismiss":
                permissionSetupStep = nil
            case "progress":
                if let step {
                    MacPermissionSetup.advance(to: step)
                    refreshBootstrap()
                }
            case "finish":
                permissionSetupStep = nil
                MacPermissionSetup.finish()
                refreshBootstrap()
            default:
                guard !MacPermissionSetup.isDiagnostic else { return }
                switch operation {
                case "notifications":
                    PomodoroEngine.shared.setNotifications(true) { [weak self] error in
                        self?.sendPermissionStatus()
                        if let error { self?.send(["type": "notice", "message": error, "error": true]) }
                    }
                case "notificationSettings": MacPermissionSetup.openNotificationSettings()
                case "accessibility": SettingsScreenTimeReader.requestAccess()
                case "fullDiskAccess": PhoneScreenTimeController.openAccessSettings()
                case "launchAtLogin":
                    let preferences = DesktopPreferences.shared
                    if !preferences.setEnabled(true), let message = preferences.message {
                        send(["type": "notice", "message": message, "error": true])
                    }
                    sendPermissionStatus()
                case "loginSettings": DesktopPreferences.openLoginSettings()
                default: break
                }
            }
        }

        private func exportBackup(_ state: [String: Any]) {
            guard let window = webView?.window else { return }
            let panel = NSSavePanel()
            panel.title = "Export FocoNow Backup"
            panel.allowedContentTypes = [.json]
            let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
            panel.nameFieldStringValue = "foconow-\(formatter.string(from: Date())).json"
            panel.beginSheetModal(for: window) { [weak self] result in
                guard result == .OK, let url = panel.url else { return }
                do {
                    let data = try JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys])
                    try data.write(to: url, options: .atomic)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                    self?.send(["type": "notice", "message": "Your backup is saved."])
                } catch { self?.send(["type": "notice", "message": "Couldn’t export the backup. Try a different folder.", "error": true]) }
            }
        }

        private func importBackup() {
            guard let window = webView?.window else { return }
            let panel = NSOpenPanel()
            panel.title = "Import FocoNow Backup"
            panel.allowedContentTypes = [.json]
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.beginSheetModal(for: window) { [weak self] result in
                guard result == .OK, let url = panel.url else { return }
                do {
                    let attributes = try url.resourceValues(forKeys: [.fileSizeKey])
                    guard (attributes.fileSize ?? 0) <= 10 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
                    let data = try Data(contentsOf: url)
                    let value = try JSONSerialization.jsonObject(with: data)
                    self?.send(["type": "import", "state": value])
                } catch { self?.send(["type": "notice", "message": "This file isn’t a readable backup smaller than 10 MB.", "error": true]) }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
            // No remote sites are allowed to load inside the privileged native bridge.
            decisionHandler(isBundledURL(url) && navigationAction.targetFrame?.isMainFrame != false ? .allow : .cancel)
        }

        func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
            guard frame.isMainFrame, let window = webView.window else { completionHandler(nil); return }
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.json]
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.beginSheetModal(for: window) { completionHandler($0 == .OK ? panel.urls : nil) }
        }
    }
}
#else
import UIKit

struct WebHost: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "habitCounter")
        config.userContentController.addUserScript(WKUserScript(source: context.coordinator.bootstrapScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 15/255, green: 22/255, blue: 18/255, alpha: 1)
                : UIColor(red: 245/255, green: 244/255, blue: 239/255, alpha: 1)
        }
        view.underPageBackgroundColor = view.backgroundColor!
        view.scrollView.backgroundColor = view.backgroundColor
        context.coordinator.webView = view
        if let directory = Bundle.main.resourceURL?.appendingPathComponent("WebContent") {
            context.coordinator.directory = directory
            view.loadFileURL(directory.appendingPathComponent("index.html"), allowingReadAccessTo: directory)
        }
        return view
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "habitCounter")
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, UIDocumentPickerDelegate {
        weak var webView: WKWebView?
        var directory: URL?
        let store = NativeStore()
        private weak var focusHost: UIViewController?

        var bootstrapScript: String {
            let data = (try? JSONSerialization.data(withJSONObject: store.bootstrap)) ?? Data("{}".utf8)
            return """
            window.__HABIT_NATIVE__ = JSON.parse(new TextDecoder().decode(Uint8Array.from(atob('\(data.base64EncodedString())'), c => c.charCodeAt(0))));
            if (!crypto.randomUUID) crypto.randomUUID = function () {
              const b = crypto.getRandomValues(new Uint8Array(16)); b[6]=(b[6]&15)|64; b[8]=(b[8]&63)|128;
              const h = Array.from(b,n=>n.toString(16).padStart(2,'0')).join('');
              return h.slice(0,8)+'-'+h.slice(8,12)+'-'+h.slice(12,16)+'-'+h.slice(16,20)+'-'+h.slice(20);
            };
            """
        }
        func bundled(_ url: URL) -> Bool {
            guard url.isFileURL, let directory else { return false }
            return url.standardizedFileURL.path.hasPrefix(directory.standardizedFileURL.path + "/")
        }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, let url = message.frameInfo.request.url, bundled(url),
                  let body = message.body as? [String: Any], let action = body["action"] as? String else { return }
            if action == "openFocus" {
                if #available(iOS 17.4, *) {
                    let host = UIHostingController(rootView: FocusView(onClose: { [weak self] in
                        self?.focusHost?.dismiss(animated: true)
                        self?.focusHost = nil
                    }))
                    host.modalPresentationStyle = .pageSheet
                    host.sheetPresentationController?.detents = [.large()]
                    host.sheetPresentationController?.prefersGrabberVisible = true
                    focusHost = host
                    presenter?.present(host, animated: true)
                } else {
                    send(["type": "notice", "message": "App limits require iOS 17.4 or later.", "error": true])
                }
                return
            }
            if action == "reminder", let enabled = body["enabled"] as? Bool, let time = body["time"] as? String {
                DailyReminder.configure(enabled: enabled, time: time) { [weak self] event in
                    guard let self else { return }
                    if let controller = self.webView?.configuration.userContentController {
                        controller.removeAllUserScripts()
                        controller.addUserScript(WKUserScript(source: self.bootstrapScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
                    }
                    self.send(event)
                }
                return
            }
            if action == "appearance", let preference = body["preference"] as? String {
                store.setAppearance(preference)
                userContentController.removeAllUserScripts()
                userContentController.addUserScript(WKUserScript(source: bootstrapScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
                return
            }
            if action == "save", let state = body["state"] as? [String: Any] {
                do {
                    try store.save(state, replacingUnreadable: body["replaceUnreadable"] as? Bool == true)
                    userContentController.removeAllUserScripts()
                    userContentController.addUserScript(WKUserScript(source: bootstrapScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
                    send(["type": "saved", "success": true, "requestId": body["requestId"] ?? 0])
                } catch {
                    send(["type": "saved", "success": false, "requestId": body["requestId"] ?? 0, "error": "Couldn’t save to this iPhone. Export a backup before closing."])
                }
            } else if action == "export", let state = body["state"] as? [String: Any] { exportBackup(state) }
            else if action == "import" {
                let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json], asCopy: true)
                picker.delegate = self
                presenter?.present(picker, animated: true)
            }
        }
        var presenter: UIViewController? {
            var controller = webView?.window?.rootViewController
            while let next = controller?.presentedViewController { controller = next }
            return controller
        }
        func send(_ event: [String: Any]) {
            guard let data = try? JSONSerialization.data(withJSONObject: event) else { return }
            webView?.evaluateJavaScript("window.dispatchEvent(new CustomEvent('habit-native-event',{detail:JSON.parse(new TextDecoder().decode(Uint8Array.from(atob('\(data.base64EncodedString())'),c=>c.charCodeAt(0))))}));", completionHandler: nil)
        }
        func exportBackup(_ state: [String: Any]) {
            do {
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let file = directory.appendingPathComponent("Habit-Counter-backup.json")
                let data = try JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: file, options: [.atomic, .completeFileProtection])
                let share = UIActivityViewController(activityItems: [file], applicationActivities: nil)
                share.popoverPresentationController?.sourceView = webView
                share.popoverPresentationController?.sourceRect = CGRect(x: (webView?.bounds.midX ?? 0), y: (webView?.bounds.midY ?? 0), width: 1, height: 1)
                share.completionWithItemsHandler = { _, _, _, _ in try? FileManager.default.removeItem(at: directory) }
                presenter?.present(share, animated: true)
            } catch { send(["type": "notice", "message": "Couldn’t prepare your backup.", "error": true]) }
        }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 10 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
                let data = try Data(contentsOf: url)
                let value = try JSONSerialization.jsonObject(with: data)
                send(["type": "import", "state": value])
            } catch { send(["type": "notice", "message": "Choose a valid backup smaller than 10 MB.", "error": true]) }
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
            decisionHandler(bundled(url) && navigationAction.targetFrame?.isMainFrame != false ? .allow : .cancel)
        }
    }
}
#endif
