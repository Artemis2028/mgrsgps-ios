import Foundation

/// Names are allocated against the saved snapshot, so retries cannot publish
/// duplicate suggestions made while an editor was open.
public enum AutomaticNames {
    public static func next(prefix: String, among names: [String]) -> String {
        let upper = prefix.uppercased()
        let used = Set(names.map { $0.uppercased() })
        let largest = used.compactMap { value -> Int? in
            guard value.hasPrefix(upper) else { return nil }
            let suffix = value.dropFirst(upper.count)
            guard !suffix.isEmpty, suffix.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            return Int(suffix)
        }.max() ?? 0
        var number = largest < Int.max ? largest + 1 : 1
        while used.contains(upper + String(number)) { number += 1 }
        return prefix + String(number)
    }

    public static func waypoint(_ draft: WaypointDraft, among points: [Waypoint], excluding id: String? = nil) -> String {
        let entered = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !entered.isEmpty { return entered }
        let prefix: String
        if draft.kind == KIND_UNIT || MilitarySymbols.function(draft.symbol) != nil {
            let symbolAffiliation = draft.symbol.split(separator: "_").dropFirst().first.map(String.init)
            let affiliation: String
            switch draft.affiliation {
            case "friendly": affiliation = "FRN"
            case "hostile": affiliation = "EN"
            case "neutral": affiliation = "NTRL"
            case "unknown": affiliation = "UNK"
            default: affiliation = ["f":"FRN","h":"EN","n":"NTRL","u":"UNK"][symbolAffiliation ?? ""] ?? "UNK"
            }
            let unit = (MilitarySymbols.function(draft.symbol) ?? "unit").uppercased().replacingOccurrences(of: "_", with: "-")
            let echelon = draft.echelon.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            prefix = affiliation + "-" + unit + (echelon.isEmpty ? "" : "-" + echelon) + "-"
        } else { prefix = "WP" }
        return next(prefix: prefix, among: points.filter { $0.id != id }.map(\.name))
    }

    public static func graphic(_ graphic: Backup.Graphic, among graphics: [Backup.Graphic]) -> String {
        let entered = graphic.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !entered.isEmpty { return entered }
        let prefix = graphic.type == "route" ? "RT" : graphic.type.uppercased().replacingOccurrences(of: "_", with: "-")
        return next(prefix: prefix, among: graphics.filter { $0.id != graphic.id }.map(\.name))
    }

    public static func routePrefix(id: String, name: String, among points: [Waypoint]) -> String {
        func prefix(_ name: String) -> String? {
            let parts = name.uppercased().components(separatedBy: "WP")
            guard parts.count == 2, parts[0].hasPrefix("RT"), Int(parts[0].dropFirst(2)) != nil, Int(parts[1]) != nil else { return nil }
            return parts[0]
        }
        if let existing = points.first(where: { $0.sourceRouteId == id && prefix($0.name) != nil }) { return prefix(existing.name)! }
        let occupied = points.filter { $0.sourceRouteId != id }.compactMap { prefix($0.name) }
        let entered = name.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if entered.hasPrefix("RT"), let n = Int(entered.dropFirst(2)), n > 0, !occupied.contains(entered) { return entered }
        return next(prefix: "RT", among: occupied)
    }
}
