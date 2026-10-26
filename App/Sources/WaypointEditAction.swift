import GridFixCore

@MainActor
enum WaypointEditAction {
    /// Cancelled navigation startup must not publish after its worker finishes.
    static func select(_ id: String?,in store: WaypointStore,
                       validate: @MainActor () throws -> Void = {}) async throws {
        try Task.checkCancellation()
        let intent = store.beginSelection()
        func check() throws {
            try Task.checkCancellation()
            guard store.selectionIsCurrent(intent) else { throw CancellationError() }
            try validate()
        }
        while true {
            try check()
            let snapshot = store.restoreSnapshot()
            let prepared = try await Task.detached(priority: .userInitiated) { try snapshot.prepareSelection(id) }.value
            try check()
            if try store.publishSelection(prepared) { return }
        }
    }

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
