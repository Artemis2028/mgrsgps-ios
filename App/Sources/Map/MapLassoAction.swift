import GridFixCore

@MainActor
enum MapLassoAction {
    struct Outcome {
        let completed: Int
        let remaining: LibrarySelection
        let error: String?
    }
    /// Independent repositories, as on Android. Keep only unfinished IDs on
    /// failure; explicit Hide is idempotent even after concurrent changes.
    static func apply(_ selection: LibrarySelection,action: LibraryBatchAction,waypoints: WaypointStore,field: FieldDataStore) async -> Outcome {
        var remaining = selection, completed = 0
        remaining.tracks = [] // Tracks/remote TAK items are outside map lasso.
        remaining.retain(waypoints: Set(waypoints.waypoints.map(\.id)),graphics: Set(field.document.graphics.map(\.id)),tracks: [])
        do {
            try Task.checkCancellation()
            if !remaining.waypoints.isEmpty {
                while true {
                    let snapshot = waypoints.restoreSnapshot(), ids = remaining.waypoints
                    let prepared = try await Task.detached(priority: .userInitiated) { try snapshot.prepareBatch(ids: ids,action: action) }.value
                    if try waypoints.publishBatch(prepared) { break }
                }
                completed += remaining.waypoints.count; remaining.waypoints = []
            }
            if !remaining.graphics.isEmpty {
                try await FieldEditAction.apply(.libraryBatch(graphicIDs: remaining.graphics,trackIDs: [],action: action),to: field)
                completed += remaining.graphics.count; remaining.graphics = []
            }
            return .init(completed: completed,remaining: remaining,error: nil)
        } catch { return .init(completed: completed,remaining: remaining,error: error.localizedDescription) }
    }
}
