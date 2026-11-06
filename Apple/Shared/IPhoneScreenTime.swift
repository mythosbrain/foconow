#if os(macOS)
import Foundation
import zlib

struct SyncedScreenTimeDevice {
    let id: String
    let name: String
    let platform: Int
}
struct IPhoneUsageSession: Hashable {
    let bundleID: String
    let start: Double
    let end: Double
}
struct IPhoneFocusEvent: Hashable {
    let bundleID: String
    let time: Double
    let starting: Bool
}
struct IPhoneUsageResult {
    var devices: [SyncedScreenTimeDevice] = []
    var sessions: [String: [IPhoneUsageSession]] = [:]
    var issue: ScreenTimeIssue?
    var detail = ""
    var warning = ""
    var newestEvent: Double?
}

/// Decodes only the documented-by-observation App.InFocus fields needed for usage.
/// No network calls, app-store lookups, account identifiers or unrelated streams.
enum IPhoneFocusFormat {
    private static func uint32(_ data: Data, _ offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 | UInt32(data[offset+$1]) << ($1*8) }
    }
    private static func uint64(_ data: Data, _ offset: Int) -> UInt64 {
        (0..<8).reduce(UInt64(0)) { $0 | UInt64(data[offset+$1]) << ($1*8) }
    }
    static func events(in data: Data) throws -> [IPhoneFocusEvent] {
        guard data.count >= 32, data.prefix(4) == Data("SEGB".utf8) else {
            throw ScreenTimeFailure(kind: .schema, message: "This Mac uses an unsupported Biome segment format. No guessed usage was imported.")
        }
        let count = Int(uint32(data,4))
        guard count <= 200000, count <= (data.count-32)/16 else { throw ScreenTimeFailure(kind: .corrupt, message: "Invalid Biome entry table.") }
        let tableStart = data.count-count*16
        var cursor = 32, events: [IPhoneFocusEvent] = []
        for index in 0..<count {
            let entry = data.count-(index+1)*16
            let end = 32+Int(uint32(data,entry)), state = uint32(data,entry+4)
            if end == 32 { continue }
            guard end <= tableStart, end >= cursor+8 else { throw ScreenTimeFailure(kind: .corrupt, message: "Invalid Biome record bounds.") }
            if state == 1 {
                let payload = Data(data[(cursor+8)..<end])
                let checksum = payload.withUnsafeBytes { UInt32(crc32(0,$0.bindMemory(to:Bytef.self).baseAddress,uInt($0.count))) }
                guard checksum == uint32(data,cursor) else { throw ScreenTimeFailure(kind: .busy, message: "A Biome record changed during copying. Refresh to try again.") }
                if let event = decode(payload) { events.append(event) }
            }
            cursor = (end+3) & ~3
        }
        return events
    }
    static func decode(_ data: Data) -> IPhoneFocusEvent? {
        guard data.count <= 65536 else { return nil }
        var position = 0, kind: UInt64?, flag: UInt64?, timestamp: Double?, bundle: String?
        func variable() -> UInt64? {
            var value: UInt64 = 0
            for shift in stride(from:0,through:63,by:7) {
                guard position < data.count else { return nil }
                let byte = data[position]; position += 1
                if shift == 63 && byte > 1 { return nil }
                value |= UInt64(byte & 127) << shift
                if byte < 128 { return value }
            }
            return nil
        }
        while position < data.count {
            guard let tag = variable(), tag >> 3 > 0 else { return nil }
            let field = tag >> 3
            switch tag & 7 {
            case 0:
                guard let value = variable() else { return nil }
                if field == 2 { kind = value }; if field == 3 { flag = value }
            case 1:
                guard position <= data.count-8 else { return nil }
                if field == 4 { timestamp = Double(bitPattern:uint64(data,position)) }
                position += 8
            case 2:
                guard let length = variable(), length <= UInt64(data.count-position) else { return nil }
                if field == 6 { bundle = String(data:data[position..<(position+Int(length))],encoding:.utf8) }
                position += Int(length)
            case 5:
                guard position <= data.count-4 else { return nil }; position += 4
            default: return nil
            }
        }
        guard kind == 1, let flag, flag <= 1, let timestamp, timestamp.isFinite, timestamp >= 0,
              let bundle, !bundle.isEmpty, bundle.count <= 300, !bundle.contains("\n") else { return nil }
        return IPhoneFocusEvent(bundleID:bundle,time:timestamp+ScreenTimeReader.appleEpoch,starting:flag==1)
    }
    static func sessions(from events: [IPhoneFocusEvent], now: Double = Date().timeIntervalSince1970) -> [IPhoneUsageSession] {
        let sorted = Set(events).filter { $0.time <= now }.sorted { $0.time == $1.time ? (!$0.starting && $1.starting) : $0.time < $1.time }
        var starts: [String: Double] = [:], sessions: [IPhoneUsageSession] = []
        for event in sorted {
            if event.starting {
                // Do not invent an end for a lost event or count an ongoing synced session.
                starts[event.bundleID] = event.time
            } else if let start = starts.removeValue(forKey:event.bundleID), event.time > start, event.time-start <= 86400 {
                sessions.append(IPhoneUsageSession(bundleID:event.bundleID,start:start,end:event.time))
            }
        }
        // Repeated synced segments can describe overlapping intervals for one app.
        var merged: [IPhoneUsageSession] = []
        for (_, group) in Dictionary(grouping:sessions,by: { $0.bundleID }) {
            for session in group.sorted(by: { $0.start < $1.start }) {
                if let last = merged.last, last.bundleID == session.bundleID, session.start <= last.end {
                    merged[merged.count-1] = IPhoneUsageSession(bundleID:last.bundleID,start:last.start,end:max(last.end,session.end))
                } else { merged.append(session) }
            }
        }
        return merged
    }
}

