import AppKit
import WebKit

@main struct BackupDeadlineUISmoke {
    static func main() {
        guard CommandLine.arguments.count > 2, DesktopLaunchCheck.directory != nil else { exit(2) }
        let app = NSApplication.shared; app.setActivationPolicy(.accessory)
        let runner = BackupDeadlineUIRunner(); app.delegate = runner
        withExtendedLifetime(runner) { app.run() }
    }
}
@MainActor final class BackupDeadlineUIRunner: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    var window: NSWindow!; var web: WKWebView!; var bridge: WebHost.Coordinator!; var store: NativeStore!
    let output = DesktopLaunchCheck.directory!
    func applicationDidFinishLaunching(_ notification: Notification) {
        try! FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        store = NativeStore(directory: output.appendingPathComponent("isolated-data"))
        for key in CompleteBackup.keys { store.backupDefaults.removeObject(forKey: key) }
        bridge = WebHost.Coordinator(store: store)
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
        config.userContentController.add(bridge!, name: "habitCounter")
        config.userContentController.addUserScript(WKUserScript(source: bridge.bootstrapScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1280, height: 960), configuration: config)
        bridge.webView = web
        let content = URL(fileURLWithPath: CommandLine.arguments[1]); bridge.contentDirectory = content
        web.navigationDelegate = self; web.uiDelegate = bridge
        window = NSWindow(contentRect: web.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentView = web; window.makeKeyAndOrderFront(nil)
        web.loadFileURL(content.appendingPathComponent("index.html"), allowingReadAccessTo: content)
        DispatchQueue.main.asyncAfter(deadline: .now()+40) { fputs("FAIL: Timed out\n",stderr); exit(1) }
    }
    func js(_ script: String) async throws {
        _ = try await web.evaluateJavaScript(script)
        try await Task.sleep(nanoseconds: 350_000_000)
    }
    func capture(_ name: String) async throws {
        let image = try await web.takeSnapshot(configuration: nil)
        let png = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        try png.write(to: output.appendingPathComponent(name))
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        bridge.webView(webView, didFinish: navigation)
        Task { do {
            try await js("location.hash='tasks';")
            try await js("document.querySelector('#new-task').value='Prepare the weekly review';document.querySelector('#new-task-due').value='2020-01-01';document.querySelector('#add-task-form').requestSubmit();")
            try await js("if(!document.querySelector('.deadline-chip.overdue'))throw Error('Missing overdue chip');document.querySelector('[data-edit-task]').click();")
            try await js("document.querySelector('#edit-task-due-time').value='14:30';document.querySelector('#edit-task-form').requestSubmit();")
            try await js("if(!document.querySelector('.deadline-chip').textContent.includes('14:30'))throw Error('Deadline time lost');document.querySelector('#tasks-date-button').click();")
            try await capture("calendar-dark.png")
            try await js("if(document.querySelectorAll('[data-pick-date]').length!==42)throw Error('Calendar grid');let cell=document.querySelector('[data-pick-date][aria-selected=true]');let original=cell.dataset.pickDate;cell.dispatchEvent(new KeyboardEvent('keydown',{key:'ArrowRight',bubbles:true}));if(document.activeElement.dataset.pickDate===original)throw Error('Arrow navigation');document.activeElement.click();")
            try await js("document.querySelector('#tasks-today').click();document.querySelector('#settings-button').click();document.querySelector('[data-appearance-choice=light]').click();document.querySelector('#modal [data-close]').click();document.querySelector('#tasks-date-button').click();")
            try await capture("calendar-light.png")
            try await js("document.querySelector('[data-picker-close]').click();document.querySelector('[data-edit-task]').click();")
            try await capture("deadline-editor.png")
            try await js("document.querySelector('#modal [data-close]').click();document.querySelector('#settings-button').click();document.querySelector('[data-appearance-choice=dark]').click();document.querySelector('#modal [data-close]').click();")
            try PomodoroEngine.shared.start()
            let backup = try CompleteBackup.make(state:store.state!,timer:PomodoroEngine.shared.backupRecord(),directory:store.directory,defaults:store.backupDefaults)
            try await js("document.querySelector('[data-toggle-task]').click();")
            try bridge.prepareImport(backup)
            try await Task.sleep(nanoseconds: 350_000_000)
            try await capture("complete-backup-confirmation.png")
            try await js("if(!document.querySelector('#confirm-import'))throw Error('No restore confirmation');document.querySelector('#confirm-import').click();")
            try await js("if(document.querySelector('#modal').open)throw Error(document.querySelector('#complete-import-error')?.textContent||'Restore did not finish');if(document.querySelector('[data-toggle-task]').getAttribute('aria-pressed')!=='false')throw Error('Task not restored');if(!document.querySelector('.deadline-chip').textContent.includes('14:30'))throw Error('Deadline not restored');")
            guard PomodoroEngine.shared.record.status == "paused", store.appearance == "dark", try store.recoveryCopies().contains(where: { ($0["name"] as? String)?.hasPrefix("complete-") == true }) else { throw CompleteBackup.failure("Timer, appearance or safety copy missing") }
            try await capture("tasks-deadlines.png")
            print("PASS: WebKit date grid and keyboard navigation; light/dark calendar; task deadline add/edit/persistence; complete restore confirmation; restored task, paused timer, preferences and full safety copy")
            NSApplication.shared.terminate(nil)
        } catch { fputs("FAIL: \(error)\n",stderr);exit(1) } }
    }
}
