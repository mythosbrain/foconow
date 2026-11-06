#if os(macOS)
import Foundation
import SQLite3
import Darwin

enum ScreenTimeSource: String, Codable { case knowledge, local, cloud }
enum ScreenTimeIssue: String, Codable { case permission, missing, schema, busy, corrupt, dataVaultBlocked, error }
struct ScreenTimeFailure: Error {
    let kind: ScreenTimeIssue
    let message: String
}
struct ScreenTimeAppUsage {
    var bundleID: String
    var date: Date
    var totalSeconds: Double
    var source: ScreenTimeSource
    var deviceID = "mac"
    var deviceName = "This Mac"
}
struct ScreenTimeSourceResult {
    var source: ScreenTimeSource
    var rows: [ScreenTimeAppUsage] = []
    var issue: ScreenTimeIssue?
    var detail = ""
    var schema: [String: [String]] = [:]
}

/// Only temporary snapshots are opened by SQLite. Apple’s originals are never opened or modified.
final class ScreenTimeDatabase {
    let handle: OpaquePointer
    let directory: URL
    init(copying original: URL) throws {
        let manager = FileManager.default
        directory = manager.temporaryDirectory.appendingPathComponent("habit-screentime-\(UUID().uuidString)", isDirectory: true)
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            let destination = directory.appendingPathComponent(original.lastPathComponent)
            // A checkpoint during file copies can produce an inconsistent snapshot. Retry if
            // either the main DB or WAL changes, and never run SQLite against the originals.
            var stable = false
            for _ in 0..<3 {
                let before = try Self.stamps(original)
                for suffix in ["", "-wal", "-shm"] {
                    let source = URL(fileURLWithPath: original.path + suffix)
                    let target = URL(fileURLWithPath: destination.path + suffix)
                    try? manager.removeItem(at: target)
                    do {
                        try manager.copyItem(at: source, to: target)
                        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
                    } catch {
                        if !suffix.isEmpty && Self.isMissing(error) { continue }
                        throw error
                    }
                }
                if before == (try Self.stamps(original)) { stable = true; break }
            }
            guard stable else { throw ScreenTimeFailure(kind: .busy, message: "The source changed while copying. Refresh to try again.") }
            var pointer: OpaquePointer?
            let code = sqlite3_open_v2(destination.path, &pointer, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
            guard code == SQLITE_OK, let pointer else {
                let message = pointer.map { String(cString: sqlite3_errmsg($0)) } ?? "Cannot open the temporary database."
                if let pointer { sqlite3_close(pointer) }
                throw ScreenTimeFailure(kind: .corrupt, message: "SQLite \(code): \(message)")
            }
            handle = pointer
            sqlite3_busy_timeout(pointer, 1000)
            sqlite3_limit(pointer, SQLITE_LIMIT_LENGTH, 2 * 1024 * 1024)
            sqlite3_exec(pointer, "PRAGMA query_only=ON; PRAGMA trusted_schema=OFF;", nil, nil, nil)
        } catch {
            try? manager.removeItem(at: directory)
            if let failure = error as? ScreenTimeFailure { throw failure }
            let ns = error as NSError
            let permission = Self.isPermission(error)
            throw ScreenTimeFailure(kind: permission ? .permission : Self.isMissing(error) ? .missing : .error, message: "Copy \(original.lastPathComponent): \(ns.domain) \(ns.code): \(ns.localizedDescription)")
        }
    }
    deinit { sqlite3_close(handle); try? FileManager.default.removeItem(at: directory) }
    private static func stamps(_ original: URL) throws -> [String] {
        try ["", "-wal"].map { suffix in
            do {
                let attrs = try FileManager.default.attributesOfItem(atPath: original.path + suffix)
                guard (attrs[.type] as? FileAttributeType) == .typeRegular else { throw ScreenTimeFailure(kind: .error, message: "The source is not a regular database file.") }
                let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
                guard size < 2 * 1024 * 1024 * 1024 else { throw ScreenTimeFailure(kind: .error, message: "The source database is too large to copy safely.") }
                return "\(size):\((attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0):\(attrs[.systemFileNumber] ?? 0)"
            } catch {
                if !suffix.isEmpty && isMissing(error) { return "absent" }
                throw error
            }
        }
    }
    static func isMissing(_ error: Error) -> Bool {
        let ns = error as NSError
        return (ns.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(ns.code)) || (ns.domain == NSPOSIXErrorDomain && ns.code == Int(ENOENT))
    }
    static func isPermission(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain && [NSFileReadNoPermissionError, NSFileWriteNoPermissionError].contains(ns.code) { return true }
        if ns.domain == NSPOSIXErrorDomain && [Int(EACCES),Int(EPERM)].contains(ns.code) { return true }
        return (ns.userInfo[NSUnderlyingErrorKey] as? NSError).map { isPermission($0) } ?? false
    }
    func query(_ sql: String, numbers: [Double] = []) throws -> [[String: Any]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw databaseFailure() }
        defer { sqlite3_finalize(statement) }
        for (index,value) in numbers.enumerated() { sqlite3_bind_double(statement,Int32(index+1),value) }
        var rows: [[String: Any]] = []
        var code = sqlite3_step(statement)
        while code == SQLITE_ROW {
            guard rows.count < 200000 else { throw ScreenTimeFailure(kind: .error, message: "Too many Screen Time records to load in one request.") }
            var row: [String: Any] = [:]
            for i in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement,i))
                switch sqlite3_column_type(statement,i) {
                case SQLITE_INTEGER: row[name] = sqlite3_column_int64(statement,i)
                case SQLITE_FLOAT: row[name] = sqlite3_column_double(statement,i)
                case SQLITE_TEXT: if let text = sqlite3_column_text(statement,i) { row[name] = String(cString: text) }
                default: break
                }
            }
            rows.append(row); code = sqlite3_step(statement)
        }
        guard code == SQLITE_DONE else { throw databaseFailure() }
        return rows
    }
    private func databaseFailure() -> ScreenTimeFailure {
        let code = sqlite3_errcode(handle)
        let kind: ScreenTimeIssue = [SQLITE_BUSY,SQLITE_LOCKED].contains(code) ? .busy : [SQLITE_CORRUPT,SQLITE_NOTADB].contains(code) ? .corrupt : .schema
        return ScreenTimeFailure(kind: kind, message: "SQLite \(code): \(String(cString: sqlite3_errmsg(handle)))")
    }
    func schema() throws -> [String: [String]] {
        var result: [String: [String]] = [:]
        for row in try query("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name") {
            guard let table = row["name"] as? String, table.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil else { continue }
            result[table] = try query("PRAGMA table_info(\"\(table)\")").compactMap { $0["name"] as? String }
        }
        return result
    }
}

