import Foundation

/// Android release/1.1.0 geoUri: six decimal degrees and Android Uri.encode's
/// unreserved label characters. The payload carries the coordinate, not a
/// promise about its accuracy or the receiving camera's URI support.
public enum PositionShare {
    public static func geoURI(lat: Double, lon: Double, label: String) -> String? {
        guard lat.isFinite, lon.isFinite, (-90...90).contains(lat), (-180...180).contains(lon) else { return nil }
        let coordinate = String(format: "%.6f,%.6f", locale: Locale(identifier: "en_US_POSIX"), lat, lon)
        let name = label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Waypoint" : label
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-!.~'()*")
        guard let encoded = name.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return "geo:\(coordinate)?q=\(coordinate)(\(encoded))"
    }
}
