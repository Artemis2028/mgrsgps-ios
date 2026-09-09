import Foundation
import GridFixCore

/// Position / Navigate instrument. Android `Face` ints: 0 Glance, 1 Lensatic, 2 Dial.
/// iOS defaults to Glance so the CI Position shot stays the large-grid face.
enum PositionFace: Int, CaseIterable, Identifiable, Codable {
    case glance = 0
    case lensatic = 1
    case dial = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .glance: return "Glance"
        case .lensatic: return "Lensatic"
        case .dial: return "Dial"
        }
    }
}

/// 0 true, 1 magnetic, 2 grid — same ints as Android `northRef`.
enum NorthReference: Int, CaseIterable, Identifiable, Codable {
    case trueNorth = 0
    case magnetic = 1
    case grid = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .trueNorth: return "True"
        case .magnetic: return "Mag"
        case .grid: return "Grid"
        }
    }

    var letter: String {
        switch self {
        case .trueNorth: return "T"
        case .magnetic: return "M"
        case .grid: return "G"
        }
    }
}

/// Local settings the Position and Navigate screens actually read.
///
/// JSON beside `waypoints-v1.json` so a field wipe of Documents clears both,
/// and a backup slice can pick the file up later without a second store.
@MainActor
final class AppSettings: ObservableObject {
    @Published var nightMode: Bool = false { didSet { persist() } }
    /// 4 / 6 / 8 / 10. Default 8 matches the Position face CI already photographs.
    @Published var mgrsDigits: Int = 8 { didSet { persist() } }
    @Published var units: DistanceUnit = .metric { didSet { persist() } }
    @Published var latLonFormat: LatLonFormat = .degreesMinutes { didSet { persist() } }
    @Published var angleUnit: AngleUnit = .degrees { didSet { persist() } }
    @Published var northRef: NorthReference = .trueNorth { didSet { persist() } }
    /// East-positive degrees. Nil follows DeclinationService (heading, then WMM).
    @Published var declinationOverride: Double? { didSet { persist() } }
    @Published var face: PositionFace = .glance { didSet { persist() } }

    private let fileURL: URL
    private var ready = false

    private struct Snapshot: Codable {
        var nightMode: Bool
        var mgrsDigits: Int
        var units: Int
        var latLonFormat: Int
        var angleUnit: Int
        var northRef: Int
        var declinationOverride: Double?
        var face: Int
    }

    init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .documentDirectory,
                                                         in: .userDomainMask).first!
        fileURL = dir.appendingPathComponent("settings-v1.json")
        load()
        ready = true
    }

    func setMgrsDigits(_ value: Int) {
        guard [4, 6, 8, 10].contains(value) else { return }
        mgrsDigits = value
    }

    func cycleMgrsDigits() {
        let order = [4, 6, 8, 10]
        let i = order.firstIndex(of: mgrsDigits) ?? 2
        mgrsDigits = order[(i + 1) % order.count]
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        nightMode = snap.nightMode
        mgrsDigits = [4, 6, 8, 10].contains(snap.mgrsDigits) ? snap.mgrsDigits : 8
        units = DistanceUnit(rawValue: snap.units) ?? .metric
        latLonFormat = LatLonFormat(rawValue: snap.latLonFormat) ?? .degreesMinutes
        angleUnit = AngleUnit(rawValue: snap.angleUnit) ?? .degrees
        northRef = NorthReference(rawValue: snap.northRef) ?? .trueNorth
        if let d = snap.declinationOverride, d.isFinite, d >= -180, d <= 180 {
            declinationOverride = d
        } else {
            declinationOverride = nil
        }
        face = PositionFace(rawValue: snap.face) ?? .glance
    }

    private func persist() {
        guard ready else { return }
        let snap = Snapshot(
            nightMode: nightMode,
            mgrsDigits: mgrsDigits,
            units: units.rawValue,
            latLonFormat: latLonFormat.rawValue,
            angleUnit: angleUnit.rawValue,
            northRef: northRef.rawValue,
            declinationOverride: declinationOverride,
            face: face.rawValue
        )
        guard let data = try? JSONEncoder().encode(snap) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

enum FieldMath {
    static func normalize(_ degrees: Double) -> Double {
        var v = degrees.truncatingRemainder(dividingBy: 360.0)
        if v < 0 { v += 360 }
        return v
    }

    /// True azimuth into the operator's north reference.
    /// Magnetic with no declination returns nil — never treat a missing
    /// G-M angle as zero.
    static func toNorthRef(angleTrue: Double,
                            north: NorthReference,
                            declinationEast: Double?,
                            convergence: Double) -> Double? {
        switch north {
        case .trueNorth:
            return normalize(angleTrue)
        case .magnetic:
            guard let d = declinationEast else { return nil }
            return normalize(angleTrue - d)
        case .grid:
            return normalize(angleTrue - convergence)
        }
    }

    /// Compass heading in the selected north reference. Nil until the compass
    /// has actually reported; a sitting card must not read as 000.
    static func heading(trueHeading: Double?,
                         magneticHeading: Double?,
                         north: NorthReference,
                         declinationEast: Double?,
                         convergence: Double?) -> Double? {
        switch north {
        case .trueNorth:
            if let t = trueHeading, t >= 0 { return normalize(t) }
            if let m = magneticHeading, m >= 0, let d = declinationEast {
                return normalize(m + d)
            }
            return nil
        case .magnetic:
            if let m = magneticHeading, m >= 0 { return normalize(m) }
            if let t = trueHeading, t >= 0, let d = declinationEast {
                return normalize(t - d)
            }
            return nil
        case .grid:
            guard let c = convergence else { return nil }
            if let t = trueHeading, t >= 0 { return normalize(t - c) }
            if let m = magneticHeading, m >= 0, let d = declinationEast {
                return normalize(m + d - c)
            }
            return nil
        }
    }
}
