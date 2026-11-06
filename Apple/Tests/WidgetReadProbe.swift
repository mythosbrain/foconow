import Foundation
import Darwin

/// Runs as a separate locally signed, sandboxed process using the widget's exact file entitlement.
/// Reports booleans only; it does not copy or print personal record contents.
@main
struct WidgetReadProbe {
    static func main() throws {
        guard let directory = getpwuid(getuid())?.pointee.pw_dir else { exit(2) }
        let home = URL(fileURLWithPath: String(cString: directory), isDirectory: true)
        let support = home.appendingPathComponent("Library/Application Support/com.yassine.habitcounter", isDirectory: true)
        let summary = WidgetSummary.read(support.appendingPathComponent(WidgetSummary.filename))
        let canonicalRead = try? Data(contentsOf: support.appendingPathComponent("state.json"))
        let result = ["summaryReadable": summary != nil, "canonicalDatabaseDenied": canonicalRead == nil]
        print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
        if summary == nil || canonicalRead != nil { exit(1) }
    }
}
