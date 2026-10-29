import Foundation
import GridFixCore

@MainActor
enum TrackMapFocusAction {
    struct Prepared {
        let points: [GeoPoint]
        let trackID: String
        private let source: FieldDataStore.TrackReadSnapshot
        fileprivate init(points: [GeoPoint],source: FieldDataStore.TrackReadSnapshot) {
            self.points = points; self.source = source; trackID = source.track.id
        }
        func isCurrent(in field: FieldDataStore) -> Bool { field.isCurrent(source) }
    }
    enum Failure: LocalizedError {
        case empty, changed
        var errorDescription: String? {
            switch self {
            case .empty: return "This track has no saved points to show."
            case .changed: return "The saved track changed while opening. Try again."
            }
        }
    }
    static func prepare(trackID: String,field: FieldDataStore,waypoints: WaypointStore,
                        scan: (@Sendable (Data) async throws -> [GeoPoint])? = nil) async throws -> Prepared {
        while true {
            try Task.checkCancellation()
            let source = try field.trackReadSnapshot(trackID)
            let worker = Task.detached(priority: .userInitiated) {
                if let scan { return try await scan(source.readBytes()) }
                return try FieldMapGeometry.trackFitPoints(visit: source.visitPoints)
            }
            let points = try await withTaskCancellationHandler(operation: { try await worker.value },onCancel: { worker.cancel() })
            try Task.checkCancellation()
            guard field.isCurrent(source) else { continue }
            guard !points.isEmpty else { throw Failure.empty }
            if waypoints.folders.first(where: { $0.name == source.track.folder })?.visible == false {
                _ = try await LibraryMutationAction.apply(.folderVisibility(source.track.folder,true),to: waypoints)
            }
            try Task.checkCancellation()
            guard field.isCurrent(source) else { throw Failure.changed }
            return .init(points: points,source: source)
        }
    }
}
