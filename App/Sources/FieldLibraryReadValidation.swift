#if DEBUG
import GridFixCore
import SwiftUI

/// Only synthetic UI-test data. The app's retry still uses the real worker
/// reader; repair simulates an external source becoming readable in-session.
enum FieldLibraryReadValidation {
    static var enabled: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-uiTesting") && args.contains("-uiTestFieldReadRecovery") && args.contains("-uiTestDeferredFieldLoad")
    }
    private static var directory: URL { FileManager.default.temporaryDirectory.appendingPathComponent("mgrsgps-ui-tests",isDirectory:true) }
    private static let backupName = "synthetic-readable-field-index.json"
    static func seed(in target: URL) {
        guard enabled,target.standardizedFileURL == directory.standardizedFileURL else { return }
        do {
            var doc = Backup.Document(); doc.hasSettings = false
            doc.graphics = [.init(id:"recovery-route",name:"Recovered CAFÉ route",type:"route",points:[.init(lat:24,lon:54),.init(lat:24.01,lon:54)])]
            let (track,bytes) = try TrackCodec.imported(name:"Recovered patrol",points:[.init(lat:24,lon:54),.init(lat:24.01,lon:54)],now:1000)
            doc.tracks = [track]; doc.trackFiles[track.id] = bytes
            try FieldDataStore(directory:target).restore(doc)
            let index = target.appendingPathComponent("field-data-v2.json")
            try Data(contentsOf:index).write(to:target.appendingPathComponent(backupName),options:.atomic)
            try Data("SYNTHETIC unreadable field index\n".utf8).write(to:index,options:.atomic)
        } catch { assertionFailure("Could not prepare synthetic field-read fixture") }
    }
    static func repair() throws {
        guard enabled else { return }
        try Data(contentsOf:directory.appendingPathComponent(backupName))
            .write(to:directory.appendingPathComponent("field-data-v2.json"),options:.atomic)
    }
}

struct FieldLibraryReadValidationRepair: View {
    let identifier: String
    @State private var status: String?
    var body: some View {
        if FieldLibraryReadValidation.enabled {
            Button("Repair synthetic test index") {
                do { try FieldLibraryReadValidation.repair(); status = "Synthetic source repaired" }
                catch { status = "Synthetic source repair failed" }
            }.frame(minHeight:44).accessibilityIdentifier(identifier)
            if let status { Text(status).font(.caption).accessibilityIdentifier(identifier + "-status") }
        }
    }
}
#endif
