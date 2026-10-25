import GridFixCore

@MainActor
enum WaypointEditAction {
    /// Keep the store mutation on the UI executor, with encoding and staging on
    /// a worker. A concurrent edit/selection requests a fresh snapshot.
    static func save(_ edit: WaypointStore.Edit,to store: WaypointStore) async throws -> Waypoint {
        try Task.checkCancellation()
        while true {
            let snapshot = store.restoreSnapshot()
            let prepared = try await Task.detached(priority: .userInitiated) { try snapshot.prepare(edit: edit) }.value
            if let result = try store.publishEdit(prepared) { return result }
        }
    }
}
