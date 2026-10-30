import Foundation

/// A shared budget follows every supported member of a package while parsing.
/// Shapes share a point cap, matching ImportCoordinator's final combined check.
final class ImportParseBudget {
    private var waypoints = 0, shapes = 0, tracks = 0, savedShapePoints = 0, trackPoints = 0
    var recordLimit = 10_000, pointLimit = 250_000
    func waypoint() throws { waypoints += 1; try check(waypoints,recordLimit,"waypoints") }
    func shape() throws { shapes += 1; try check(shapes,recordLimit,"lines and areas") }
    func track() throws { tracks += 1; try check(tracks,recordLimit,"tracks") }
    func shapePoints(_ n: Int = 1) throws { savedShapePoints += n; try check(savedShapePoints,pointLimit,"shape points") }
    func trackPoint() throws { trackPoints += 1; try check(trackPoints,pointLimit,"track points") }
    private func check(_ count: Int,_ limit: Int,_ label: String) throws {
        if count > limit { throw BackupError.notABackup("Too many imported \(label) (limit \(limit))") }
    }
}
