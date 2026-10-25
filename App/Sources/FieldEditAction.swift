import Foundation
import GridFixCore

@MainActor
enum FieldEditAction {
    /// A confirmed atomic phase finishes even if its owner leaves. Rebase only
    /// after a stale preparation; never retry a successfully published toggle.
    static func apply(_ edit: FieldDataStore.Edit,to store: FieldDataStore) async throws {
        try Task.checkCancellation()
        while true {
            let snapshot = try store.restoreSnapshot()
            let prepared = try await Task.detached(priority: .userInitiated) { try snapshot.prepare(edit: edit) }.value
            if try store.publishEdit(prepared) { return }
        }
    }

    static func saveGraphic(_ graphic: Backup.Graphic,original: Backup.Graphic?,field: FieldDataStore,waypoints: WaypointStore) async throws -> Backup.Graphic {
        let edit = original.map { FieldDataStore.Edit.editGraphic(original: $0,updated: graphic) } ?? .createGraphic(graphic)
        try await apply(edit,to: field)
        guard let saved = field.document.graphics.first(where: { $0.id == graphic.id }) else { throw Failure.removed }
        do { _ = try await LibraryRestoreCommit.waypoints([],folders: [.init(name: saved.folder)],into: waypoints) }
        catch { throw Failure.folder(error.localizedDescription) }
        guard let current = field.document.graphics.first(where: { $0.id == graphic.id }) else { throw Failure.removed }
        return current
    }
    enum Failure: LocalizedError {
        case removed,folder(String)
        var errorDescription: String? {
            switch self {
            case .removed: return "This graphic is no longer saved. Your draft is kept."
            case .folder(let error): return "Graphic saved. Could not finish its folder settings: \(error). Retry to finish; the saved graphic is kept."
            }
        }
    }
}
