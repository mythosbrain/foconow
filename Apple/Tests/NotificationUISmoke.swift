import AppKit
import WebKit

@main struct NotificationUISmoke {
    static func main() {
        guard CommandLine.arguments.count > 2, DesktopLaunchCheck.directory != nil else { exit(2) }
        let app = NSApplication.shared; app.setActivationPolicy(.accessory)
        let runner = NotificationUIRunner(); app.delegate = runner
        withExtendedLifetime(runner) { app.run() }
    }
}
final class NotificationUIRunner: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    var window: NSWindow!
    var web: WKWebView!
    var bridge: WebHost.Coordinator!
    let output = DesktopLaunchCheck.directory!
    func applicationDidFinishLaunching(_ notification: Notification) {
        try! FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        bridge = WebHost.Coordinator(store: NativeStore(directory: output.appendingPathComponent("isolated-data")))
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
        config.userContentController.add(bridge!, name: "habitCounter")
        config.userContentController.addUserScript(WKUserScript(source: bridge.bootstrapScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1180, height: 900), configuration: config)
        bridge.webView = web
        let content = URL(fileURLWithPath: CommandLine.arguments[1]); bridge.contentDirectory = content
        web.navigationDelegate = self; web.uiDelegate = bridge
        window = NSWindow(contentRect: web.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentView = web; window.makeKeyAndOrderFront(nil)
        web.loadFileURL(content.appendingPathComponent("index.html"), allowingReadAccessTo: content)
        DispatchQueue.main.asyncAfter(deadline: .now()+25) { self.fail("Timed out") }
    }
    func fail(_ message: String) { fputs("FAIL: \(message)\n", stderr); exit(1) }
    func js(_ script: String, _ next: @escaping () -> Void) {
        web.evaluateJavaScript(script) { _, error in if let error { self.fail(error.localizedDescription) }; DispatchQueue.main.asyncAfter(deadline: .now()+0.25, execute: next) }
    }
    func capture(_ name: String, next: @escaping () -> Void) {
        web.takeSnapshot(with: nil) { image, error in
            guard let data = image?.tiffRepresentation, let png = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]) else { self.fail("Snapshot failed"); return }
            try! png.write(to: self.output.appendingPathComponent(name)); next()
        }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        bridge.webView(webView, didFinish: navigation)
        js("document.querySelector('#settings-button').click();document.querySelector('#open-notification-settings').click();if(!document.querySelector('#nudges-form'))throw Error('Missing settings');if(document.querySelector('#nudge-tasks').checked)throw Error('Must opt in');") {
            self.capture("notification-settings.png") {
                self.js("document.querySelector('#nudge-from').value='9';document.querySelector('#nudge-until').value='9';document.querySelector('#nudges-form').requestSubmit();if(!document.querySelector('#nudge-error').textContent)throw Error('Quiet hours not validated');document.querySelector('#nudge-until').value='21';document.querySelector('#nudge-sounds').checked=false;document.querySelector('#nudges-form').requestSubmit();") {
                    self.js("if(document.querySelector('#modal').open)throw Error('Preferences not saved');document.querySelector('#settings-button').click();document.querySelector('#open-notification-settings').click();if(document.querySelector('#nudge-sounds').checked)throw Error('Saved state lost');document.querySelector('#alert-timer-settings').click();if(!document.querySelector('#preview-focus-sound')||!document.querySelector('#preview-break-sound'))throw Error('Missing alarm controls');document.querySelector('#modal [data-close]').click();") {
                        self.js("const testTimer={...window.__HABIT_NATIVE__.pomodoro,status:'running',endsAt:Date.now(),phase:'work'};window.dispatchEvent(new CustomEvent('habit-native-event',{detail:{type:'pomodoro',snapshot:testTimer}}));window.dispatchEvent(new CustomEvent('habit-native-event',{detail:{type:'pomodoro',snapshot:{...testTimer,status:'completed',remaining:0,nextPhase:'short'}}}));if(!document.querySelector('#completion-notice'))throw Error('Completion notice missing');") {
                            self.capture("completion-notice.png") {
                                self.js("document.querySelector('#completion-dismiss').click();if(document.querySelector('#completion-notice'))throw Error('Dismiss failed');") {
                                    print("PASS: real WebKit notification controls, quiet-hour validation, native preference round trip, alarm links, completion card and dismiss")
                                    NSApplication.shared.terminate(nil)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
