import GridFixCore

/// Shared additive store phases for backups and interchange. Each phase finishes
/// its atomic publication before its caller decides whether to start the next.
@MainActor
enum LibraryRestoreCommit {
    static func field(_ document: Backup.Document,into store: FieldDataStore) async throws -> Backup.RestoreResult {
        while true {
            let snapshot = try store.restoreSnapshot()
            let prepared = try await Task.detached(priority: .userInitiated) { try snapshot.prepare(document) }.value
            if let result = try store.publishRestore(prepared) { return result }
        }
    }

    static func waypoints(_ points: [Waypoint],folders: [FolderInfo],into store: WaypointStore) async throws -> Int {
        while true {
            let snapshot = store.restoreSnapshot()
            let prepared = try await Task.detached(priority: .userInitiated) { try snapshot.prepare(waypoints: points,folders: folders) }.value
            if let count = try store.publishRestore(prepared) { return count }
        }
    }
}
