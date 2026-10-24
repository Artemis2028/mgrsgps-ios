import GridFixCore

@MainActor
enum BackupCoordinator {
    /// Match Android's ordered, additive restore. Report any sections already
    /// committed when a later write fails; retrying never replaces current IDs.
    static func restore(_ document: Backup.Document, waypoints: WaypointStore,
                        fieldData: FieldDataStore, settings: AppSettings) -> String {
        var applied: [String] = []
        do {
            try Backup.validate(document)
            let result = try fieldData.restore(document)
            if result.graphics > 0 { applied.append("\(result.graphics) graphics/routes") }
            if result.tracks > 0 { applied.append("\(result.tracks) tracks") }
            if result.course > 0 { applied.append("\(result.course) course results") }
            var folders = document.folders
            for name in Set(document.graphics.map(\.folder) + document.tracks.map(\.folder)) where !folders.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                folders.append(FolderInfo(name: name))
            }
            let count = try waypoints.restore(waypoints: document.waypoints, folders: folders)
            if count > 0 { applied.append("\(count) waypoints") }
            if document.hasSettings { try settings.applyBackup(document.settings); applied.append("settings") }
            return applied.isEmpty ? "Nothing new to restore" : "Restored " + applied.joined(separator: ", ")
        } catch {
            let progress = applied.isEmpty ? "No records added." : "Already restored: " + applied.joined(separator: ", ") + "."
            return "Restore stopped: \(error.localizedDescription). \(progress) You can retry."
        }
    }
}
