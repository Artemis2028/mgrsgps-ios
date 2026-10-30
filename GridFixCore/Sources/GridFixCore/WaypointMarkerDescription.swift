import Foundation

/// Describe the artwork's precedence rather than a hidden fallback symbol.
/// Imported MilGPS shape/character overrides the base glyph, frame and echelon.
public enum WaypointMarkerDescription {
    private static let units = Set(MilitarySymbols.unitKeys)
    private static let tasks = Set(MilitarySymbols.tasks.map(\.key))
    private static let basic = Set(MilitarySymbols.basic.map(\.key))

    public static func text(symbol: String,affiliation: String = "none",echelon: String = "",metadata: WaypointMetadata = .init()) -> String {
        if let imported = MilGpsSymbols.decode(metadata.milgpsSymbolCode) {
            let character: String?
            switch imported.character {
            case "!": character = "exclamation mark"
            case "?": character = "question mark"
            default: character = imported.character
            }
            return [imported.shape.label,character,"marker"].compactMap { $0 }.joined(separator: " ")
        }
        let isUnit = units.contains(symbol)
        var labels = [isUnit || tasks.contains(symbol) || basic.contains(symbol)
                      ? MilitarySymbols.label(symbol)
                      : symbol.isEmpty ? "Unrecognized marker" : "Unrecognized symbol \(symbol)"]
        // Unit affiliation is encoded by the catalog key, even if legacy
        // waypoint metadata has a different affiliation alongside it.
        if !isUnit,affiliation != "none",let label = MilitarySymbols.affiliations.first(where: { $0.key == affiliation })?.label {
            labels.append(label)
        }
        // The task renderer returns before the echelon overlay is drawn.
        if !symbol.hasPrefix("task_"),!echelon.isEmpty,let label = MilitarySymbols.echelons.first(where: { $0.key == echelon })?.label {
            labels.append(label)
        }
        return labels.joined(separator: ", ")
    }
    public static func text(_ waypoint: Waypoint) -> String {
        text(symbol: waypoint.symbol,affiliation: waypoint.affiliation,echelon: waypoint.echelon,metadata: waypoint.metadata)
    }
    public static func text(_ point: WatchMapSnapshot.Point) -> String {
        text(symbol: point.symbol,affiliation: point.affiliation,echelon: point.echelon,
             metadata: .init(color: point.importedColor,milgpsSymbolCode: point.importedCode))
    }
}
