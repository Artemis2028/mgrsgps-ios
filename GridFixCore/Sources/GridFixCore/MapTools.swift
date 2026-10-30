import Foundation

/// Android SettingsRepository.MapTools keys/order at 4c8216d. Visibility never
/// changes the active tool/session itself; active escape controls stay reachable.
public enum MapTools {
    public static let all = ["layers","locate","ruler","draw","goto","tools","record"]
    public static func decode(_ raw: String?) -> Set<String> {
        Set((raw ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { all.contains($0) })
    }
    public static func encode(_ keys: Set<String>) -> String { all.filter { keys.contains($0) }.joined(separator: ",") }
    public static func visible(hidden: Set<String>,active: Set<String> = []) -> [String] {
        all.filter { !hidden.contains($0) || active.contains($0) }
    }
    public static func title(_ key: String) -> String {
        switch key { case "layers": return "Layers"; case "locate": return "Locate"; case "ruler": return "Ruler"; case "draw": return "Draw"; case "goto": return "Go to"; case "tools": return "Tools"; case "record": return "Record"; default: return key }
    }
}
