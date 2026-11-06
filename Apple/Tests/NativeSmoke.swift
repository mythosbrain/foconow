import AppKit
import WebKit

/// Runs the real bundled WebKit UI and native disk bridge with isolated test data.
@main
struct NativeSmoke {
    static func main() {
        guard CommandLine.arguments.count > 2, let directory = DesktopLaunchCheck.directory,
              directory.standardizedFileURL == URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true).standardizedFileURL else {
            fputs("Native smoke requires --startup-check with the absolute output directory to isolate timer records.\n", stderr)
            exit(2)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let runner = SmokeRunner()
        app.delegate = runner
        withExtendedLifetime(runner) { app.run() }
    }
}

final class SmokeRunner: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var webView: WKWebView!
    var bridge: WebHost.Coordinator!
    let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
    var dataDirectory: URL { output.appendingPathComponent("isolated-data", isDirectory: true) }
    var reports: [String] = []
    var attempts = 0
    var previousTimeOrigin: Double?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        catch { fail("Cannot prepare smoke output: \(error)"); return }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        bridge = WebHost.Coordinator(store: NativeStore(directory: dataDirectory))
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.add(bridge!, name: "habitCounter")
        config.userContentController.addUserScript(WKUserScript(source: bridge.bootstrapScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1280, height: 850), configuration: config)
        bridge.webView = webView
        bridge.contentDirectory = directory
        webView.navigationDelegate = bridge
        webView.uiDelegate = bridge
        window = NSWindow(contentRect: webView.frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Habit Counter — verification"
        window.contentView = webView
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        webView.loadFileURL(directory.appendingPathComponent("index.html"), allowingReadAccessTo: directory)
        waitReady {
            if CommandLine.arguments.contains("--show-permission-setup") { self.verifyPermissionSetup() }
            else { self.verifyDailyFocus() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 70) { self.fail("Native test timed out") }
    }

    func verifyPermissionSetup() {
        expect("""
        document.querySelector('#modal').open &&
        document.querySelector('[data-setup-step="0"]:not([hidden]) h2').textContent === 'Welcome to FocoNow' &&
        document.querySelectorAll('.setup-workflow article').length === 3 &&
        document.querySelector('[data-setup-step="0"]').textContent.includes('100% LOCAL APP DATA') &&
        !document.querySelector('.setup-panel:not([hidden]) [data-permission]')
        """, "First launch introduces the workspace and local storage before showing permission controls") {
            self.capture("setup-workspace.png") {
                self.evaluate("document.querySelector('#permissions-next').click()") {
                    self.expect("document.querySelector('[data-setup-step=\"1\"]:not([hidden]) [data-permission=notifications]') !== null && !document.querySelector('[data-setup-step=\"1\"]').textContent.includes('Full Disk Access')", "Alerts and login are offered separately from Screen Time permissions") {
                        self.capture("setup-alerts.png") {
                            self.evaluate("document.querySelector('#permissions-next').click()") { self.verifyPermissionResume() }
                        }
                    }
                }
            }
        }
    }

    func verifyPermissionResume() {
        expect("""
        (() => {
          const access = document.querySelector('[data-setup-step="2"]:not([hidden]) [data-permission=fullDiskAccess]');
          return access?.textContent === 'Access confirmed' && access.disabled;
        })()
        """, "Screen Time setup confirms readable synced activity without asking to grant access again") {
            self.capture("setup-screen-time.png") {
                self.reloadForPermissionCheck {
                    self.expect("document.querySelector('[data-setup-step=\"2\"]:not([hidden])') !== null && window.__HABIT_NATIVE__.permissionSetupStep === 2", "Onboarding returns to the Screen Time step after a reload") {
                        self.evaluate("document.querySelector('#permissions-back').click()") {
                            self.expect("document.querySelector('[data-setup-step=\"1\"]:not([hidden])') !== null", "Back returns to the previous onboarding step") {
                                self.evaluate("document.querySelector('#permissions-skip').click()") { self.verifyPermissionDismissal() }
                            }
                        }
                    }
                }
            }
        }
    }

    func verifyPermissionDismissal() {
        reloadForPermissionCheck {
            self.expect("!document.querySelector('#modal').open && !window.__HABIT_NATIVE__.showPermissionSetup", "Skipping setup keeps the workspace open and dismisses onboarding across reloads") {
                self.evaluate("document.querySelector('#settings-button').click();document.querySelector('#open-permission-setup').click()") {
                    self.expect("document.querySelector('#modal').open && document.querySelector('[data-setup-step=\"1\"]:not([hidden])') !== null", "Settings can reopen the permission review") {
                        self.evaluate("document.querySelector('#permissions-skip').click()") { self.verifyDailyFocus() }
                    }
                }
            }
        }
    }

    func reloadForPermissionCheck(_ next: @escaping () -> Void) {
        webView.evaluateJavaScript("performance.timeOrigin") { origin, _ in
            self.previousTimeOrigin = origin as? Double
            self.webView.reload()
            self.waitReady {
                self.previousTimeOrigin = nil
                next()
            }
        }
    }

    func verifyDailyFocus() {
        evaluate("document.querySelector('#day-timer-toggle').click()") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.expect("document.querySelector('#day-timer-toggle').textContent === 'Pause' && document.querySelector('#pomo-start-label').textContent === 'Pause'", "My Day starts the same focus timer as Tasks & Focus") {
                    self.evaluate("document.querySelector('#day-timer-toggle').click()") {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            self.expect("document.querySelector('#day-timer-toggle').textContent === 'Resume' && document.querySelector('#day-timer-state').textContent === 'Focus · paused'", "My Day pauses the shared timer and shows its state") {
                                do { try PomodoroEngine.shared.reset() }
                                catch { self.fail("Could not reset the isolated timer"); return }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.verifyDailyPlanner() }
                            }
                        }
                    }
                }
            }
        }
    }

    func verifyDailyPlanner() {
        expect("document.documentElement.dataset.view === 'planner' && document.documentElement.dataset.theme === 'dark' && !document.querySelector('#planner-view').hidden && document.querySelector('#heading').textContent === 'My Day' && document.querySelector('.habit-toolbar').closest('#overview-view') !== null && document.querySelector('#habit-insights').closest('#overview-view') !== null && document.querySelector('#day-timer-toggle').textContent === 'Start focus'", "Mac opens to My Day with a focus timer and habit controls confined to Bad Habits") {
            self.evaluate("document.querySelector('#plan-morning').click();document.querySelector('#morning-focus').value='Finish what matters';document.querySelector('#morning-tasks').value='Finish my project\\nTake a long walk';document.querySelector('#morning-form').requestSubmit()") {
                self.expect("document.querySelectorAll('.task-row').length === 2 && document.querySelector('#day-focus').value === 'Finish what matters' && document.querySelectorAll('#day-next-tasks li').length === 2 && document.querySelector('#day-task-open').textContent === '2'", "Morning plan creates the main target and multiple daily tasks") {
                    self.evaluate("document.querySelector('[data-priority-task]').click();document.querySelector('[data-toggle-task]').click();document.querySelector('#day-summary').value='Today I finished the important work and made time for myself.';document.querySelector('#day-summary').dispatchEvent(new Event('input'))") {
                        self.expect("document.querySelector('#task-progress').textContent === '1 / 2 done' && document.querySelector('#summary-status').textContent.includes('Draft saved')", "Task completion, priority, and summary drafts save through the native bridge") {
                            self.evaluate("document.querySelector('#finish-day').click();document.querySelector('#planner-prev').click();document.querySelector('#new-task').value='Bring this task forward';document.querySelector('#add-task-form').requestSubmit();document.querySelector('#planner-today').click();document.querySelector('#carry-tasks').click();document.querySelector('#carry-form').requestSubmit()") {
                                self.expect("document.querySelector('#task-progress').textContent === '1 / 3 done' && document.querySelector('#summary-status').textContent.includes('Day reviewed')", "Unfinished tasks can be brought forward while preserving the saved daily summary") {
                                    self.webView.evaluateJavaScript("performance.timeOrigin") { origin, _ in
                                        self.previousTimeOrigin = origin as? Double
                                        self.webView.reload()
                                        self.waitReady {
                                            self.previousTimeOrigin = nil
                                            self.expect("document.querySelector('#day-summary').value.includes('important work') && document.querySelectorAll('.task-row').length === 3", "Full app-page reload preserves tasks, daily target, summary, and completed state") {
                                                guard DesktopCounter.shared.plan(at: Date())["focus"] as? String == "Finish what matters" else { self.fail("Menu bar daily target did not follow native storage") }
                                                self.reports.append("Menu bar receives the same saved daily planner state")
                                                self.evaluate("location.hash='overview'") { self.editHabit() }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    func waitReady(_ next: @escaping () -> Void) {
        let newDocument = previousTimeOrigin.map { " && performance.timeOrigin !== \($0)" } ?? ""
        webView.evaluateJavaScript("document.querySelector('.local-chip')?.textContent === 'Saved on this Mac'\(newDocument)") { value, error in
            if value as? Bool == true { self.attempts = 0; next() }
            else {
                self.attempts += 1
                if self.attempts > 80 { self.fail("Bundled UI or native persistence did not become ready: \(String(describing: error))"); return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.waitReady(next) }
            }
        }
    }

    func evaluate(_ script: String, _ next: @escaping () -> Void) {
        webView.evaluateJavaScript(script) { _, error in
            if let error { self.fail("JavaScript error: \(error)") }
            else { self.waitReady(next) }
        }
    }

    func readState() throws -> [String: Any] {
        let data = try Data(contentsOf: dataDirectory.appendingPathComponent("state.json"))
        guard let state = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CocoaError(.fileReadCorruptFile) }
        return state
    }

    func editHabit() {
        reports.append("Bundled classic JavaScript loads offline and initial state saves natively")
        evaluate("""
        document.querySelector('#edit-habit').click();
        document.querySelector('#habit-name').value = 'Native smoke test';
        document.querySelector('#habit-reason').value = 'Bridge persistence check';
        document.querySelector('#habit-form').requestSubmit();
        """) {
            do {
                let habits = try self.readState()["habits"] as? [[String: Any]]
                guard habits?.first?["name"] as? String == "Native smoke test" else { self.fail("Edit did not persist to Application Support"); return }
                self.reports.append("Habit edit reaches native atomic disk storage")
                self.checkin()
            } catch { self.fail("Read after edit: \(error)") }
        }
    }

    func checkin() {
        evaluate("""
        document.querySelector('[data-mood="good"]').click();
        document.querySelector('#checkin-button').click();
        document.querySelector('#checkin-note').value = 'A native check-in';
        document.querySelector('#checkin-form').requestSubmit();
        """) {
            do {
                let h = (try self.readState()["habits"] as? [[String: Any]])?.first
                guard (h?["checkins"] as? [[String: Any]])?.first?["note"] as? String == "A native check-in" else { self.fail("Check-in did not persist"); return }
                self.reports.append("Check-in and note persist through the native bridge")
                self.webView.evaluateJavaScript("performance.timeOrigin") { origin, _ in
                    self.previousTimeOrigin = origin as? Double
                    self.webView.reload()
                    self.waitReady { self.previousTimeOrigin = nil; self.verifyReload() }
                }
            } catch { self.fail("Read after check-in: \(error)") }
        }
    }

    func verifyReload() {
        webView.evaluateJavaScript("document.querySelector('#habit-select').selectedOptions[0].textContent === 'Native smoke test' && document.querySelector('#checkin-tag').textContent === 'COMPLETE'") { value, error in
            guard value as? Bool == true else { self.fail("Reload lost current data: \(String(describing: error))"); return }
            self.reports.append("Full WebKit reload keeps the latest state without reverting it")
            do {
                let snapshot = try self.readState()
                let reopened = NativeStore(directory: self.dataDirectory)
                guard let reloaded = reopened.state,
                      NSDictionary(dictionary: snapshot).isEqual(to: reloaded) else { self.fail("Fresh native store could not reload disk state"); return }
                self.reports.append("A new native store instance reloads the saved data")
                self.bridge.send(["type": "import", "state": snapshot])
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.confirmImport() }
            } catch { self.fail("Read after reload: \(error)") }
        }
    }

    func confirmImport() {
        webView.evaluateJavaScript("document.querySelector('#modal').open && document.querySelector('#confirm-import') !== null") { value, _ in
            guard value as? Bool == true else {
                self.webView.evaluateJavaScript("JSON.stringify({toast:document.querySelector('#toast').textContent,modal:document.querySelector('#modal').innerHTML,ready:document.readyState})") { diagnostic, error in
                    self.fail("Native import did not ask for confirmation: \(String(describing: diagnostic)); \(String(describing: error))")
                }
                return
            }
            self.evaluate("document.querySelector('#confirm-import').click()") {
                let files = (try? FileManager.default.contentsOfDirectory(atPath: self.dataDirectory.path)) ?? []
                guard files.contains(where: { $0.hasPrefix("before-restore-") }) else { self.fail("Restore did not preserve previous state"); return }
                self.reports.append("Native import confirms replacement and preserves the previous copy")
                self.verifyDesktop()
            }
        }
    }

    func expect(_ script: String, _ message: String, next: @escaping () -> Void) {
        webView.evaluateJavaScript(script) { value, error in
            guard value as? Bool == true else { self.fail("\(message): \(String(describing: error))") }
            self.reports.append(message)
            next()
        }
    }

    func verifyDesktop() {
        expect("document.documentElement.dataset.platform === 'mac' && !document.querySelector('#calendar-card').hidden && document.querySelector('#open-focus').hidden && document.querySelector('#heading').textContent === 'Bad Habits' && document.querySelector('#habit-select').options.length === 1", "Bad Habits has its own tracker, selection and calendar") {
            self.evaluate("document.querySelector('[data-calendar-date][aria-current=date]').click()") {
                self.expect("document.querySelector('#modal').textContent.includes('A native check-in')", "Calendar opens the actual saved check-in for its day") {
                    self.evaluate("document.querySelector('#modal [data-close]').click();document.querySelector('#calendar-prev').click()") {
                        self.expect("!document.querySelector('#calendar-next').disabled", "Calendar supports previous months and return to today") {
                            self.evaluate("document.querySelector('#calendar-now').click();document.querySelector('#desktop-search').click();document.querySelector('#command-search').value='reflection';document.querySelector('#command-search').dispatchEvent(new Event('input'));document.querySelector('#command-search').dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',bubbles:true}));document.querySelector('#entry-text').value='A reflection from quick actions';document.querySelector('#entry-form').requestSubmit()") {
                                self.expect("document.querySelector('#journal-list').textContent.includes('A reflection from quick actions')", "Keyboard-searchable quick actions open a working reflection form") {
                                    self.verifyHabitSwitching()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    func verifyHabitSwitching() {
        evaluate("document.querySelector('#add-habit').click();document.querySelector('#habit-name').value='Another personal goal';document.querySelector('#habit-form').requestSubmit()") {
            self.expect("document.querySelector('#habit-select').options.length === 2 && document.querySelector('#habit-select').selectedOptions[0].textContent === 'Another personal goal'", "Adding a bad habit updates the tracker and native saved selection") {
                self.evaluate("const selector = document.querySelector('#habit-select');selector.selectedIndex=0;selector.dispatchEvent(new Event('change',{bubbles:true}))") {
                    self.expect("document.querySelector('#checkin-tag').textContent === 'COMPLETE' && document.querySelector('#habit-select').selectedOptions[0].textContent === 'Native smoke test'", "Switching habits brings back the original habit’s saved check-in") {
                        self.verifyMenuAndRecovery()
                    }
                }
            }
        }
    }

    func verifyMenuAndRecovery() {
        guard DesktopCounter.shared.active?["name"] as? String == "Native smoke test" else { fail("Menu bar snapshot did not follow successful saves") }
        DesktopCounter.shared.command("urge")
        expect("document.querySelector('#urge-form') !== null", "Native menu bar actions reach the main window") {
            self.evaluate("document.querySelector('#modal').close();document.querySelector('#settings-button').click();document.querySelector('#open-recovery').click()") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    self.expect("document.querySelector('[data-recovery]') !== null", "Native recovery copies appear in settings") {
                        self.evaluate("document.querySelector('[data-recovery]').click()") {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                self.expect("document.querySelector('#confirm-import') !== null", "A recovery copy requires confirmation before replacing current data") {
                                    self.evaluate("document.querySelector('#modal').close();document.documentElement.dataset.theme='light';window.scrollTo(0,0)") { self.screenshot() }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    func screenshot() {
        // Background WebKit windows can suspend animation clocks during snapshotting.
        evaluate("const reviewStyle=document.createElement('style');reviewStyle.textContent='*,*::before,*::after{animation:none!important;transition:none!important}';document.head.append(reviewStyle);document.querySelector('#toast').classList.remove('visible');document.documentElement.dataset.theme='dark';location.hash='planner'") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                self.capture("daily-planner-dark.png") {
                    self.evaluate("document.documentElement.dataset.theme='light'") {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            self.capture("daily-planner-light.png") {
                                self.evaluate("location.hash='overview'") {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        self.capture("native-dashboard.png") { self.darkScreenshot() }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    func capture(_ name: String, next: @escaping () -> Void) {
        webView.takeSnapshot(with: nil) { image, error in
            guard let image, let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { self.fail("Screenshot failed: \(String(describing: error))"); return }
            do {
                try png.write(to: self.output.appendingPathComponent(name))
                next()
            } catch { self.fail("Cannot save result: \(error)") }
        }
    }

    func darkScreenshot() {
        evaluate("document.documentElement.dataset.theme='dark'") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self.capture("native-dashboard-dark.png") {
                    self.evaluate("document.querySelector('#calendar-card').scrollIntoView({block:'center'})") {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            self.capture("native-calendar-dark.png") { self.compactScreenshot() }
                        }
                    }
                }
            }
        }
    }

    func compactScreenshot() {
        window.setContentSize(NSSize(width: 800, height: 780))
        evaluate("window.scrollTo(0,0)") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                self.expect("document.documentElement.scrollWidth <= innerWidth && [...document.querySelectorAll('.time-parts b')].every(e=>{const a=e.getBoundingClientRect(),b=document.querySelector('.counter-ring').getBoundingClientRect();return a.left>b.left&&a.right<b.right})", "Narrow Mac layout fits the window and keeps counter digits inside the circle") {
                    self.capture("native-compact-dark.png") {
                        self.evaluate("location.hash='planner'") {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                self.expect("document.documentElement.scrollWidth <= innerWidth && document.querySelector('#day-summary').getBoundingClientRect().width > 100", "Daily planner adapts to a smaller Mac window without horizontal overflow") {
                                    self.capture("daily-planner-compact.png") { self.taskScreens() }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    func taskScreens() {
        window.setContentSize(NSSize(width: 1280, height: 850))
        evaluate("location.hash='tasks'") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                self.expect("!document.querySelector('#tasks-view').hidden && document.querySelector('#planner-view').hidden && document.querySelector('#pomo-start').getBoundingClientRect().bottom <= innerHeight", "Tasks and Pomodoro have a separate page with timer controls visible at desktop size") {
                    self.capture("tasks-focus-dark.png") {
                        self.evaluate("document.documentElement.dataset.theme='light'") {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                self.capture("tasks-focus-light.png") {
                                    self.window.setContentSize(NSSize(width: 800, height: 780))
                                    self.evaluate("document.documentElement.dataset.theme='dark';window.scrollTo(0,0)") {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                            self.expect("document.documentElement.scrollWidth <= innerWidth", "Task page adapts to smaller windows without horizontal overflow") {
                                                self.capture("tasks-focus-compact.png") { self.controlScreens() }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    func controlScreens() {
        window.setContentSize(NSSize(width: 1280, height: 850))
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        evaluate("location.hash='tasks';document.querySelector('#new-task').value='A little focus for today';document.querySelector('#new-task').focus();window.scrollTo(0,0)") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                self.expect("getComputedStyle(document.querySelector('#new-task')).outlineStyle === 'none' && getComputedStyle(document.querySelector('.add-task-form')).boxShadow !== 'none'", "Task entry uses the rounded outer field focus treatment without an inner rectangle") {
                    self.capture("controls-task-input-dark.png") {
                        self.evaluate("document.querySelector('#pomo-settings').click();document.querySelector('#pomo-setting-every').parentElement.querySelector('.select-trigger').click()") {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                self.expect("document.querySelector('.select-menu') !== null && document.querySelector('.select-trigger[aria-expanded=true]') !== null && document.querySelectorAll('.number-shell').length === 3", "Modal dropdown and number controls use the custom UI") {
                                    self.capture("controls-dropdown-dark.png") {
                                        self.evaluate("document.documentElement.dataset.theme='light'") {
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                                self.capture("controls-dropdown-light.png") { self.insightScreens() }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    func insightScreens() {
        window.setContentSize(NSSize(width: 1280, height: 1050))
        evaluate("""
        document.querySelector('#modal [data-close]').click();document.documentElement.dataset.theme='dark';
        const diagnosticNow=new Date();diagnosticNow.setHours(18,0,0,0);Date.now=()=>+diagnosticNow;
        const fixture={phase:'work',status:'ready',duration:1500,remaining:1500,cycle:0,settings:{work:25,short:5,long:15,every:4,sounds:true},taskId:'',sessions:[],focusSpans:[]};
        for(let i=0;i<7;i++) { const date=new Date();date.setDate(date.getDate()-i);date.setHours(9,0,0,0);const start=+date;const seconds=[4200,5400,2700,7200,1800,3600,4500][i];fixture.focusSpans.push({start,end:start+seconds*1000,taskId:'writing',taskTitle:'Build something that matters'});fixture.sessions.push({id:'sample-'+i,endedAt:start+seconds*1000,seconds,tracked:true}); }
        window.dispatchEvent(new CustomEvent('habit-native-event',{detail:{type:'pomodoro',snapshot:fixture}}));location.hash='insights';window.scrollTo(0,0);
        """) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                self.expect("document.querySelectorAll('[data-focus-day]').length===7 && document.querySelector('#insight-total').textContent==='8h 10m' && document.querySelectorAll('#focus-hour-chart>div').length===24 && document.querySelector('#focus-task-ranking').textContent.includes('Build something')", "Insights sums focus hours and renders daily, hourly, task progress and allocation charts") {
                    self.capture("insights-dark-sample.png") {
                        self.evaluate("document.querySelector('[data-focus-day]').click()") {
                            self.expect("document.querySelector('#focus-day-total').textContent==='1h 15m' && document.querySelector('[data-focus-day]').getAttribute('aria-pressed')==='true'", "Selecting a chart bar displays that day’s focus total and hourly breakdown") {
                                self.evaluate("document.querySelector('[data-insight-range=\\\"30\\\"]').click()") {
                                    self.expect("document.querySelectorAll('[data-focus-day]').length===30 && document.querySelector('#insight-total').textContent==='8h 10m'", "Thirty-day view preserves focus totals and renders all daily bars") {
                                        self.evaluate("document.querySelector('[data-insight-range=\\\"7\\\"]').click();document.querySelector('#focus-day-title').scrollIntoView({block:'start'})") {
                                            self.capture("insights-detail-sample.png") {
                                                self.window.setContentSize(NSSize(width: 800, height: 900))
                                                self.evaluate("window.scrollTo(0,0)") {
                                                    self.expect("document.documentElement.scrollWidth<=innerWidth && [...document.querySelectorAll('.focus-stat')].every(e=>e.scrollWidth<=e.clientWidth)", "Insights charts and summary cards fit a compact Mac window") {
                                                        self.capture("insights-compact-sample.png") {
                                                            self.window.setContentSize(NSSize(width: 1280, height: 1050))
                                                            self.evaluate("document.documentElement.dataset.theme='light';window.scrollTo(0,0)") {
                                                                self.capture("insights-light-sample.png") { self.phoneScreens() }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    func phoneScreens() {
        evaluate("document.documentElement.dataset.theme='dark';location.hash='phone';window.scrollTo(0,0)") {
            DispatchQueue.main.asyncAfter(deadline:.now()+0.4) {
                self.expect("!document.querySelector('#phone-view').hidden && !document.querySelector('#phone-access-settings').hidden && document.querySelector('#phone-data').hidden && !document.querySelector('#phone-access-steps').hidden", "Phone import shows a clean Full Disk Access onboarding state without displaying Mac data or synthetic totals") {
                    self.capture("iphone-permission-dark.png") {
                        self.evaluate("""
                        const phoneDays=[];for(let i=0;i<7;i++){const d=new Date();d.setDate(d.getDate()-6+i);const date=`${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;const seconds=i===0?600:3300;phoneDays.push({date,totalSeconds:seconds,hours:Array.from({length:24},(_,h)=>h===12?seconds:0),apps:i===0?[{name:'Sample app',bundleID:'sample.a',seconds:600}]:[{name:'Sample app',bundleID:'sample.a',seconds:1800},{name:'Another app',bundleID:'sample.b',seconds:1500}]});}
                        const phoneFixture={status:'ready',detail:'',warning:'',devices:[{id:'sample-phone',name:'Sample iPhone — preview',days:phoneDays}],updatedAt:Date.now(),newestEvent:Date.now()-60000};window.dispatchEvent(new CustomEvent('habit-native-event',{detail:{type:'phoneScreenTime',snapshot:phoneFixture}}));
                        """) {
                            self.expect("document.querySelector('#phone-total').textContent==='55m' && document.querySelectorAll('[data-phone-day]').length===7 && document.querySelectorAll('.phone-app-row').length===2 && document.querySelector('#insight-total').textContent==='8h 10m'", "Phone charts, hourly bars and ranked apps render separately from Pomodoro totals using isolated sample data") {
                                self.capture("iphone-usage-sample-dark.png") {
                                    self.evaluate("document.querySelector('[data-phone-day]').click()") {
                                        self.expect("document.querySelector('#phone-total').textContent==='10m' && document.querySelectorAll('.phone-app-row').length===1", "Selecting a phone chart day updates its own app list and duration") {
                                            self.window.setContentSize(NSSize(width:800,height:900))
                                            self.evaluate("window.scrollTo(0,0)") {
                                                self.expect("document.documentElement.scrollWidth<=innerWidth", "Phone import charts adapt to a compact window") {
                                                    self.capture("iphone-compact-sample.png") {
                                                        self.evaluate("window.dispatchEvent(new CustomEvent('habit-native-event',{detail:{type:'phoneScreenTime',snapshot:{status:'schema',detail:'Unsupported test format',devices:[],updatedAt:Date.now()}}}))") {
                                                            self.expect("!document.querySelector('#phone-empty').hidden && !document.querySelector('#phone-import-details').hidden && document.querySelector('#phone-import-error').readOnly", "Unknown schemas have a safe empty state and copyable error details") { self.settingsReportScreens() }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    func settingsReportScreens() {
        window.setContentSize(NSSize(width:1280,height:1050))
        evaluate("document.querySelector('#phone-read-settings').click()") {
            DispatchQueue.main.asyncAfter(deadline:.now()+0.4) {
                self.expect("!document.querySelector('#phone-settings-access').hidden && document.querySelector('#phone-settings-message').textContent.includes('Diagnostic mode')", "Settings reader presents an Accessibility permission state and never reads personal windows in diagnostics") {
                    self.evaluate("""
                    const date=new Date();const key=`${date.getFullYear()}-${String(date.getMonth()+1).padStart(2,'0')}-${String(date.getDate()).padStart(2,'0')}`;
                    window.dispatchEvent(new CustomEvent('habit-native-event',{detail:{type:'phoneSettingsRead',status:'ready',deviceName:'Sample iPhone 16 Pro Max',date:key,reports:[{deviceName:'Sample iPhone 16 Pro Max',date:key,totalSeconds:46380,capturedAt:Date.now(),apps:[{name:'Instagram',seconds:12600},{name:'YouTube',seconds:11760}]}]}}));window.scrollTo(0,0);
                    """) {
                        self.expect("document.querySelector('#phone-total').textContent==='12h 53m' && document.querySelector('#phone-total-label').textContent==='TOTAL SHOWN IN SETTINGS' && document.querySelector('#phone-hour-panel').hidden && document.querySelector('#phone-source-settings').getAttribute('aria-pressed')==='true'", "Settings report preserves Apple's displayed total without inventing hourly values or summing an incomplete app list") {
                            self.capture("settings-report-sample-dark.png") {
                                self.evaluate("document.querySelector('#phone-source-events').click();document.querySelector('#phone-source-settings').click()") {
                                    self.expect("document.querySelector('#phone-total').textContent==='12h 53m' && document.querySelector('#insight-total').textContent==='8h 10m'", "Switching report sources preserves the Settings snapshot and leaves focus hours unchanged") { self.periodScreens() }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    func periodScreens() {
        evaluate("""
        const periodReports=[];for(let i=0;i<30;i++){const d=new Date();d.setDate(d.getDate()-i);const date=`${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;periodReports.push({deviceName:'Sample iPhone 16 Pro Max',date,totalSeconds:(i+1)*60,capturedAt:Date.now(),apps:[{name:'Sample app',seconds:60}]});}
        window.dispatchEvent(new CustomEvent('habit-native-event',{detail:{type:'phoneSettingsReports',reports:periodReports,sync:{enabled:false,running:false,current:0,total:0,message:''}}}));document.querySelector('[data-phone-range="7"]').click();
        """) {
            self.expect("document.querySelector('#phone-total').textContent==='28m' && document.querySelectorAll('[data-phone-day]').length===7 && document.querySelector('#phone-selected-date').textContent.includes('7 / 7')", "Seven-day Settings totals use all daily reports and show complete coverage") {
                self.evaluate("document.querySelector('[data-phone-range=\"30\"]').click()") {
                    self.expect("document.querySelector('#phone-total').textContent==='7h 45m' && document.querySelectorAll('[data-phone-day]').length===30 && document.querySelector('#phone-bars').classList.contains('month-range')", "Thirty-day Settings view aggregates authoritative totals and renders a monthly chart") {
                        self.capture("settings-month-sample-dark.png") {
                            self.window.setContentSize(NSSize(width:800,height:900))
                            self.evaluate("window.scrollTo(0,0)") {
                                self.expect("document.documentElement.scrollWidth<=innerWidth", "Monthly phone controls and charts fit a compact window") {
                                    self.evaluate("window.dispatchEvent(new CustomEvent('habit-native-event',{detail:{type:'phoneSettingsReports',reports:periodReports.slice(0,2)}}));window.dispatchEvent(new CustomEvent('habit-native-event',{detail:{type:'phoneSettingsSync',enabled:true,running:true,current:3,total:30,message:'Saved 3 of 30 days',status:'running'}}))") {
                                        self.expect("document.querySelector('#phone-total').textContent==='3m' && document.querySelectorAll('[data-phone-day][disabled]').length===28 && !document.querySelector('#phone-import-progress').hidden && !document.querySelector('#phone-cancel-import').hidden && document.querySelector('#phone-import-month').disabled", "Missing days stay explicit while progress and Stop controls protect a running import") {
                                            self.evaluate("window.dispatchEvent(new CustomEvent('habit-native-event',{detail:{type:'phoneSettingsSync',enabled:false,running:false,current:3,total:30,message:'Stopped',status:'cancelled'}}))") { self.finish() }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    func finish() {
                        do {
                            let data = try JSONSerialization.data(withJSONObject: ["passed": true, "checks": self.reports], options: .prettyPrinted)
                            try data.write(to: self.output.appendingPathComponent("result.json"))
                            print(String(decoding: data, as: UTF8.self))
                            self.webView.configuration.userContentController.removeScriptMessageHandler(forName: "habitCounter")
                            self.bridge.stop()
                            NSApplication.shared.terminate(nil)
                        } catch { self.fail("Cannot save result: \(error)") }
    }

    func fail(_ message: String) -> Never {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}
