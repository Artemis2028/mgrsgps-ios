import Foundation
import GridFixCore

@MainActor
enum RouteWaypointAction {
    static func generate(_ route: Backup.Graphic,to store: WaypointStore,field: FieldDataStore,
                         validate: @escaping @MainActor () throws -> Void = {}) async throws {
        func checkSource() throws {
            try Task.checkCancellation()
            try validate()
            guard route.type == "route", (2...10_000).contains(route.points.count),
                  field.document.graphics.contains(route) else {
                throw BoundaryError.invalid("The route changed or was deleted. Reopen it before generating waypoints.")
            }
        }
        try checkSource()
        let reference = route.name.range(of: "^RT[1-9][0-9]*$", options: [.regularExpression, .caseInsensitive]) != nil
            ? route.name : AutomaticNames.next(prefix: "RT", among: field.document.graphics.filter { $0.type == "route" }.map(\.name))
        let edit = await Task.detached(priority: .userInitiated) {
            WaypointStore.RouteEdit(routeID: route.id,name: reference,points: route.points.map { GeoPoint(lat: $0.lat,lon: $0.lon) },folder: route.folder)
        }.value
        while true {
            try checkSource()
            let snapshot = store.restoreSnapshot()
            let prepared = try await Task.detached(priority: .userInitiated) { try snapshot.prepareRoute(edit) }.value
            try checkSource()
            if try store.publishBatch(prepared) { return }
        }
    }
}
