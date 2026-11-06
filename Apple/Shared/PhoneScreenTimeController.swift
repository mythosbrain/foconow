#if os(macOS)
import AppKit

/// Opt-in imports are requested only by the phone page. No source is mixed with Pomodoro data.
final class PhoneScreenTimeController {
    static let didSync = Notification.Name("HabitCounterPhoneSettingsSync")
    private static var instances: [String:PhoneScreenTimeController] = [:]
    static func shared(store:NativeStore) -> PhoneScreenTimeController {
        let key=store.directory.standardizedFileURL.path
        if let instance=instances[key] { return instance }
        let instance=PhoneScreenTimeController(store:store);instances[key]=instance;return instance
    }
    private var syncTimer: Timer?
    private var autoEnabled = false
    private var syncDevice: String?
    private var lastSync: Double = 0
    private var syncCurrent = 0
    private var syncTotal = 0
    private var syncStatus = "idle"
    private var syncMessage = "Import a period to fill your history."
    private let cancelLock = NSLock()
    private var cancelFlag = false
    var syncConfiguration: [String:Any] { ["type":"phoneSettingsSync","enabled":autoEnabled,"running":readingSettings,"current":syncCurrent,"total":syncTotal,"status":syncStatus,"message":syncMessage,"lastSync":lastSync] }
    private func emitSync() { NotificationCenter.default.post(name:Self.didSync,object:self,userInfo:syncConfiguration) }
    private var isCancelled: Bool { cancelLock.lock();defer{cancelLock.unlock()};return cancelFlag }
    func cancelSettingsImport() { cancelLock.lock();cancelFlag=true;cancelLock.unlock() }
    func configureSettingsSync(_ enabled:Bool) {
        autoEnabled=enabled
        if DesktopLaunchCheck.directory == nil { UserDefaults.standard.set(enabled,forKey:"habit-counter.phone-settings-auto") }
        syncTimer?.invalidate();syncTimer=nil
        if enabled && DesktopLaunchCheck.directory == nil {
            syncTimer=Timer.scheduledTimer(withTimeInterval:900,repeats:true){[weak self] _ in self?.automaticRefresh()}
        }
        emitSync()
    }
    private func automaticRefresh() {
        guard autoEnabled,!readingSettings,syncDevice != nil else { return }
        importSettings(days:3,automatic:true){_ in}
    }

    private let queue = DispatchQueue(label:"com.yassine.habitcounter.phone-import",qos:.utility)
    private var generation = 0
    private var importing = false
    private var readingSettings = false
    private var appCache: [String: [String: String]] = [:]
    private let store: NativeStore
    init(store: NativeStore) {
        self.store = store
        let defaults=UserDefaults.standard
        syncDevice=defaults.string(forKey:"habit-counter.phone-settings-device") ?? (try? Self.loadSettingsReports(store.directory))?.first?.deviceName
        lastSync=defaults.double(forKey:"habit-counter.phone-settings-last-sync")
        let enabled=DesktopLaunchCheck.directory == nil && (defaults.object(forKey:"habit-counter.phone-settings-auto") == nil || defaults.bool(forKey:"habit-counter.phone-settings-auto"))
        configureSettingsSync(enabled)
        if enabled { DispatchQueue.main.asyncAfter(deadline:.now()+15){[weak self] in self?.automaticRefresh()} }
    }
    deinit { syncTimer?.invalidate() }

