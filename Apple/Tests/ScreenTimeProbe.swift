import Foundation

@main struct ScreenTimeProbe {
    static func main() {
        let now = Date(), start = Calendar.current.startOfDay(for: now)
        let result = IPhoneScreenTimeReader().read(from:start,to:now)
        let devices: [[String:Any]] = result.devices.map { device in
            var totals: [String:Double] = [:]
            for session in result.sessions[device.id] ?? [] { totals[session.bundleID,default:0] += max(0,min(now.timeIntervalSince1970,session.end)-max(start.timeIntervalSince1970,session.start)) }
            return ["name":device.name,"top20":totals.sorted { $0.value > $1.value }.prefix(20).map { ["bundleID":$0.key,"seconds":Int($0.value)] as [String:Any] }]
        }
        var output: [String: Any] = ["process":"ScreenTimeProbe launched by Codex (separate permissions from Habit Counter)","source":"synced iPhone / iPad only","state":result.issue?.rawValue ?? (devices.isEmpty ? "empty":"ready"),"detail":result.detail,"devices":devices]
        if let directory = ScreenTimeReader.storeDirectory {
            output["storeDirectory"] = directory.path
            var stores: [[String: Any]] = []
            for (source,name) in [(ScreenTimeSource.local,"RMAdminStore-Local.sqlite"),(.cloud,"RMAdminStore-Cloud.sqlite")] {
                let value = ScreenTimeReader.result(source: source) {
                    let db = try ScreenTimeDatabase(copying: directory.appendingPathComponent(name))
                    return ScreenTimeSourceResult(source: source,schema: try db.schema())
                }
                stores.append(["source":source.rawValue,"state":value.issue?.rawValue ?? "schema-readable","detail":value.detail,"schema":value.schema])
            }
            output["adminStores"] = stores
        }
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Biome")
        var biome: [String: Any] = [:]
        let metadata = ScreenTimeReader.result(source: .cloud) {
            let db = try ScreenTimeDatabase(copying: root.appendingPathComponent("sync/sync.db"))
            return ScreenTimeSourceResult(source: .cloud,schema:try db.schema())
        }
        biome["metadata"] = ["state":metadata.issue?.rawValue ?? "readable","detail":metadata.detail,"schema":metadata.schema]
        do {
            let remote = root.appendingPathComponent("streams/restricted/App.InFocus/remote",isDirectory:true)
            let devices = try FileManager.default.contentsOfDirectory(at:remote,includingPropertiesForKeys:nil).filter { !$0.lastPathComponent.hasPrefix(".") }
            biome["remoteDevices"] = devices.map { device -> [String: Any] in
                do {
                    let files = try FileManager.default.contentsOfDirectory(at:device,includingPropertiesForKeys:[.isRegularFileKey]).filter { (try? $0.resourceValues(forKeys:[.isRegularFileKey]).isRegularFile) == true }
                    return ["device":device.lastPathComponent,"segments":files.count]
                } catch { return ["device":device.lastPathComponent,"error":error.localizedDescription] }
            }
        } catch { biome["remoteState"] = ScreenTimeDatabase.isPermission(error) ? "permission":"missing-or-error"; biome["remoteDetail"] = error.localizedDescription }
        output["biome"] = biome
        if let data = try? JSONSerialization.data(withJSONObject: output,options:[.prettyPrinted,.sortedKeys]) { print(String(decoding:data,as:UTF8.self)) }
    }
}
