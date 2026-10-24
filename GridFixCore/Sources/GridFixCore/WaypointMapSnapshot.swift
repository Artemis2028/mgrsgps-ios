import Foundation

/// One visibility rule for the map, its fit-to-waypoints action, and tests.
/// A selected navigation target does not bypass a hidden folder.
public enum WaypointMapSnapshot {
    public static func visible(waypoints: [Waypoint], folders: [FolderInfo]) -> [Waypoint] {
        waypoints.filter { waypoint in
            waypoint.visible && waypoint.lat.isFinite && waypoint.lon.isFinite
                && (-90...90).contains(waypoint.lat) && (-180...180).contains(waypoint.lon)
                && (folders.first {
                    $0.name.caseInsensitiveCompare(waypoint.folder) == .orderedSame
                }?.visible ?? true)
        }
    }
}
