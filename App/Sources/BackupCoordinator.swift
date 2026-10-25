import Foundation
import GridFixCore

@MainActor
enum BackupCoordinator {
    /// Once publication starts, finish/report ordered phases even if the caller
    /// goes away, like Android's NonCancellable restore. Worker tasks do not
    /// inherit cancellation. Each stale snapshot is rebuilt from current data.
    static func restore(_ document: Backup.Document,waypoints: WaypointStore,
                        fieldData: FieldDataStore,settings: AppSettings,lanes: NavigationLaneStore? = nil) async -> String {
        var applied: [String] = []
        do {
            try await Task.detached(priority: .userInitiated) { try Backup.validate(document) }.value
            if !document.navLanes.isEmpty && lanes == nil { throw LaneRestoreUnavailable() }
            if !document.tracks.isEmpty {
                var tracks = Backup.Document(); tracks.hasSettings = false
                tracks.tracks = document.tracks; tracks.trackFiles = document.trackFiles
                let count = try await LibraryRestoreCommit.field(tracks,into: fieldData).tracks
                if count > 0 { applied.append("\(count) tracks") }
            }
            let folders = await Task.detached(priority: .userInitiated) {
                var folders = document.folders
                for name in Set(document.graphics.map(\.folder)+document.tracks.map(\.folder)+document.navLanes.map(\.folder)) where !folders.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                    folders.append(FolderInfo(name: name))
                }
                return folders
            }.value
            let count = try await LibraryRestoreCommit.waypoints(document.waypoints,folders: folders,into: waypoints)
            if count > 0 { applied.append("\(count) waypoints") }
            if !document.graphics.isEmpty {
                var graphics = Backup.Document(); graphics.hasSettings = false; graphics.graphics = document.graphics
                let count = try await LibraryRestoreCommit.field(graphics,into: fieldData).graphics
                if count > 0 { applied.append("\(count) graphics/routes") }
            }
            if !document.navLanes.isEmpty,let lanes {
                let count = try await lanes.restore(document.navLanes)
                if count > 0 { applied.append(count == 1 ? "1 navigation lane" : "\(count) navigation lanes") }
            }
            if !document.courseHistory.isEmpty {
                var course = Backup.Document(); course.hasSettings = false; course.courseHistory = document.courseHistory
                let count = try await LibraryRestoreCommit.field(course,into: fieldData).course
                if count > 0 { applied.append("\(count) course results") }
            }
            if document.hasSettings {
                while true {
                    let snapshot = settings.restoreSnapshot()
                    let prepared = try await Task.detached(priority: .userInitiated) { try snapshot.prepare(document.settings) }.value
                    if try settings.publishRestore(prepared) { applied.append("settings"); break }
                }
            }
            return applied.isEmpty ? "Nothing new to restore" : "Restored "+applied.joined(separator: ", ")
        } catch {
            let progress = applied.isEmpty ? "No records added." : "Already restored: "+applied.joined(separator: ", ")+"."
            return "Restore stopped: \(error.localizedDescription). \(progress) You can retry."
        }
    }
}

private struct LaneRestoreUnavailable: LocalizedError {
    var errorDescription: String? { "Navigation lane storage is unavailable" }
}
