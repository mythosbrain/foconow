import AppKit
import SQLite3
import zlib

@main struct ScreenTimeChecks {
    static func main() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("habit-phone-tests-\(UUID().uuidString)",isDirectory:true)
        try FileManager.default.createDirectory(at:temp,withIntermediateDirectories:false)
        defer { try? FileManager.default.removeItem(at:temp) }
        let start = Date().timeIntervalSince1970-300, end = start+240
        let events = [event("app.a",start,true),event("app.a",end,false),event("app.a",start,true),event("app.a",end,false),event("unfinished",end,true)]
        let data = segment(events)
        let decoded = try IPhoneFocusFormat.events(in:data)
        let sessions = IPhoneFocusFormat.sessions(from:decoded)
        assert(sessions.count == 1 && sessions[0].end-sessions[0].start == 240,"Synced duplicate records count once; no invented end for unfinished events")
        assert(IPhoneFocusFormat.decode(Data([0x80])) == nil)
        assert(IPhoneFocusFormat.decode(event("overlay",start,true,kind:3)) == nil)
        var corrupt = data; corrupt[40] ^= 1
        do { _ = try IPhoneFocusFormat.events(in:corrupt); fatalError("Accepted invalid CRC") } catch { }
        do { _ = try IPhoneFocusFormat.events(in:Data("old-format".utf8)); fatalError("Accepted unknown format") } catch { }
        let merged = IPhoneFocusFormat.sessions(from:[.init(bundleID:"a",time:start,starting:true),.init(bundleID:"a",time:end,starting:false),.init(bundleID:"a",time:start+1,starting:true),.init(bundleID:"a",time:end+1,starting:false)])
        assert(merged.count == 1 && merged[0].end-merged[0].start == 239)
        for count in 0..<200 { _ = IPhoneFocusFormat.decode(Data((0..<count).map { UInt8(($0*127+count)%256) })) }
        print("PASS: SEGB CRC/bounds; required protobuf fields; overlays ignored; duplicate start/end events; unfinished sessions excluded; malformed payloads safe")

