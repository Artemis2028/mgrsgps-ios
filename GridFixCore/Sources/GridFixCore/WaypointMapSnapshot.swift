import Foundation

/// One visibility rule for the map, its fit-to-waypoints action, and tests.
/// A selected navigation target does not bypass a hidden folder.
public enum WaypointMapSnapshot {
    public static func visible(waypoints: [Waypoint], folders: [FolderInfo]) -> [Waypoint] {
        // Preserve Foundation's comparison and first matching folder semantics,
        // but resolve each distinct folder once rather than once per waypoint.
        var visibility: [String: Bool] = [:]
        return waypoints.filter { waypoint in
            waypoint.visible && waypoint.lat.isFinite && waypoint.lon.isFinite
                && (-90...90).contains(waypoint.lat) && (-180...180).contains(waypoint.lon)
                && {
                    if let saved = visibility[waypoint.folder] { return saved }
                    let shown = folders.first {
                        $0.name.caseInsensitiveCompare(waypoint.folder) == .orderedSame
                    }?.visible ?? true
                    visibility[waypoint.folder] = shown
                    return shown
                }()
        }
    }
}
