import Foundation
import GridFixCore

@MainActor
enum TrackBacktrackAction {
    enum Failure: LocalizedError {
        case changed
        var errorDescription: String? { "The saved track changed while building its backtrack route. Try again." }
    }
    static func create(track: Backup.TrackMeta,field: FieldDataStore,waypoints: WaypointStore,
                       build: (@Sendable (Backup.TrackMeta,Data) async throws -> Backup.Graphic)? = nil,
                       prepare: @escaping @Sendable (FieldDataStore.RestoreSnapshot,Backup.Graphic) async throws -> FieldDataStore.PreparedEdit = { try $0.prepare(edit: .createGraphic($1)) }) async throws -> Backup.Graphic {
        while true {
            try Task.checkCancellation()
            let source = try field.trackReadSnapshot(track.id)
            let worker = Task.detached(priority: .userInitiated) {
                if let build { return try await build(source.track,source.readBytes()) }
                return try TrackBacktrack.route(track: source.track,visit: source.visitPoints)
            }
            var route = try await withTaskCancellationHandler(operation: { try await worker.value },onCancel: { worker.cancel() })
            try Task.checkCancellation()
            // A changed source during calculation must be rebuilt from the
            // current immutable log, including its latest name and folder.
            guard field.isCurrent(source) else { continue }
            guard let folder = try await LibraryMutationAction.apply(.folderVisibility(source.track.folder,true),to: waypoints) else { throw Failure.changed }
            route.folder = folder
            try Task.checkCancellation()
            guard field.isCurrent(source) else { throw Failure.changed }
            let snapshot = try field.restoreSnapshot(), result = route
            let saving = Task.detached(priority: .userInitiated) { try await prepare(snapshot,result) }
            let prepared = try await withTaskCancellationHandler(operation: { try await saving.value },onCancel: { saving.cancel() })
            try Task.checkCancellation()
            // No await between this check and atomic publish. Do not rebase
            // source-derived geometry over replacement/deletion during staging.
            guard field.isCurrent(source) else { throw Failure.changed }
            guard try field.publishEdit(prepared) else { throw Failure.changed }
            return route
        }
    }
}