        let sync = temp.appendingPathComponent("sync",isDirectory:true)
        try FileManager.default.createDirectory(at:sync,withIntermediateDirectories:true)
        var db: OpaquePointer?
        sqlite3_open(sync.appendingPathComponent("sync.db").path,&db)
        defer { sqlite3_close(db) }
        exec(db,"PRAGMA journal_mode=WAL; CREATE TABLE DevicePeer(device_identifier TEXT,platform INTEGER,me INTEGER,name TEXT); INSERT INTO DevicePeer VALUES('phone',2,0,'iPhone 16 Pro Max'),('mac',3,0,'Other Mac');")
        let remote = temp.appendingPathComponent("streams/restricted/App.InFocus/remote",isDirectory:true)
        for name in ["phone","mac"] {
            let folder = remote.appendingPathComponent(name,isDirectory:true)
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            try data.write(to:folder.appendingPathComponent("1"))
        }
        let reader = IPhoneScreenTimeReader(root: temp)
        assert(reader.checkAccess() == .accessible, "Readable synced source should be recognized without importing")
        assert(IPhoneScreenTimeReader(root: temp.appendingPathComponent("absent")).checkAccess() == .unavailable)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: remote.path)
        let blocked = reader.checkAccess()
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: remote.path)
        assert(blocked == .blocked, "Existing but unreadable source is different from a missing source")
        print("PASS: synced source access distinguishes readable, missing, and blocked files")
        let dbHash = try Data(contentsOf:sync.appendingPathComponent("sync.db"))
        var copy: ScreenTimeDatabase? = try ScreenTimeDatabase(copying:sync.appendingPathComponent("sync.db"))
        assert(sqlite3_db_readonly(copy!.handle,"main") == 1)
        let peers = try copy!.query("SELECT * FROM DevicePeer")
        assert(peers.count == 2,"Copied WAL content must be readable")
        let copyPath = copy!.directory; copy=nil
        assert(!FileManager.default.fileExists(atPath:copyPath.path),"Snapshots cleaned after use")
        let result = IPhoneScreenTimeReader(root:temp).read(from:Date(timeIntervalSince1970:start-1),to:Date())
        assert(result.issue == nil && result.devices.count == 1 && result.devices[0].name == "iPhone 16 Pro Max")
        assert(result.sessions["phone"]?.count == 1 && result.sessions["mac"] == nil,"Never substitute Mac usage for phone usage")
        let dbAfter = try Data(contentsOf:sync.appendingPathComponent("sync.db"))
        assert(dbAfter == dbHash,"Original metadata DB unchanged")
        let missing = IPhoneScreenTimeReader(root:temp.appendingPathComponent("absent")).read(from:Date(),to:Date())
        assert(missing.issue == .missing)
        print("PASS: SQLite read-only copies include WAL; temporary snapshots cleaned; iPhone identity verified; Mac peers excluded; missing source typed; originals unchanged")

        var calendar = Calendar(identifier:.gregorian); calendar.timeZone = TimeZone(identifier:"America/New_York")!
        let formatter = ISO8601DateFormatter()
        for (a,b,seconds) in [("2026-11-04T23:30:00-05:00","2026-11-05T00:30:00-05:00",3600.0),("2026-11-01T00:30:00-04:00","2026-11-01T03:30:00-05:00",14400.0)] {
            let from=formatter.date(from:a)!, to=formatter.date(from:b)!
            let sample = IPhoneUsageResult(sessions:["phone":[.init(bundleID:"a",start:from.timeIntervalSince1970,end:to.timeIntervalSince1970)]])
            let grouped = PhoneScreenTimeController.group(sample,from:from,to:to,calendar:calendar)
            assert(grouped["phone"]!.values.reduce(0) { $0 + $1.apps.values.reduce(0,+) } == seconds)
            assert(grouped["phone"]!.values.reduce(0) { $0 + $1.hours.reduce(0,+) } == seconds)
        }
        print("PASS: phone usage splits across midnight and daylight-saving hours without losing or inventing seconds")
        func text(_ value: String) -> SettingsAXNode { SettingsAXNode(role:"AXStaticText",value:value) }
        let settings = SettingsAXNode(role:"AXWindow",children:[text("App & Website Activity"),SettingsAXNode(role:"AXPopUpButton",value:"Sample iPhone"),SettingsAXNode(role:"AXPopUpButton",value:"Today"),SettingsAXNode(role:"AXTable",children:[SettingsAXNode(role:"AXRow",children:[text("All Usage"),text("4h 25m")]),SettingsAXNode(role:"AXRow",children:[text("Sample Reader"),text("1h 5m")]),SettingsAXNode(role:"AXRow",children:[text("Sample Maps"),text("42m")])])])
        let report = try SettingsScreenTimeReader.parse(settings)
        assert(report.totalSeconds == 265*60 && report.apps.count == 2 && report.apps[0].seconds == 65*60)
        assert(report.totalSeconds != report.apps.reduce(0) { $0+$1.seconds },"Settings total is not replaced by a partial app-list sum")
        var wrongDevice = settings; wrongDevice.children[1].value = "All Devices"
        do { _ = try SettingsScreenTimeReader.parse(wrongDevice); fatalError("Imported All Devices as iPhone") } catch { }
        var wrongDate = settings; wrongDate.children[2].value = "This Week"
        do { _ = try SettingsScreenTimeReader.parse(wrongDate); fatalError("Imported an unverified date") } catch { }
        assert(SettingsScreenTimeReader.duration("4h 25m") == 15900)
        assert(SettingsScreenTimeReader.duration("1 hour 5 minutes") == 3900)
        assert(SettingsScreenTimeReader.duration("4 hours, 25 minutes") == 15900)
        assert(SettingsScreenTimeReader.duration("90m") == 5400)
        assert(SettingsScreenTimeReader.duration("99 hours") == nil)
        print("PASS: Settings displayed total preserved independently of app-row sums; verified phone/date required; duration parser handles minutes/hours and rejects absurd totals")
        let historyNow=Date(timeIntervalSince1970:1793793600)
        var historyCalendar=Calendar(identifier:.gregorian);historyCalendar.timeZone=TimeZone(secondsFromGMT:0)!
        final class FakeSettings {
            var offset=1,previousCalls=0,todayCalls=0,savedCount=0
            var switchDevice=false
            let now:Date, calendar:Calendar
            init(_ now:Date,_ calendar:Calendar){self.now=now;self.calendar=calendar}
            func read()->SettingsUsageReport {
                SettingsUsageReport(deviceName:switchDevice && savedCount>=2 ? "Another iPhone":"iPhone 16 Pro Max",date:PhoneScreenTimeController.dateKey(calendar.date(byAdding:.day,value:-offset,to:now)!,calendar:calendar),totalSeconds:Double(offset+1)*60,apps:[],capturedAt:Date().timeIntervalSince1970*1000)
            }
            var source:SettingsHistorySource {SettingsHistorySource(read:{self.read()},today:{self.offset=0;self.todayCalls+=1},previous:{self.offset+=1;self.previousCalls+=1})}
        }
        for count in [7,30] {
            let fake=FakeSettings(historyNow,historyCalendar);var imported:[SettingsUsageReport]=[]
            try SettingsHistoryImporter.run(days:count,source:fake.source,now:historyNow,calendar:historyCalendar,pause:{_ in}){report,current,total in imported.append(report);fake.savedCount=current;assert(total==count)}
            assert(imported.count==count && Set(imported.map(\.date)).count==count && fake.previousCalls==count-1 && fake.offset==0 && fake.todayCalls==2)
        }
        let cancellation=FakeSettings(historyNow,historyCalendar);var partial:[SettingsUsageReport]=[]
        do {
            try SettingsHistoryImporter.run(days:30,source:cancellation.source,now:historyNow,calendar:historyCalendar,pause:{_ in},cancelled:{partial.count>=3}){report,_,_ in partial.append(report)}
            fatalError("Cancellation ignored")
        } catch let failure as SettingsReportFailure {assert(failure.status=="cancelled")}
        assert(partial.count==3 && cancellation.offset==0)
        let switched=FakeSettings(historyNow,historyCalendar);switched.switchDevice=true
        do {try SettingsHistoryImporter.run(days:7,source:switched.source,now:historyNow,calendar:historyCalendar,pause:{_ in}){_,current,_ in switched.savedCount=current};fatalError("Mixed devices") }catch{ }
        assert(switched.savedCount==2 && switched.offset==1,"User's changed device/report is left alone")
        assert(SettingsScreenTimeReader.reportDate("Tuesday, 3 November",now:historyNow,calendar:historyCalendar) != nil)
        assert(SettingsScreenTimeReader.reportDate("This Week, 2–8 November",now:historyNow,calendar:historyCalendar) == nil)
        assert(SettingsScreenTimeReader.reportDate("31 February 2026",now:historyNow,calendar:historyCalendar) == nil)
        print("PASS: 7/30-day navigation, distinct dates and stable report attribution; cancellation keeps partial progress; device changes stop without mixing; Settings returns to Today")
        var zeroHeader=settings;zeroHeader.children[3].children=[];zeroHeader.children.append(SettingsAXNode(role:"AXStaticText",value:"0 seconds",identifier:"usageHeaderView"))
        assert(tryZero(zeroHeader)==0,"A verified midnight zero can come from the explicit Settings usage header")
        if let index=CommandLine.arguments.firstIndex(of:"--zero-fixture"),CommandLine.arguments.count>index+1 {
            let tree=try JSONDecoder().decode(SettingsAXNode.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[index+1])))
            let report=try SettingsScreenTimeReader.parse(tree)
            assert(report.totalSeconds == 0)
            print("PASS: real midnight Settings report retains verified zero usage without losing earlier days")
        }
        if let index = CommandLine.arguments.firstIndex(of:"--settings-fixture"), CommandLine.arguments.count > index+1 {
            let data = try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[index+1]))
            let tree = try JSONDecoder().decode(SettingsAXNode.self,from:data)
            let real = try SettingsScreenTimeReader.parse(tree,now:Date(timeIntervalSince1970:1793833200))
            let output = try JSONEncoder().encode(real)
            try output.write(to:URL(fileURLWithPath:CommandLine.arguments[index+1]).deletingLastPathComponent().appendingPathComponent("settings-real-parsed.json"))
            print("PASS: System Settings fixture parses as an iPhone usage report")
        }
    }
    static func tryZero(_ node:SettingsAXNode)->Double? {(try? SettingsScreenTimeReader.parse(node))?.totalSeconds}
    static func exec(_ db: OpaquePointer?, _ sql: String) { assert(sqlite3_exec(db,sql,nil,nil,nil)==SQLITE_OK) }
    static func append32(_ value: UInt32, to data: inout Data) { for i in 0..<4 { data.append(UInt8((value >> (i*8)) & 255)) } }
    static func event(_ bundle: String, _ time: Double, _ start: Bool, kind: UInt8 = 1) -> Data {
        var data = Data([0x10,kind,0x18,start ? 1:0,0x21])
        let bits = (time-ScreenTimeReader.appleEpoch).bitPattern
        for i in 0..<8 { data.append(UInt8((bits >> (i*8)) & 255)) }
        data.append(contentsOf:[0x32,UInt8(bundle.utf8.count)]);data.append(contentsOf:bundle.utf8)
        return data
    }
    static func segment(_ records: [Data]) -> Data {
        var result = Data("SEGB".utf8);append32(UInt32(records.count),to:&result)
        result.append(Data(repeating:0,count:24));var ends: [Int] = []
        for record in records {
            while result.count%4 != 0 { result.append(0) }
            let crc = record.withUnsafeBytes { UInt32(crc32(0,$0.bindMemory(to:Bytef.self).baseAddress,uInt($0.count))) }
            append32(crc,to:&result);append32(0,to:&result);result.append(record);ends.append(result.count-32)
        }
        for end in ends.reversed() { append32(UInt32(end),to:&result);append32(1,to:&result);result.append(Data(repeating:0,count:8)) }
        return result
    }
}
