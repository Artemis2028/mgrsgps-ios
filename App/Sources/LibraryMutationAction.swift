import Foundation
import GridFixCore

@MainActor
enum LibraryMutationAction {
    static func apply(_ edit: WaypointStore.LibraryEdit,to store: WaypointStore) async throws -> String? {
        try Task.checkCancellation()
        while true {
            let snapshot = store.restoreSnapshot()
            let prepared = try await Task.detached(priority: .userInitiated) { try snapshot.prepareLibrary(edit) }.value
            if try store.publishLibraryEdit(prepared) { return prepared.folder }
        }
    }

    /// Each durable repository phase is acknowledged before the next begins.
    /// A failed second phase leaves only its IDs selected, so retry cannot
    /// repeat a visibility swap that already committed.
    static func batch(_ selection: LibrarySelection,action: LibraryBatchAction,waypoints: WaypointStore,field: FieldDataStore) async -> LibraryBatches.Outcome {
        var remaining = selection, completed = 0
        remaining.retain(waypoints: Set(waypoints.waypoints.map(\.id)),graphics: Set(field.document.graphics.map(\.id)),tracks: Set(field.document.tracks.map(\.id)))
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
            if !remaining.graphics.isEmpty || !remaining.tracks.isEmpty {
                try await FieldEditAction.apply(.libraryBatch(graphicIDs: remaining.graphics,trackIDs: remaining.tracks,action: action),to: field)
                completed += remaining.graphics.count + remaining.tracks.count
            }
            return .init(completed: completed,remaining: LibrarySelection(),failure: nil)
        } catch { return .init(completed: completed,remaining: remaining,failure: error.localizedDescription) }
    }
}
