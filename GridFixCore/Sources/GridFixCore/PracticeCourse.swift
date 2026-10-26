import Foundation

/// Android release/1.1.0 CourseState/CourseNavigationPolicy, separate from route following.
public struct PracticeCourse: Codable, Equatable, Sendable {
    public let runID: String
    public let name: String
    public let waypointIDs: [String]
    public let startedAt: Int64
    public private(set) var foundAt: [Int64]
    public private(set) var missingIDs: [String]
    public var nextIndex: Int { foundAt.count }
    public var done: Bool { nextIndex == waypointIDs.count }
    public var paused: Bool { !missingIDs.isEmpty }
    public var targetID: String? { !paused && waypointIDs.indices.contains(nextIndex) ? waypointIDs[nextIndex] : nil }
    public var valid: Bool {
        !runID.isEmpty && (2...10_000).contains(waypointIDs.count)
        && waypointIDs.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } && Set(waypointIDs).count == waypointIDs.count
        && startedAt >= 0 && foundAt.count <= waypointIDs.count
        && zip([startedAt] + foundAt,foundAt).allSatisfy { $0 <= $1 }
        && missingIDs == waypointIDs.dropFirst(nextIndex).filter { missingIDs.contains($0) }
    }
    public init(name: String,waypointIDs: [String],startedAt: Int64,runID: String = UUID().uuidString.lowercased()) throws {
        self.runID = runID; self.name = name; self.waypointIDs = waypointIDs; self.startedAt = startedAt
        foundAt = []; missingIDs = []
        guard valid else { throw PracticeCourseError.invalid("Choose at least two distinct saved checkpoints and a valid start time.") }
    }
    public mutating func reconcile(availableIDs: Set<String>) {
        missingIDs = waypointIDs.dropFirst(nextIndex).filter { !availableIDs.contains($0) }
    }
    public mutating func markFound(runID: String,checkpointID: String,now: Int64) throws -> Bool {
        guard valid, self.runID == runID, targetID == checkpointID else { return false }
        guard now >= (foundAt.last ?? startedAt) else { throw PracticeCourseError.invalid("Device time moved backwards. Scoring waits until it reaches the last saved time.") }
        foundAt.append(now); return true
    }
    public var result: Backup.CourseResult? {
        guard valid, done else { return nil }
        var previous = startedAt
        let splits = foundAt.map { time -> Int64 in defer { previous = time }; return time-previous }
        return .init(name: name,points: waypointIDs.count,started: startedAt,total: foundAt.last!-startedAt,splits: splits)
    }
    public var pauseReason: String? {
        guard paused else { return nil }
        let positions = waypointIDs.enumerated().filter { missingIDs.contains($0.element) }.map { String($0.offset+1) }.joined(separator: ", ")
        return "Missing checkpoint\(missingIDs.count == 1 ? "" : "s") \(positions). Restore the same checkpoint IDs or end the course. Elapsed time continues."
    }
    public static func canScore(distance: Double,accuracy: Double) -> Bool {
        distance.isFinite && distance >= 0 && accuracy.isFinite && (0...25).contains(accuracy) && distance+accuracy < 25
    }
    public static func time(_ milliseconds: Int64) -> String {
        let seconds = max(0,milliseconds/1000)
        return seconds >= 3600 ? String(format: "%lld:%02lld:%02lld",seconds/3600,(seconds%3600)/60,seconds%60)
            : String(format: "%lld:%02lld",seconds/60,seconds%60)
    }
}

public enum PracticeCourseError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { switch self { case .invalid(let reason): return reason } }
}

