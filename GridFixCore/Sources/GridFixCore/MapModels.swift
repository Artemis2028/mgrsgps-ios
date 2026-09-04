import Foundation

/// Engine-agnostic base layer. Mirrors the fields the map screen actually uses,
/// so the same catalog feeds osmdroid on Android and MapLibre on iOS.
public struct BaseLayerDescriptor: Equatable, Sendable, Codable {
    public let key: String
    public let label: String
    public let attribution: String
    public let maxDownloadZoom: Int
    public let bulkDownload: Bool

    public init(key: String, label: String, attribution: String,
                maxDownloadZoom: Int, bulkDownload: Bool = false) {
        self.key = key
        self.label = label
        self.attribution = attribution
        self.maxDownloadZoom = maxDownloadZoom
        self.bulkDownload = bulkDownload
    }
}

/// A calibrated image quad: a photographed paper map or an imported GeoTIFF,
/// pinned to the world by its four corners.
public struct ImageQuad: Equatable, Sendable, Codable {
    public let id: String
    public let name: String
    /// Four corners in order: TL, TR, BR, BL.
    public let corners: [Corner]
    public var opacity: Double
    public var visible: Bool

    public struct Corner: Equatable, Sendable, Codable {
        public let lat: Double
        public let lon: Double
        public init(lat: Double, lon: Double) {
            self.lat = lat
            self.lon = lon
        }
    }

    /// Nil rather than a trap: a quad with the wrong number of corners is a
    /// bad import, not a programming error, and the UI has to say so.
    public init?(id: String, name: String, corners: [Corner],
                 opacity: Double = 1.0, visible: Bool = true) {
        guard corners.count == 4 else { return nil }
        self.id = id
        self.name = name
        self.corners = corners
        self.opacity = opacity
        self.visible = visible
    }
}

/// An offline region request, replacing per-provider bulk-download flags.
public struct OfflinePack: Equatable, Sendable, Codable {
    public let layerKey: String
    public let latNorth: Double
    public let latSouth: Double
    public let lonWest: Double
    public let lonEast: Double
    public let minZoom: Int
    public let maxZoom: Int

    public init(layerKey: String, latNorth: Double, latSouth: Double,
                lonWest: Double, lonEast: Double, minZoom: Int, maxZoom: Int) {
        self.layerKey = layerKey
        self.latNorth = latNorth
        self.latSouth = latSouth
        self.lonWest = lonWest
        self.lonEast = lonEast
        self.minZoom = minZoom
        self.maxZoom = maxZoom
    }
}

/// The minimal projection contract every renderer satisfies.
public protocol MapProjection {
    func toPoint(lat: Double, lon: Double) -> (x: Double, y: Double)
    func fromPoint(x: Double, y: Double) -> (lat: Double, lon: Double)
}

/// Default on-disk cap for cached elevation tiles, shared with Android.
public let elevationMaxCachedTiles = 400
