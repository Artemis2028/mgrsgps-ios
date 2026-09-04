import Foundation

/// Folder naming, identical to Android's `app.gridfix.core.Folders`.
///
/// Frozen since 0.9.9: the legacy "Waypoints" and "Graphics" folders and the
/// blank name all collapse into one base folder, so a single eye switch clears
/// the map. Matching is case-insensitive against folders already in use, which
/// is why "recon" and "Recon" are one folder and not two.
public enum Folders {

    public static let defaultFolder = "Base"

    /// A folder name as stored.
    public static func canonical(_ raw: String?) -> String {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed {
        case "", "Waypoints", "Graphics": return defaultFolder
        default: return trimmed
        }
    }

    /// A one-line warning for folder-name fields when the typed name will not
    /// be kept as typed.
    public static func reservedHint(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty || t == defaultFolder { return nil }
        guard canonical(t) == defaultFolder else { return nil }
        return "\"\(t)\" is a reserved name — this goes into \(defaultFolder)"
    }

    /// The stored spelling of a folder. `known` is every folder currently in
    /// use; the first case-insensitive match wins.
    public static func match(known: [String], raw: String?) -> String {
        let clean = canonical(raw)
        return known.first { $0.caseInsensitiveCompare(clean) == .orderedSame } ?? clean
    }
}