enum SyncedScreenTimeAccess: String {
    case accessible
    case blocked
    case unavailable
    case unverified
}

final class IPhoneScreenTimeReader {
    let root: URL
    private var syncDatabase: URL { root.appendingPathComponent("sync/sync.db") }
    private var remoteActivity: URL { root.appendingPathComponent("streams/restricted/App.InFocus/remote", isDirectory: true) }
    init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Biome",isDirectory:true)) { self.root = root }
    /// Test the files used by this import, without reading records or creating a snapshot.
    func checkAccess() -> SyncedScreenTimeAccess {
        do {
            let database = try FileHandle(forReadingFrom: syncDatabase)
            try database.close()
            _ = try FileManager.default.contentsOfDirectory(atPath: remoteActivity.path)
            return .accessible
        } catch {
            if ScreenTimeDatabase.isPermission(error) { return .blocked }
            if ScreenTimeDatabase.isMissing(error) { return .unavailable }
            return .unverified
        }
    }

    func read(from start: Date, to end: Date) -> IPhoneUsageResult {
        do {
            let peers = try devices()
            let directories = try FileManager.default.contentsOfDirectory(at:remoteActivity,includingPropertiesForKeys:[.isDirectoryKey])
                .filter { !$0.lastPathComponent.hasPrefix(".") && (try? $0.resourceValues(forKeys:[.isDirectoryKey]).isDirectory) == true }
            var result = IPhoneUsageResult()
            for directory in directories {
                let id = directory.lastPathComponent
                // Platform 2 identifies iOS/iPadOS. Never relabel the local Mac as an iPhone.
                guard let device = peers.first(where: { $0.id.caseInsensitiveCompare(id) == .orderedSame && $0.platform == 2 }) else { continue }
                result.devices.append(device)
                let files = try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:[.isRegularFileKey,.fileSizeKey])
                    .filter { UInt64($0.lastPathComponent) != nil && (try? $0.resourceValues(forKeys:[.isRegularFileKey]).isRegularFile) == true }
                guard files.count <= 1024 else { throw ScreenTimeFailure(kind:.error,message:"Too many synced segments to inspect safely in one refresh.") }
                var events: [IPhoneFocusEvent] = []
                var failed = 0, lastFailure: ScreenTimeFailure?
                for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    do { events += try readSegment(file) }
                    catch { failed += 1; lastFailure = error as? ScreenTimeFailure }
                    guard events.count <= 500000 else { throw ScreenTimeFailure(kind:.error,message:"Too many synced events to load in one refresh.") }
                }
                let sessions = IPhoneFocusFormat.sessions(from:events)
                result.sessions[id] = sessions.filter { $0.end > start.timeIntervalSince1970 && $0.start < end.timeIntervalSince1970 }
                if let newest = events.map(\.time).filter({ $0 <= Date().timeIntervalSince1970 }).max() { result.newestEvent = max(result.newestEvent ?? 0,newest) }
                if failed > 0 {
                    result.warning = "\(failed) synced files could not be decoded. The visible totals may be incomplete."
                    result.detail += lastFailure?.message ?? "A synced file could not be read."
                    if sessions.isEmpty { result.issue = lastFailure?.kind ?? .error }
                }
            }
            if result.devices.isEmpty && !directories.isEmpty {
                result.issue = .schema; result.detail = "Remote activity exists, but no iPhone/iPad identity could be verified against DevicePeer. Mac usage was not substituted."
            }
            return result
        } catch let failure as ScreenTimeFailure { return IPhoneUsageResult(issue:failure.kind,detail:failure.message) }
        catch { return IPhoneUsageResult(issue:ScreenTimeDatabase.isPermission(error) ? .permission : ScreenTimeDatabase.isMissing(error) ? .missing : .error,detail:error.localizedDescription) }
    }
    func devices() throws -> [SyncedScreenTimeDevice] {
        let db = try ScreenTimeDatabase(copying:syncDatabase)
        let schema = try db.schema()
        guard let columns = schema["DevicePeer"], ["device_identifier","platform","me"].allSatisfy(columns.contains) else { throw ScreenTimeFailure(kind:.schema,message:"Biome device metadata has an unfamiliar schema.") }
        let nameColumn = ["name","device_name","display_name"].first(where:columns.contains)
        let select = nameColumn.map { ", \"\($0)\" AS name" } ?? ""
        return try db.query("SELECT device_identifier AS id, platform\(select) FROM DevicePeer WHERE me=0").compactMap { row in
            guard let id = row["id"] as? String, !id.isEmpty, id.count<=100, let platform = row["platform"] as? Int64 else { return nil }
            let name = (row["name"] as? String).flatMap { $0.isEmpty ? nil : String($0.prefix(100)) } ?? "Synced iPhone / iPad"
            return SyncedScreenTimeDevice(id:id,name:name,platform:Int(platform))
        }
    }
    private func readSegment(_ original: URL) throws -> [IPhoneFocusEvent] {
        let manager = FileManager.default
        let folder = manager.temporaryDirectory.appendingPathComponent("habit-phone-segb-\(UUID().uuidString)",isDirectory:true)
        try manager.createDirectory(at:folder,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        defer { try? manager.removeItem(at:folder) }
        let attrs = try original.resourceValues(forKeys:[.fileSizeKey])
        guard (attrs.fileSize ?? Int.max) <= 32*1024*1024 else { throw ScreenTimeFailure(kind:.error,message:"A synced segment exceeds the safe file size limit.") }
        let copy = folder.appendingPathComponent("segment")
        do {
            try manager.copyItem(at:original,to:copy)
            try manager.setAttributes([.posixPermissions:0o600],ofItemAtPath:copy.path)
            return try IPhoneFocusFormat.events(in:Data(contentsOf:copy))
        } catch {
            if let failure = error as? ScreenTimeFailure { throw failure }
            throw ScreenTimeFailure(kind:ScreenTimeDatabase.isPermission(error) ? .permission : .error,message:error.localizedDescription)
        }
    }
}
#endif
