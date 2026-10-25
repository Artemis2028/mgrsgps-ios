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
            if !document.tracks.isEmpty {
                var tracks = Backup.Document(); tracks.hasSettings = false
                tracks.tracks = document.tracks; tracks.trackFiles = document.trackFiles
                let count = try fieldData.restore(tracks).tracks
                if count > 0 { applied.append("\(count) tracks") }
            }
            var folders = document.folders
            for name in Set(document.graphics.map(\.folder) + document.tracks.map(\.folder)) where !folders.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                folders.append(FolderInfo(name: name))
            }
            let count = try waypoints.restore(waypoints: document.waypoints, folders: folders)
            if count > 0 { applied.append("\(count) waypoints") }
            if !document.graphics.isEmpty {
                var graphics = Backup.Document(); graphics.hasSettings = false; graphics.graphics = document.graphics
                let count = try fieldData.restore(graphics).graphics
                if count > 0 { applied.append("\(count) graphics/routes") }
            }
            if !document.courseHistory.isEmpty {
                var course = Backup.Document(); course.hasSettings = false; course.courseHistory = document.courseHistory
                let count = try fieldData.restore(course).course
                if count > 0 { applied.append("\(count) course results") }
            }
            if document.hasSettings { try settings.applyBackup(document.settings); applied.append("settings") }
            return applied.isEmpty ? "Nothing new to restore" : "Restored " + applied.joined(separator: ", ")
        } catch {
            let progress = applied.isEmpty ? "No records added." : "Already restored: " + applied.joined(separator: ", ") + "."
            return "Restore stopped: \(error.localizedDescription). \(progress) You can retry."
        }
    }
}
