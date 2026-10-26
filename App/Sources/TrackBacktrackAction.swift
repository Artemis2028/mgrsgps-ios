import Foundation
import GridFixCore

@MainActor
enum TrackBacktrackAction {
    enum Failure: LocalizedError {
        case removed
        var errorDescription: String? { "This track is no longer saved." }
    }
    static func create(track: Backup.TrackMeta,field: FieldDataStore,waypoints: WaypointStore) async throws -> Backup.Graphic {
        guard field.document.tracks.contains(where: { $0.id == track.id }) else { throw Failure.removed }
        // Decode and simplify the whole log off the UI thread. The original
        // recording remains untouched; no target selection or GPS is started.
        var route = try await Task.detached(priority: .userInitiated) {
            try TrackBacktrack.route(track: track,points: field.points(for: track.id))
        }.value
        try Task.checkCancellation()
        guard let current = field.document.tracks.first(where: { $0.id == track.id }) else { throw Failure.removed }
        route.name = String(("Back "+current.name).prefix(20))
        guard let folder = try await LibraryMutationAction.apply(.folderVisibility(current.folder,true),to: waypoints) else { throw Failure.removed }
        route.folder = folder
        guard field.document.tracks.contains(where: { $0.id == track.id }) else { throw Failure.removed }
        try await FieldEditAction.apply(.createGraphic(route),to: field)
        return route
    }
}
