import Foundation

/// Waypoint and folder models matching Android `WaypointRepository` at 0.9.32.
public let KIND_WP = "wp"
public let KIND_UNIT = "unit"
public let DEFAULT_SYMBOL = "flag"

/// Optional interchange fields; independent of a waypoint's tactical affiliation.
public struct WaypointMetadata: Equatable, Sendable, Codable {
    public var color: String?
    public var milgpsSymbolCode: Int?
    public var elevationMeters: Double?
    public var timestampMillis: Int64?

    public init(color: String? = nil, milgpsSymbolCode: Int? = nil,
                elevationMeters: Double? = nil, timestampMillis: Int64? = nil) {
        self.color = color
        self.milgpsSymbolCode = milgpsSymbolCode
        self.elevationMeters = elevationMeters
        self.timestampMillis = timestampMillis
    }
}

public struct Waypoint: Equatable, Sendable, Identifiable, Codable {
    public var id: String
    public var name: String
    public var lat: Double
    public var lon: Double
    public var createdAt: Int64
    public var folder: String
    public var symbol: String
    public var affiliation: String
    public var echelon: String
    public var designation: String
    public var kind: String
    public var rotation: Double
    public var visible: Bool
    public var metadata: WaypointMetadata

    public init(id: String = UUID().uuidString,
                name: String,
                lat: Double,
                lon: Double,
                createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
                folder: String = Folders.defaultFolder,
                symbol: String = DEFAULT_SYMBOL,
                affiliation: String = "none",
                echelon: String = "",
                designation: String = "",
                kind: String = KIND_WP,
                rotation: Double = 0,
                visible: Bool = true,
                metadata: WaypointMetadata = WaypointMetadata()) {
        self.id = id
        self.name = name
        self.lat = lat
        self.lon = lon
        self.createdAt = createdAt
        self.folder = Folders.canonical(folder)
        self.symbol = symbol
        self.affiliation = affiliation
        self.echelon = echelon
        self.designation = designation
        self.kind = kind
        self.rotation = rotation
        self.visible = visible
        self.metadata = metadata
    }
}

/// Everything needed to create or update a waypoint.
public struct WaypointDraft: Equatable, Sendable {
    public var name: String
    public var lat: Double
    public var lon: Double
    public var folder: String
    public var symbol: String
    public var affiliation: String
    public var echelon: String
    public var designation: String
    public var kind: String
    public var rotation: Double
    /// Nil on ordinary edits means retain the existing interchange metadata.
    public var metadata: WaypointMetadata?

    public init(name: String, lat: Double, lon: Double,
                folder: String = Folders.defaultFolder,
                symbol: String = DEFAULT_SYMBOL,
                affiliation: String = "none",
                echelon: String = "",
                designation: String = "",
                kind: String = KIND_WP,
                rotation: Double = 0,
                metadata: WaypointMetadata? = nil) {
        self.name = name
        self.lat = lat
        self.lon = lon
        self.folder = folder
        self.symbol = symbol
        self.affiliation = affiliation
        self.echelon = echelon
        self.designation = designation
        self.kind = kind
        self.rotation = rotation
        self.metadata = metadata
    }
}

public struct FolderInfo: Equatable, Sendable, Identifiable, Codable {
    public var name: String
    public var visible: Bool
    public var id: String { name }

    public init(name: String, visible: Bool = true) {
        self.name = name
        self.visible = visible
    }
}

public enum MilGpsShape: Int, CaseIterable, Sendable {
    case cross = 0, circle, triangle, square, star
    public var label: String {
        switch self {
        case .cross: return "Cross"
        case .circle: return "Circle"
        case .triangle: return "Triangle"
        case .square: return "Square"
        case .star: return "Star"
        }
    }
}

public struct MilGpsSymbol: Equatable, Sendable {
    public let shape: MilGpsShape
    public let character: String?
}

/// Documented by https://milgps.com/userguide/frequently-asked-questions/csv-format/
public enum MilGpsSymbols {
    public static let colors = ["red", "orange", "yellow", "green", "blue", "cyan", "magenta"]
    public static let characters: [String] =
        (0...9).map(String.init)
        + (65...90).compactMap { UnicodeScalar(UInt32($0)).map(String.init) }
        + ["!", "?"]

    public static func decode(_ code: Int?) -> MilGpsSymbol? {
        guard let code, code >= 0 else { return nil }
        guard let shape = MilGpsShape(rawValue: code / 1000) else { return nil }
        let suffix = code % 1000
        if shape == .cross && suffix != 0 { return nil }
        let character: String?
        switch suffix {
        case 0: character = nil
        case 100...135: character = characters[suffix - 100]
        case 200: character = "!"
        case 201: character = "?"
        default: return nil
        }
        return MilGpsSymbol(shape: shape, character: character)
    }

    public static func encode(shape: MilGpsShape, character: String?) -> Int {
        let suffix: Int
        if shape == .cross || character == nil {
            suffix = 0
        } else if character == "!" {
            suffix = 200
        } else if character == "?" {
            suffix = 201
        } else if let idx = characters.firstIndex(of: character!) {
            suffix = 100 + idx
        } else {
            suffix = 0
        }
        return shape.rawValue * 1000 + suffix
    }
}