/// Active sessions are not part of Android's backup contract. A durable final
/// checkpoint is retained until the existing field-history store acknowledges it.
public final class PracticeCourseStore {
    private struct Envelope: Codable, Sendable { var version = 1; var active: PracticeCourse? }
    public private(set) var active: PracticeCourse?
    public private(set) var loadError: String?
    private let file: URL
    private var revision: UInt64 = 0
    private let identity = UUID()
    private var loadedStamp: SourceStamp?
    fileprivate struct SourceStamp: Equatable, Sendable {
        let size: UInt64, inode: UInt64, volume: UInt64
        let modified: Date?, regular: Bool
        static func read(_ file: URL) -> Self? {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path) else { return nil }
            return .init(size: (attributes[.size] as? NSNumber)?.uint64Value ?? 0,
                         inode: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0,
                         volume: (attributes[.systemNumber] as? NSNumber)?.uint64Value ?? 0,
                         modified: attributes[.modificationDate] as? Date,
                         regular: attributes[.type] as? FileAttributeType == .typeRegular)
        }
    }
    public enum StartupFailure: LocalizedError {
        case changed
        public var errorDescription: String? { "Saved practice course changed while opening. Try again." }
    }
    public struct PreparedStartup: Sendable {
        fileprivate let file: URL
        fileprivate let active: PracticeCourse?
        fileprivate let error: String?
        fileprivate let stamp: SourceStamp?
    }
    public static func prepareStartup(directory: URL) throws -> PreparedStartup {
        try Task.checkCancellation()
        let value = readStartup(directory.appendingPathComponent("practice-course-v1.json"))
        try Task.checkCancellation()
        return value
    }
    private static func readStartup(_ file: URL) -> PreparedStartup {
        let stamp = SourceStamp.read(file)
        guard FileManager.default.fileExists(atPath: file.path) else {
            return .init(file: file,active: nil,error: nil,stamp: stamp)
        }
        do {
            let saved = try JSONDecoder().decode(Envelope.self,from: Data(contentsOf: file,options: .mappedIfSafe))
            guard saved.version == 1,saved.active?.valid != false else { throw PracticeCourseError.invalid("Invalid saved practice course.") }
            return .init(file: file,active: saved.active,error: nil,stamp: stamp)
        } catch { return .init(file: file,active: nil,error: "Saved course was kept: \(error.localizedDescription)",stamp: stamp) }
    }
    public init(directory: URL) {
        let prepared = Self.readStartup(directory.appendingPathComponent("practice-course-v1.json"))
        file = prepared.file; active = prepared.active; loadError = prepared.error; loadedStamp = prepared.stamp
    }
    public init(startup: PreparedStartup) throws {
        guard SourceStamp.read(startup.file) == startup.stamp else { throw StartupFailure.changed }
        file = startup.file; active = startup.active; loadError = startup.error; loadedStamp = startup.stamp
    }
    public struct RecoverySnapshot: Sendable {
        fileprivate let revision: UInt64
        fileprivate let identity: UUID
        fileprivate let file: URL
        fileprivate let stamp: SourceStamp
        public func prepare() throws -> PreparedRecovery {
            try Task.checkCancellation()
            guard SourceStamp.read(file) == stamp else { throw PracticeCourseError.invalid("Saved course changed. Reopen the app before resetting it.") }
            let bytes = try Data(contentsOf: file,options: .mappedIfSafe)
            guard SourceStamp.read(file) == stamp else { throw PracticeCourseError.invalid("Saved course changed. Its original data was kept.") }
            let kept = file.deletingLastPathComponent().appendingPathComponent("practice-course-damaged-\(UUID().uuidString).json")
            let archive = try PreparedAtomicFile(data: bytes,destination: kept,lockCompatible: true,synchronize: true)
            let empty = try PreparedAtomicFile(data: JSONEncoder().encode(Envelope(active: nil)),destination: file,lockCompatible: true,synchronize: true)
            try Task.checkCancellation()
            return .init(revision: revision,identity: identity,stamp: stamp,archive: archive,empty: empty)
        }
    }
    public struct PreparedRecovery: Sendable {
        fileprivate let revision: UInt64
        fileprivate let identity: UUID
        fileprivate let stamp: SourceStamp
        fileprivate let archive: PreparedAtomicFile
        fileprivate let empty: PreparedAtomicFile
        public func discard() { archive.discard(); empty.discard() }
    }
    public func recoverySnapshot() throws -> RecoverySnapshot {
        guard loadError != nil,let stamp = loadedStamp,stamp.regular else {
            throw PracticeCourseError.invalid("No readable damaged course file can be preserved. The original data was kept.")
        }
        guard SourceStamp.read(file) == stamp else { throw PracticeCourseError.invalid("Saved course changed. Reopen the app before resetting it.") }
        return .init(revision: revision,identity: identity,file: file,stamp: stamp)
    }
    @discardableResult public func publishRecovery(_ prepared: PreparedRecovery) throws -> Bool {
        guard prepared.identity == identity else { throw PracticeCourseError.invalid("Prepared recovery belongs to another course store.") }
        guard prepared.revision == revision,loadError != nil else { prepared.discard(); return false }
        defer { prepared.discard() }
        guard SourceStamp.read(file) == prepared.stamp else { throw PracticeCourseError.invalid("Saved course changed. Reopen the app before resetting it.") }
        try prepared.archive.publish(replacing: false)
        guard SourceStamp.read(file) == prepared.stamp else { throw PracticeCourseError.invalid("Saved course changed. A copy was preserved and its current data was kept.") }
        try prepared.empty.publish()
        active = nil; loadError = nil; loadedStamp = SourceStamp.read(file); revision &+= 1
        return true
    }
    public func preserveDamagedAndReset() throws {
        guard loadError != nil else { return }
        _ = try publishRecovery(recoverySnapshot().prepare())
    }
    /// Snapshot and publication belong to the owner's serial executor. The
    /// immutable preparation can encode/write without borrowing the live store.
    public struct SaveSnapshot: Sendable {
        fileprivate let revision: UInt64
        fileprivate let identity: UUID
        fileprivate let destination: URL
        fileprivate let loadError: String?
        public func prepare(_ value: PracticeCourse?) throws -> PreparedSave {
            if let loadError { throw PracticeCourseError.invalid(loadError) }
            guard value?.valid != false else { throw PracticeCourseError.invalid("Invalid practice progress.") }
            try Task.checkCancellation()
            let file = try PreparedAtomicFile(data: JSONEncoder().encode(Envelope(active: value)),destination: destination,lockCompatible: true)
            return .init(value: value,revision: revision,identity: identity,file: file)
        }
    }
    public struct PreparedSave: Sendable {
        fileprivate let value: PracticeCourse?
        fileprivate let revision: UInt64
        fileprivate let identity: UUID
        fileprivate let file: PreparedAtomicFile
    }
    public func saveSnapshot() -> SaveSnapshot {
        .init(revision: revision,identity: identity,destination: file,loadError: loadError)
    }
    public func publish(_ prepared: PreparedSave) throws -> Bool {
        guard prepared.identity == identity else { throw PracticeCourseError.invalid("Prepared course belongs to another store.") }
        guard prepared.revision == revision else { prepared.file.discard(); return false }
        try prepared.file.publish()
        active = prepared.value; revision &+= 1
        return true
    }
    public func save(_ value: PracticeCourse?) throws {
        while true { if try publish(saveSnapshot().prepare(value)) { return } }
    }
}

