import GridFixCore
import UIKit

/// Interchange presentation does not change a waypoint's tactical affiliation.
struct WaypointMarkerStyle {
    let waypoint: Waypoint
    let night: Bool

    var character: String? { MilGpsSymbols.decode(waypoint.metadata.milgpsSymbolCode)?.character }
    var symbolName: String {
        guard let symbol = MilGpsSymbols.decode(waypoint.metadata.milgpsSymbolCode) else { return "mappin.circle.fill" }
        switch symbol.shape {
        case .cross: return "plus"
        case .circle: return "circle.fill"
        case .triangle: return "triangle.fill"
        case .square: return "square.fill"
        case .star: return "star.fill"
        }
    }

    var color: UIColor {
        if night { return .systemRed }
        switch waypoint.metadata.color?.lowercased() {
        case "red": return UIColor(red: 1, green: 0, blue: 0, alpha: 1)
        case "orange": return UIColor(red: 1, green: 0.584, blue: 0, alpha: 1)
        case "yellow": return .yellow
        case "green": return UIColor(red: 0, green: 0.867, blue: 0, alpha: 1)
        case "blue": return UIColor(red: 0, green: 0.502, blue: 1, alpha: 1)
        case "cyan": return UIColor(red: 0, green: 0.867, blue: 0.867, alpha: 1)
        case "magenta": return UIColor(red: 0.933, green: 0, blue: 0.933, alpha: 1)
        default: return UIColor(red: 1, green: 0.72, blue: 0.16, alpha: 1)
        }
    }
}