    static func openAccessSettings() {
        if let url = URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") { NSWorkspace.shared.open(url) }
    }
    func settingsHistory(completion: @escaping ([String: Any]) -> Void) {
        let directory = store.directory, configuration=syncConfiguration
        queue.async {
            let reports = (try? Self.loadSettingsReports(directory)) ?? []
            DispatchQueue.main.async { completion(["type":"phoneSettingsReports","reports":Self.settingsJSON(reports),"sync":configuration]) }
        }
    }
    func readSettings(completion: @escaping ([String: Any]) -> Void) {
        guard !readingSettings else { return }; readingSettings = true
        let directory = store.directory, diagnostic = DesktopLaunchCheck.directory != nil
        queue.async { [weak self] in
            let event: [String: Any]
            do {
                if diagnostic { throw SettingsReportFailure(status:"accessibility",message:"Diagnostic mode excludes personal Settings windows.") }
                let tree = try SettingsScreenTimeReader.read()
                // Save only Screen Time report trees for local format troubleshooting.
                if tree.flattened.flatMap(\.texts).contains(where: { $0.contains("App & Website Activity") }), let data = try? JSONEncoder().encode(tree) {
                    let path = directory.appendingPathComponent("iphone-settings-report-tree.json")
                    try data.write(to:path,options:.atomic); try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:path.path)
                }
                let report = try SettingsScreenTimeReader.parse(tree)
                var reports = try PhoneScreenTimeController.loadSettingsReports(directory)
                reports.removeAll { $0.deviceName == report.deviceName && $0.date == report.date }; reports.append(report)
                reports = Array(reports.sorted { $0.capturedAt > $1.capturedAt }.prefix(90))
                let url = directory.appendingPathComponent("iphone-settings-reports.json")
                try JSONEncoder().encode(reports).write(to:url,options:.atomic)
                try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
                event = ["type":"phoneSettingsRead","status":"ready","reports":PhoneScreenTimeController.settingsJSON(reports),"date":report.date,"deviceName":report.deviceName]
            } catch let failure as SettingsReportFailure { event = ["type":"phoneSettingsRead","status":failure.status,"message":failure.message] }
            catch { event = ["type":"phoneSettingsRead","status":"error","message":"The Settings report couldn’t be saved: \(error.localizedDescription)"] }
            DispatchQueue.main.async { [weak self] in self?.readingSettings = false
                if let self,event["status"] as? String == "ready",let name=event["deviceName"] as? String { self.syncDevice=name; if DesktopLaunchCheck.directory == nil { UserDefaults.standard.set(name,forKey:"habit-counter.phone-settings-device") } }
                self?.emitSync(); completion(event) }
        }
    }
    func importSettings(days:Int,automatic:Bool=false,completion:@escaping ([String:Any])->Void) {
        guard !readingSettings else { return }
        readingSettings=true;cancelLock.lock();cancelFlag=false;cancelLock.unlock()
        syncCurrent=0;syncTotal=days;syncStatus="running";syncMessage=automatic ? "Refreshing recent days from Settings…":"Reading \(days) daily reports from Settings…";emitSync()
        let directory=store.directory, diagnostic=DesktopLaunchCheck.directory != nil, expected=automatic ? syncDevice:nil
        queue.async { [weak self] in
            var deviceName:String?, lastDate:String?, savedCount=0
            let status:String, message:String
            do {
                if diagnostic { throw SettingsReportFailure(status:"accessibility",message:"Diagnostic mode excludes personal Settings windows.") }
                var reports=try PhoneScreenTimeController.loadSettingsReports(directory)
                try SettingsHistoryImporter.run(days:days,source:.live(diagnosticsDirectory:directory),expectedDevice:expected,cancelled:{self?.isCancelled ?? true}) { report,current,total in
                    reports.removeAll{$0.deviceName==report.deviceName && $0.date==report.date};reports.append(report)
                    reports=Array(reports.sorted{$0.capturedAt>$1.capturedAt}.prefix(180))
                    let url=directory.appendingPathComponent("iphone-settings-reports.json")
                    try JSONEncoder().encode(reports).write(to:url,options:.atomic)
                    try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
                    deviceName=report.deviceName;lastDate=report.date;savedCount=current
                    DispatchQueue.main.async { [weak self] in guard let self else{return};self.syncCurrent=current;self.syncTotal=total;self.syncMessage="Saved \(current) of \(total) days · \(report.date)";self.emitSync() }
                }
                status="ready";message=automatic ? "Recent days are up to date.":"Imported \(savedCount) days. Settings is back on Today."
            } catch let failure as SettingsReportFailure { status=failure.status;message=failure.message }
            catch { status="error";message="Import stopped: \(error.localizedDescription). Previously saved days are safe." }
            let reports=(try? PhoneScreenTimeController.loadSettingsReports(directory)) ?? []
            DispatchQueue.main.async { [weak self] in
                guard let self else{return};self.readingSettings=false;self.syncStatus=status;self.syncMessage=message
                if let deviceName {
                    self.syncDevice=deviceName
                    if !diagnostic { UserDefaults.standard.set(deviceName,forKey:"habit-counter.phone-settings-device") }
                }
                if status=="ready" { self.lastSync=Date().timeIntervalSince1970*1000;if !diagnostic {UserDefaults.standard.set(self.lastSync,forKey:"habit-counter.phone-settings-last-sync")} }
                self.emitSync()
                var event:[String:Any]=["type":"phoneSettingsRead","status":status,"message":message,"reports":Self.settingsJSON(reports),"batch":true,"days":days]
                if let deviceName {event["deviceName"]=deviceName};if let lastDate {event["date"]=lastDate}
                completion(event)
                NotificationCenter.default.post(name:Self.didSync,object:self,userInfo:["type":"phoneSettingsReports","reports":Self.settingsJSON(reports),"sync":self.syncConfiguration])
            }
        }
    }
    private static func loadSettingsReports(_ directory: URL) throws -> [SettingsUsageReport] {
        let url = directory.appendingPathComponent("iphone-settings-reports.json")
        guard FileManager.default.fileExists(atPath:url.path) else { return [] }
        guard (try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0) <= 4*1024*1024 else { throw CocoaError(.fileReadTooLarge) }
        return try JSONDecoder().decode([SettingsUsageReport].self,from:Data(contentsOf:url))
    }
    private static func settingsJSON(_ reports: [SettingsUsageReport]) -> [[String: Any]] {
        ((try? JSONSerialization.jsonObject(with:JSONEncoder().encode(reports))) as? [[String:Any]]) ?? []
    }
    func refresh(completion: @escaping ([String: Any]) -> Void) {
        guard !importing else { return }
        importing = true; generation += 1
        let request = generation
        let now = Date(), calendar = Calendar.current
        let today = calendar.startOfDay(for:now)
        let start = calendar.date(byAdding:.day,value:-6,to:today)!
        let diagnostic = DesktopLaunchCheck.directory
        queue.async { [weak self] in
            let result: IPhoneUsageResult
            let admin: ScreenTimeSourceResult
            if diagnostic != nil {
                result = IPhoneUsageResult(issue:.permission,detail:"Diagnostic permission state. No personal Apple records were accessed.")
                admin = ScreenTimeSourceResult(source:.cloud,issue:.permission,detail:"Personal records excluded from diagnostics.")
            } else {
                result = IPhoneScreenTimeReader().read(from:start,to:now)
                // Discover the actual Cloud schema without assuming private table layouts.
                admin = ScreenTimeReader.result(source:.cloud) {
                    guard let directory = ScreenTimeReader.storeDirectory else { throw ScreenTimeFailure(kind:.missing,message:"The Darwin Screen Time store location is unavailable.") }
                    let db = try ScreenTimeDatabase(copying:directory.appendingPathComponent("RMAdminStore-Cloud.sqlite"))
                    return ScreenTimeSourceResult(source:.cloud,schema:try db.schema())
                }
            }
            let grouped = PhoneScreenTimeController.group(result,from:start,to:now,calendar:calendar)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == request else { return }
                self.importing = false
                var devices: [[String: Any]] = []
                for device in result.devices {
                    var days: [[String: Any]] = []
                    for offset in 0..<7 {
                        let date = calendar.date(byAdding:.day,value:offset,to:start)!
                        let key = Self.dateKey(date)
                        let day = grouped[device.id]?[key] ?? PhoneUsageDay()
                        let apps: [[String: Any]] = day.apps.sorted { $0.value > $1.value }.prefix(500).map { bundle,seconds in
                            var app: [String: Any] = self.appInfo(bundle)
                            app["bundleID"] = bundle; app["seconds"] = seconds
                            return app
                        }
                        days.append(["date":key,"totalSeconds":day.apps.values.reduce(0,+),"hours":day.hours,"apps":apps])
                    }
                    devices.append(["id":device.id,"name":device.name,"days":days])
                }
                let hasData = grouped.values.contains { $0.values.contains { !$0.apps.isEmpty } }
                let status = hasData ? "ready" : result.issue?.rawValue ?? "empty"
                let report: [String: Any] = ["status":status,"detail":result.detail,"warning":result.warning,"devices":devices,"updatedAt":now.timeIntervalSince1970*1000,"newestEvent":result.newestEvent.map { $0*1000 } ?? 0,"source":"biome-remote","adminCloudState":admin.issue?.rawValue ?? "schema-readable"]
                let diagnostics: [String: Any] = ["status":status,"biomeDetail":result.detail,"deviceCount":result.devices.count,"source":"App.InFocus remote","updatedAt":now.timeIntervalSince1970*1000,"adminCloudState":admin.issue?.rawValue ?? "schema-readable","adminCloudDetail":admin.detail,"adminCloudSchema":admin.schema]
                // Metadata-only diagnostics never include app usage, account information or raw records.
                if let data = try? JSONSerialization.data(withJSONObject:diagnostics,options:[.prettyPrinted,.sortedKeys]) {
                    let url = self.store.directory.appendingPathComponent("iphone-import-diagnostics.json")
                    do { try data.write(to:url,options:.atomic); try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path) } catch { }
                }
                if hasData, let data = try? JSONSerialization.data(withJSONObject:report,options:[.sortedKeys]) {
                    let url = self.store.directory.appendingPathComponent("iphone-screen-time-latest.json")
                    do { try data.write(to:url,options:.atomic); try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path) } catch { }
                }
                completion(["type":"phoneScreenTime","snapshot":report])
            }
        }
    }
    private func appInfo(_ bundle: String) -> [String: String] {
        if let cached = appCache[bundle] { return cached }
        let names = ["com.burbn.instagram":"Instagram","com.google.ios.youtube":"YouTube","net.whatsapp.WhatsApp":"WhatsApp","com.apple.mobilesafari":"Safari","com.apple.MobileSMS":"Messages","com.apple.mobilemail":"Mail","com.apple.Preferences":"Settings","com.zhiliaoapp.musically":"TikTok","com.atebits.Tweetie2":"X","com.openai.chat":"ChatGPT","com.apple.springboard":"Home & Lock Screen"]
        var info = ["name":names[bundle] ?? bundle]
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier:bundle) {
            let app = Bundle(url:url)
            info["name"] = (app?.object(forInfoDictionaryKey:"CFBundleDisplayName") as? String) ?? (app?.object(forInfoDictionaryKey:"CFBundleName") as? String) ?? info["name"]
            let original = NSWorkspace.shared.icon(forFile:url.path)
            let image = NSImage(size:NSSize(width:32,height:32))
            image.lockFocus(); original.draw(in:NSRect(x:0,y:0,width:32,height:32)); image.unlockFocus()
            if let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data:tiff), let png = bitmap.representation(using:.png,properties:[:]) { info["icon"] = "data:image/png;base64,"+png.base64EncodedString() }
        }
        if appCache.count < 500 { appCache[bundle] = info }
        return info
    }
    struct PhoneUsageDay {
        var apps: [String: Double] = [:]
        var hours = [Double](repeating:0,count:24)
    }
    static func dateKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year,.month,.day],from:date)
        return String(format:"%04d-%02d-%02d",parts.year ?? 0,parts.month ?? 0,parts.day ?? 0)
    }
    static func group(_ result: IPhoneUsageResult, from lower: Date, to upper: Date, calendar: Calendar) -> [String: [String: PhoneUsageDay]] {
        var devices: [String: [String: PhoneUsageDay]] = [:]
        for (id,sessions) in result.sessions {
            var days: [String: PhoneUsageDay] = [:]
            for session in sessions {
                var cursor = max(lower.timeIntervalSince1970,session.start)
                let end = min(upper.timeIntervalSince1970,session.end)
                while cursor < end {
                    let date = Date(timeIntervalSince1970:cursor), start = calendar.startOfDay(for:date)
                    guard let tomorrow = calendar.date(byAdding:.day,value:1,to:start) else { break }
                    let boundary = min(end,tomorrow.timeIntervalSince1970)
                    let key = dateKey(start,calendar:calendar)
                    var day = days[key] ?? PhoneUsageDay()
                    day.apps[session.bundleID,default:0] += boundary-cursor
                    while cursor < boundary {
                        let date = Date(timeIntervalSince1970:cursor)
                        guard let hour = calendar.dateInterval(of:.hour,for:date) else { break }
                        let stop = min(boundary,hour.end.timeIntervalSince1970)
                        guard stop > cursor else { break }
                        day.hours[calendar.component(.hour,from:date)] += stop-cursor; cursor = stop
                    }
                    cursor = boundary
                    days[key] = day
                }
            }
            devices[id] = days
        }
        return devices
    }
}
#endif