public enum PracticeCourseGenerator {
    /// Matches OSM GeoPoint.destinationPoint (radius 6378137), used by Android.
    public static func scatter(origin: GeoPoint,count: Int,radius: Int,random: () -> Double = { Double.random(in: 0..<1) }) throws -> [GeoPoint] {
        guard [3,4,5,6,8].contains(count), [500,1000,2000].contains(radius),
              TrackCodec.validCoordinates(origin.lat,origin.lon) else { throw PracticeCourseError.invalid("Choose a valid origin, point count and course radius.") }
        var result: [GeoPoint] = []
        for _ in 0..<400 {
            let u = random(), v = random()
            guard u.isFinite, v.isFinite, (0..<1).contains(u), (0..<1).contains(v) else { throw PracticeCourseError.invalid("Invalid random course sample.") }
            let distance = 120 + u*Double(radius-120), azimuth = v*2*Double.pi, arc = distance/6_378_137
            let lat = origin.lat*Double.pi/180, lon = origin.lon*Double.pi/180
            let destinationLat = asin(sin(lat)*cos(arc)+cos(lat)*sin(arc)*cos(azimuth))
            let destinationLon = lon+atan2(sin(azimuth)*sin(arc)*cos(lat),cos(arc)-sin(lat)*sin(destinationLat))
            let point = GeoPoint(lat: destinationLat*180/Double.pi,lon: TerrainGeometry.wrap(destinationLon*180/Double.pi))
            if result.allSatisfy({ Geodesy.navInfo(fromLat: $0.lat,fromLon: $0.lon,toLat: point.lat,toLon: point.lon).distanceMeters > 120 }) { result.append(point) }
            if result.count == count { break }
        }
        guard result.count >= 2 else { throw PracticeCourseError.invalid("Could not place two separated checkpoints. Try again; no course folder was created.") }
        return result
    }
}
