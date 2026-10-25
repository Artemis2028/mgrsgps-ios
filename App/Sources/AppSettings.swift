import Foundation
import GridFixCore

/// Position / Navigate instrument. Android `Face` ints: 0 Glance, 1 Lensatic, 2 Dial.
/// Defaults match Android; screenshot scripts choose a face explicitly.
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
    /// 4 / 6 / 8 / 10, matching Android's ten-digit default.
    @Published var mgrsDigits: Int = 10 { didSet { persist() } }
    @Published var gridSystem = 0 { didSet { persist() } }
    var gridName: String { gridSystem == 1 ? "USNG" : "MGRS" }
    @Published var units: DistanceUnit = .metric { didSet { persist() } }
    @Published var latLonFormat: LatLonFormat = .degreesMinutes { didSet { persist() } }
    @Published var angleUnit: AngleUnit = .degrees { didSet { persist() } }
    @Published var northRef: NorthReference = .trueNorth { didSet { persist() } }
    /// East-positive degrees. Nil follows DeclinationService (heading, then WMM).
    @Published var declinationOverride: Double? { didSet { persist() } }
    @Published var face: PositionFace = .lensatic { didSet { persist() } }

    @Published var keepScreenOn = true { didSet { persist() } }
    @Published var pacePer100m = 65 { didSet { persist() } }
    // Android guide settings and display orientation keep their backup integer codes.
    @Published var guideAllowance = 10 { didSet { persist() } }
    @Published var guideHoldOffSec = 5 { didSet { persist() } }
    @Published var guideHeartbeatSec = 30 { didSet { persist() } }
    @Published var guideMode = 0 { didSet { persist() } }
    @Published var guideCorridorM = 0 { didSet { persist() } }
    @Published var laneWarningM = 0 { didSet { persist() } }
    @Published var laneSideCues = true { didSet { persist() } }
    @Published var laneBackstopCue = true { didSet { persist() } }
    @Published var laneInsideTick = true { didSet { persist() } }
    @Published var laneReminderMin = 5 { didSet { persist() } }
    @Published var laneGpsAlert = true { didSet { persist() } }
    @Published var hiddenMapTools: Set<String> = [] { didSet { persist() } }
    @Published var liveActivitiesEnabled = false { didSet { persist() } }
    var guideConfiguration: GuideConfiguration {
        var c = GuideConfiguration()
        c.allowance = Double(guideAllowance); c.holdOff = Double(guideHoldOffSec); c.heartbeat = Double(guideHeartbeatSec)
        c.holdAzimuth = guideMode == 0; c.corridor = Double(guideCorridorM); return c
    }
    @Published var orientation = 0 { didSet { persist() } }
    @Published var disclaimerAccepted = false { didSet { persist() } }

    private let fileURL: URL
    private var ready = false
    private var revision: UInt64 = 0
    private let identity = UUID()

    private struct Snapshot: Codable, Sendable {
        var nightMode: Bool
        var mgrsDigits: Int
        var gridSystem: Int?
        var units: Int
        var latLonFormat: Int
        var angleUnit: Int
        var northRef: Int
        var declinationOverride: Double?
        var face: Int
        var keepScreenOn: Bool?
        var pacePer100m: Int?
        var guideAllowance: Int?
        var guideHoldOffSec: Int?
        var guideHeartbeatSec: Int?
        var guideMode: Int?
        var guideCorridorM: Int?
        var laneWarningM: Int?
        var laneSideCues: Bool?
        var laneBackstopCue: Bool?
        var laneInsideTick: Bool?
        var laneReminderMin: Int?
        var laneGpsAlert: Bool?
        var hiddenMapTools: String?
        var liveActivitiesEnabled: Bool?
        var orientation: Int?
        var disclaimerAccepted: Bool?
    }

    init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .documentDirectory,
                                                         in: .userDomainMask).first!
        fileURL = dir.appendingPathComponent("settings-v1.json")
        load()
        ready = true
        applyLaunchFace()
    }

    /// CI cannot tap Settings, so `-startFace glance|lensatic|dial` picks the
    /// Position instrument for this launch. Overrides the saved face.
    private func applyLaunchFace() {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-startFace"),
              args.index(after: idx) < args.endIndex else { return }
        switch args[args.index(after: idx)].lowercased() {
        case "glance": face = .glance
        case "lensatic": face = .lensatic
        case "dial": face = .dial
        default: break
        }
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
        mgrsDigits = [4, 6, 8, 10].contains(snap.mgrsDigits) ? snap.mgrsDigits : 10
        gridSystem = snap.gridSystem == 1 ? 1 : 0
        units = DistanceUnit(rawValue: snap.units) ?? .metric
        latLonFormat = LatLonFormat(rawValue: snap.latLonFormat) ?? .degreesMinutes
        angleUnit = AngleUnit(rawValue: snap.angleUnit) ?? .degrees
        northRef = NorthReference(rawValue: snap.northRef) ?? .trueNorth
        if let d = snap.declinationOverride, d.isFinite, d >= -180, d <= 180 {
            declinationOverride = d
        } else {
            declinationOverride = nil
        }
        face = PositionFace(rawValue: snap.face) ?? .lensatic
        keepScreenOn = snap.keepScreenOn ?? true
        pacePer100m = snap.pacePer100m ?? 65
        guideAllowance = min(90,max(1,snap.guideAllowance ?? 10)); guideHoldOffSec = min(60,max(0,snap.guideHoldOffSec ?? 5))
        guideHeartbeatSec = min(600,max(0,snap.guideHeartbeatSec ?? 30)); guideMode = snap.guideMode == 1 ? 1 : 0
        guideCorridorM = min(2000,max(0,snap.guideCorridorM ?? 0))
        laneWarningM = min(200,max(0,snap.laneWarningM ?? 0))
        laneSideCues = snap.laneSideCues ?? true
        laneBackstopCue = snap.laneBackstopCue ?? true
        laneInsideTick = snap.laneInsideTick ?? true
        laneReminderMin = min(120,max(0,snap.laneReminderMin ?? 5))
        laneGpsAlert = snap.laneGpsAlert ?? true
        hiddenMapTools = MapTools.decode(snap.hiddenMapTools)
        liveActivitiesEnabled = snap.liveActivitiesEnabled ?? false
        orientation = (0...3).contains(snap.orientation ?? 0) ? (snap.orientation ?? 0) : 0
        disclaimerAccepted = snap.disclaimerAccepted ?? false
    }

    var backupSettings: Backup.AppSettings {
        var s = Backup.AppSettings()
        s.gridSystem = gridSystem
        s.nightMode = nightMode; s.mgrsDigits = mgrsDigits; s.units = units.rawValue
        s.latLonFormat = latLonFormat.rawValue; s.angleUnit = angleUnit.rawValue; s.northRef = northRef.rawValue
        s.declinationOverride = declinationOverride; s.face = face.rawValue; s.keepScreenOn = keepScreenOn
        s.pacePer100m = pacePer100m; s.orientation = orientation; s.disclaimerAccepted = disclaimerAccepted
        s.guideAllowance = guideAllowance; s.guideHoldOffSec = guideHoldOffSec; s.guideHeartbeatSec = guideHeartbeatSec
        s.guideMode = guideMode; s.guideCorridorM = guideCorridorM; s.laneWarningM = laneWarningM; s.hiddenMapTools = hiddenMapTools
        s.laneSideCues = laneSideCues
        s.laneBackstopCue = laneBackstopCue
        s.laneInsideTick = laneInsideTick
        s.laneReminderMin = laneReminderMin
        s.laneGpsAlert = laneGpsAlert
        return s
    }

    func applyBackup(_ s: Backup.AppSettings) throws {
        try Self.encodeBackup(s,liveActivitiesEnabled:liveActivitiesEnabled).write(to: fileURL,options: .atomic)
        installBackup(s)
    }

    nonisolated private static func encodeBackup(_ s: Backup.AppSettings,liveActivitiesEnabled: Bool = false) throws -> Data {
        var check = Backup.Document(settings: s)
        check.hasSettings = true
        try Backup.validate(check)
        var snapshot = Snapshot(nightMode: s.nightMode, mgrsDigits: s.mgrsDigits, units: s.units,
                                latLonFormat: s.latLonFormat, angleUnit: s.angleUnit, northRef: s.northRef,
                                declinationOverride: s.declinationOverride, face: s.face,
                                keepScreenOn: s.keepScreenOn, pacePer100m: s.pacePer100m,
                                orientation: s.orientation, disclaimerAccepted: s.disclaimerAccepted)
        snapshot.gridSystem = s.gridSystem
        snapshot.guideAllowance = s.guideAllowance; snapshot.guideHoldOffSec = s.guideHoldOffSec
        snapshot.guideHeartbeatSec = s.guideHeartbeatSec; snapshot.guideMode = s.guideMode; snapshot.guideCorridorM = s.guideCorridorM; snapshot.laneWarningM = s.laneWarningM; snapshot.hiddenMapTools = MapTools.encode(s.hiddenMapTools)
        snapshot.laneSideCues = s.laneSideCues
        snapshot.laneBackstopCue = s.laneBackstopCue
        snapshot.laneInsideTick = s.laneInsideTick
        snapshot.laneReminderMin = s.laneReminderMin
        snapshot.laneGpsAlert = s.laneGpsAlert
        snapshot.liveActivitiesEnabled = liveActivitiesEnabled
        return try JSONEncoder().encode(snapshot)
    }

    private func installBackup(_ s: Backup.AppSettings) {
        ready = false
        gridSystem = s.gridSystem
        nightMode = s.nightMode; mgrsDigits = s.mgrsDigits
        units = DistanceUnit(rawValue: s.units)!; latLonFormat = LatLonFormat(rawValue: s.latLonFormat)!
        angleUnit = AngleUnit(rawValue: s.angleUnit)!; northRef = NorthReference(rawValue: s.northRef)!
        declinationOverride = s.declinationOverride; face = PositionFace(rawValue: s.face)!
        keepScreenOn = s.keepScreenOn; pacePer100m = s.pacePer100m
        guideAllowance = s.guideAllowance; guideHoldOffSec = s.guideHoldOffSec; guideHeartbeatSec = s.guideHeartbeatSec
        laneSideCues = s.laneSideCues
        laneBackstopCue = s.laneBackstopCue
        laneInsideTick = s.laneInsideTick
        laneReminderMin = s.laneReminderMin
        laneGpsAlert = s.laneGpsAlert
        guideMode = s.guideMode; guideCorridorM = s.guideCorridorM; laneWarningM = s.laneWarningM; hiddenMapTools = Set(s.hiddenMapTools.filter { MapTools.all.contains($0) })
        orientation = s.orientation; disclaimerAccepted = s.disclaimerAccepted
        ready = true
    }

    struct RestoreSnapshot: Sendable {
        fileprivate let destination: URL
        fileprivate let revision: UInt64
        fileprivate let identity: UUID
        fileprivate let liveActivitiesEnabled: Bool
        func prepare(_ settings: Backup.AppSettings) throws -> PreparedRestore {
            let file = try PreparedAtomicFile(data: AppSettings.encodeBackup(settings,liveActivitiesEnabled:liveActivitiesEnabled),destination: destination)
            return PreparedRestore(settings: settings,revision: revision,identity: identity,file: file)
        }
    }

    struct PreparedRestore: Sendable {
        fileprivate let settings: Backup.AppSettings
        fileprivate let revision: UInt64
        fileprivate let identity: UUID
        fileprivate let file: PreparedAtomicFile
    }

    func restoreSnapshot() -> RestoreSnapshot {
        RestoreSnapshot(destination: fileURL,revision: revision,identity: identity,liveActivitiesEnabled:liveActivitiesEnabled)
    }

    func publishRestore(_ prepared: PreparedRestore) throws -> Bool {
        guard prepared.identity == identity else {
            throw BackupError.notABackup("Prepared settings restore belongs to a different store")
        }
        guard prepared.revision == revision else { prepared.file.discard(); return false }
        try prepared.file.publish()
        installBackup(prepared.settings)
        return true
    }

    private func persist() {
        revision &+= 1
        guard ready else { return }
        var snap = Snapshot(
            nightMode: nightMode,
            mgrsDigits: mgrsDigits,
            units: units.rawValue,
            latLonFormat: latLonFormat.rawValue,
            angleUnit: angleUnit.rawValue,
            northRef: northRef.rawValue,
            declinationOverride: declinationOverride,
            face: face.rawValue,
            keepScreenOn: keepScreenOn, pacePer100m: pacePer100m,
            orientation: orientation, disclaimerAccepted: disclaimerAccepted
        )
        snap.gridSystem = gridSystem
        snap.guideAllowance = guideAllowance; snap.guideHoldOffSec = guideHoldOffSec; snap.guideHeartbeatSec = guideHeartbeatSec
        snap.guideMode = guideMode; snap.guideCorridorM = guideCorridorM; snap.laneWarningM = laneWarningM; snap.hiddenMapTools = MapTools.encode(hiddenMapTools)
        snap.laneSideCues = laneSideCues
        snap.laneBackstopCue = laneBackstopCue
        snap.laneInsideTick = laneInsideTick
        snap.laneReminderMin = laneReminderMin
        snap.laneGpsAlert = laneGpsAlert
        snap.liveActivitiesEnabled = liveActivitiesEnabled
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