final class ScreenTimeReader {
    static let appleEpoch = 978307200.0
    static var knowledgeURL: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Knowledge/knowledgeC.db") }
    static var storeDirectory: URL? {
        let size = confstr(_CS_DARWIN_USER_DIR, nil, 0)
        guard size > 0 else {
            let temp = FileManager.default.temporaryDirectory.standardizedFileURL
            guard temp.lastPathComponent == "T" else { return nil }
            return temp.deletingLastPathComponent().appendingPathComponent("0/com.apple.ScreenTimeAgent/Store", isDirectory: true)
        }
        var buffer = [CChar](repeating: 0, count: size)
        confstr(_CS_DARWIN_USER_DIR, &buffer, size)
        return URL(fileURLWithPath: String(cString: buffer), isDirectory: true).appendingPathComponent("com.apple.ScreenTimeAgent/Store", isDirectory: true)
    }
    static func result(source: ScreenTimeSource, _ operation: () throws -> ScreenTimeSourceResult) -> ScreenTimeSourceResult {
        do { return try operation() }
        catch let failure as ScreenTimeFailure { return ScreenTimeSourceResult(source: source,issue: failure.kind,detail: failure.message) }
        catch { return ScreenTimeSourceResult(source: source,issue: .error,detail: error.localizedDescription) }
    }
    func knowledge(from start: Date, to end: Date, url: URL = ScreenTimeReader.knowledgeURL) -> ScreenTimeSourceResult {
        Self.result(source: .knowledge) {
            let db = try ScreenTimeDatabase(copying: url)
            let schema = try db.schema()
            guard let columns = schema["ZOBJECT"], ["ZVALUESTRING","ZSTARTDATE","ZENDDATE","ZSTREAMNAME"].allSatisfy(columns.contains) else { throw ScreenTimeFailure(kind: .schema, message: "knowledgeC.db does not have the expected app-usage schema.") }
            let rows = try db.query("SELECT ZVALUESTRING AS bundleID, ZSTARTDATE AS start, ZENDDATE AS end FROM ZOBJECT WHERE ZSTREAMNAME='/app/usage' AND ZENDDATE > ? AND ZSTARTDATE < ? AND ZENDDATE > ZSTARTDATE", numbers: [start.timeIntervalSince1970-Self.appleEpoch,end.timeIntervalSince1970-Self.appleEpoch])
            var usage: [ScreenTimeAppUsage] = []
            for row in rows {
                guard let bundle = row["bundleID"] as? String, !bundle.isEmpty, bundle.count <= 300,
                      let a = row["start"] as? Double, let b = row["end"] as? Double, a.isFinite,b.isFinite,b>a,b-a<=86400 else { continue }
                usage += Self.split(bundleID: bundle, start: Date(timeIntervalSince1970: a+Self.appleEpoch), end: Date(timeIntervalSince1970: b+Self.appleEpoch), from: start, to: min(end,Date()), source: .knowledge)
            }
            return ScreenTimeSourceResult(source: .knowledge, rows: Self.merge(usage),schema: schema)
        }
    }
    static func split(bundleID: String, start: Date, end: Date, from lower: Date, to upper: Date, source: ScreenTimeSource, calendar: Calendar = .current) -> [ScreenTimeAppUsage] {
        var cursor = max(start,lower), result: [ScreenTimeAppUsage] = []
        let stop = min(end,upper)
        while cursor < stop {
            let day = calendar.startOfDay(for: cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > cursor else { break }
            let boundary = min(stop,next)
            result.append(ScreenTimeAppUsage(bundleID: bundleID,date: day,totalSeconds: boundary.timeIntervalSince(cursor),source: source))
            cursor = boundary
        }
        return result
    }
    static func merge(_ rows: [ScreenTimeAppUsage]) -> [ScreenTimeAppUsage] {
        var result: [String: ScreenTimeAppUsage] = [:]
        for row in rows where row.totalSeconds.isFinite && row.totalSeconds > 0 {
            let key = "\(row.date.timeIntervalSince1970)|\(row.deviceID)|\(row.bundleID)"
            var value = result[key] ?? row
            if result[key] != nil { value.totalSeconds += row.totalSeconds }
            value.totalSeconds = min(value.totalSeconds,86400)
            result[key] = value
        }
        return result.values.sorted { $0.totalSeconds > $1.totalSeconds }
    }
}
#endif
