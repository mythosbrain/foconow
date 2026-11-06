import Foundation

@main
struct RecoverySmoke {
    static func main() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("habit-recovery-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NativeStore(directory: directory)
        let first: [String: Any] = ["version": 1, "activeId": "test", "habits": [["id": "test", "name": "Original"]]]
        let second: [String: Any] = ["version": 1, "activeId": "test", "habits": [["id": "test", "name": "Changed"]]]
        try store.save(first)
        let empty = try store.recoveryCopies(); assert(empty.isEmpty)
        try store.save(second)
        let copies = try store.recoveryCopies()
        assert(copies.count == 1)
        let name = copies[0]["name"] as! String
        let restored = try store.recoveryCopy(named: name)
        assert(NSDictionary(dictionary: restored).isEqual(to: first))
        try store.save(second)
        let sameDay = try store.recoveryCopies(); assert(sameDay.count == 1)
        try store.save(first)
        let unchanged = try store.recoveryCopy(named: name); assert(NSDictionary(dictionary: unchanged).isEqual(to: first))
        do { _ = try store.recoveryCopy(named: "../state.json"); fatalError("Traversal accepted") }
        catch CocoaError.fileReadNoSuchFile { }
        let attributes = try FileManager.default.attributesOfItem(atPath: store.recoveryDirectory.appendingPathComponent(name).path)
        assert((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        for day in 1...20 {
            try JSONSerialization.data(withJSONObject: first).write(to: store.recoveryDirectory.appendingPathComponent(String(format: "recovery-2025-01-%02d.json", day)))
        }
        try store.save(second)
        let retained = try store.recoveryCopies()
        assert(retained.count == 14)
        assert(retained.first?["name"] as? String == name)
        try store.save(first, replacingUnreadable: true)
        let preserved = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        assert(preserved.contains(where: { $0.hasPrefix("before-restore-") }))
        assert(NativeStore(directory: directory).state?["activeId"] as? String == "test")
        print("PASS: previous data preserved once per day; latest 14 retained; private permissions; traversal refused; restore preserves current data; canonical saves reload")
    }
}
