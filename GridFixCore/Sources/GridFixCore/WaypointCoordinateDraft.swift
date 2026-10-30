import Foundation

/// Coordinate entry shared by add and edit. A name-only edit must not move a
/// recorded fix to the centre of the grid cell used to display it.
public struct WaypointCoordinateDraft {
    public enum Format: String, CaseIterable, Sendable {
        case mgrs = "MGRS"
        case decimal = "Lat / Lon"
    }

    public struct Position: Equatable, Sendable {
        public let lat: Double
        public let lon: Double
    }

    public var format: Format = .mgrs
    public var grid = ""
    public var latitude = ""
    public var longitude = ""
    private var original: Position?
    private var originalGrid = ""

    public init(lat: Double? = nil, lon: Double? = nil) {
        guard let lat, let lon, Self.valid(lat: lat, lon: lon) else { return }
        original = Position(lat: lat, lon: lon)
        grid = MGRS.parts(lat: lat, lon: lon, digits: 10)?.full ?? ""
        originalGrid = grid
        latitude = String(lat)
        longitude = String(lon)
        if grid.isEmpty { format = .decimal }
    }

    public var position: Position? {
        switch format {
        case .mgrs:
            let compact = grid.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                .replacingOccurrences(of: "^(MGRS|USNG)[:\\s]*", with: "", options: .regularExpression)
                .filter { !$0.isWhitespace }
            guard compact.range(of: "^[0-9]{1,2}[C-HJ-NP-X][A-HJ-NP-Z]{2}([0-9]{4}|[0-9]{6}|[0-9]{8}|[0-9]{10})$",
                                options: .regularExpression) != nil else { return nil }
            if compact == originalGrid.filter({ !$0.isWhitespace }), let original {
                return original
            }
            guard let p = MGRS.parse(compact), Self.valid(lat: p.lat, lon: p.lon) else { return nil }
            return Position(lat: p.lat, lon: p.lon)
        case .decimal:
            guard let lat = Double(latitude.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let lon = Double(longitude.trimmingCharacters(in: .whitespacesAndNewlines)),
                  Self.valid(lat: lat, lon: lon) else { return nil }
            return Position(lat: lat, lon: lon)
        }
    }

    public var validationMessage: String? {
        guard position == nil else { return nil }
        return format == .mgrs
            ? "Enter a zone, square, and 4, 6, 8, or 10 grid digits. Easting and northing must have equal lengths."
            : "Enter latitude from −90 to 90 and longitude from −180 to 180 in decimal degrees. Use a minus sign for south or west."
    }

    public mutating func changeFormat(to next: Format) {
        guard next != format else { return }
        if let p = position {
            // Convert a valid entry; changing presentation never moves it.
            self = WaypointCoordinateDraft(lat: p.lat, lon: p.lon)
        }
        format = next
    }

    private static func valid(lat: Double, lon: Double) -> Bool {
        lat.isFinite && lon.isFinite && (-90...90).contains(lat) && (-180...180).contains(lon)
    }
}
