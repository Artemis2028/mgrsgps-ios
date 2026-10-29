import Combine
import Foundation
import GridFixCore

/// Value captures only: workers never read a live repository or publish UI.
enum FieldExportRequest: Sendable {
    case library(TextInterchangeFormat,[Waypoint],Backup.Document)
    case track(Backup.TrackMeta,Data)
    case savedTrack(FieldDataStore.TrackReadSnapshot)
    var format: TextInterchangeFormat {
        if case let .library(format,_,_) = self { return format }
        return .gpx
    }
}

enum FieldExportPayload: Sendable {
    case bytes(Data)
    case file(PreparedNativeExport)
    var byteCount: UInt64 {
        get throws {
            switch self {
            case .bytes(let data): return UInt64(data.count)
            case .file(let file):
                return try withExtendedLifetime(file) {
                    let values = try file.url.resourceValues(forKeys:[.isRegularFileKey,.fileSizeKey])
                    guard values.isRegularFile == true,let size = values.fileSize,size >= 0 else { throw CocoaError(.fileReadCorruptFile) }
                    return UInt64(size)
                }
            }
        }
    }
    func readData() throws -> Data {
        try Task.checkCancellation()
        switch self {
        case .bytes(let data): return data
        case .file(let file):
            return try withExtendedLifetime(file) {
                let data = try Data(contentsOf:file.url)
                try Task.checkCancellation()
                return data
            }
        }
    }
}

struct PreparedFieldExport: Sendable {
    let payload: FieldExportPayload
    let format: TextInterchangeFormat
    let filename: String
    var protected = false
    var data: Data { get throws { try payload.readData() } }
    init(data: Data,format: TextInterchangeFormat,filename: String,protected: Bool = false) {
        payload = .bytes(data); self.format = format; self.filename = filename; self.protected = protected
    }
    init(file: PreparedNativeExport,format: TextInterchangeFormat,filename: String) {
        payload = .file(file); self.format = format; self.filename = filename
    }
    var completeFilename: String {
        let ext = format == .atak ? "zip" : format.rawValue
        return filename + "." + ext
    }
}

enum FieldExportPreparation {
    typealias Builder = @Sendable (FieldExportRequest) throws -> PreparedFieldExport
    static func prepare(_ request: FieldExportRequest,builder: @escaping Builder = { try buildForPresentation($0) }) async throws -> PreparedFieldExport {
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let result = try builder(request)
            try Task.checkCancellation()
            return result
        }
        return try await withTaskCancellationHandler(operation: { try await worker.value },onCancel: { worker.cancel() })
    }

    private static func gpxFilename(_ request: FieldExportRequest) -> String {
        let name: String
        switch request {
        case .library: return "gridfix"
        case .track(let track,_): name = track.name
        case .savedTrack(let source): name = source.track.name
        }
        let safe = name.replacingOccurrences(of:"[^A-Za-z0-9 _-]",with:"_",options:.regularExpression).trimmingCharacters(in:.whitespaces)
        return safe.isEmpty ? "track" : safe
    }
    private static func writeGPX(_ request: FieldExportRequest,sink: (Data) throws -> Void) throws {
        switch request {
        case .savedTrack(let source):
            try GPX.write(waypoints:[],tracks:[.init(name:source.track.name) { try source.visitPoints($0) }],sink:sink)
        case .track(let track,let bytes):
            try GPX.write(waypoints:[],tracks:[.init(name:track.name) { try TrackCodec.visitLocal(bytes,point:$0) }],sink:sink)
        case .library(let format,let points,let document):
            guard format == .gpx else { throw CocoaError(.fileWriteUnknown) }
            let streams = document.tracks.map { track in
                GPX.TrackStream(name:track.name) { try document.visitTrackPoints(track.id,point:$0) }
            }
            try GPX.write(waypoints:points,routes:document.graphics,tracks:streams,sink:sink)
        }
    }
    private static func writeStreamed(_ request: FieldExportRequest,sink: (Data) throws -> Void) throws {
        if request.format == .gpx { try writeGPX(request,sink:sink); return }
        guard case let .library(.kml,points,document) = request else { throw CocoaError(.fileWriteUnknown) }
        let streams = document.tracks.map { track in
            GPX.TrackStream(name:track.name) { try document.visitTrackPoints(track.id,point:$0) }
        }
        try KML.write(waypoints:points,graphics:document.graphics,tracks:streams,sink:sink)
    }
    static func buildForPresentation(_ request: FieldExportRequest,root: URL = FileManager.default.temporaryDirectory) throws -> PreparedFieldExport {
        guard request.format == .gpx || request.format == .kml else { return try build(request) }
        let name = gpxFilename(request)
        let file = try PreparedNativeExport.prepare(filename:name,extension:request.format.rawValue,root:root) { url in
            guard FileManager.default.createFile(atPath:url.path,contents:nil,attributes:[.protectionKey:FileProtectionType.completeUntilFirstUserAuthentication]) else { throw CocoaError(.fileWriteUnknown) }
            let handle = try FileHandle(forWritingTo:url)
            do {
                try writeStreamed(request) { try handle.write(contentsOf:$0) }
                try handle.synchronize(); try handle.close()
            } catch { try? handle.close(); throw error }
        }
        return .init(file:file,format:request.format,filename:name)
    }

    static func build(_ request: FieldExportRequest) throws -> PreparedFieldExport {
        try Task.checkCancellation()
        if request.format == .gpx || request.format == .kml {
            var data = Data()
            try writeStreamed(request) { data.append($0) }
            return .init(data:data,format:request.format,filename:gpxFilename(request))
        }
        let data: Data, filename: String
        switch request {
        case .savedTrack,.track: preconditionFailure("GPX handled above")
        case let .library(format,points,document):
            filename = format == .atak ? "gridfix-datapackage" : "gridfix"
            if format == .csv { data = Data(CSV.build(points).utf8) }
            else if format == .atak { data = try ATAKPackage.build(waypoints: points,routes: document.graphics.filter { $0.type == "route" }) }
            else {
                let tracks = try document.tracks.map { track -> GPX.Track in
                    try Task.checkCancellation()
                    return GPX.Track(name: track.name,points: try TrackCodec.decode(document.trackData(track.id,maximumBytes:TrackCodec.interchangeByteLimit)))
                }
                try Task.checkCancellation()
                switch format {
                case .gpx,.kml: preconditionFailure("Streamed formats handled above")
                case .geojson: data = Data(try GeoJSON.build(waypoints: points,graphics: document.graphics,tracks: tracks).utf8)
                case .kmz: data = try KMZ.build(waypoints: points,graphics: document.graphics,tracks: tracks)
                case .csv,.atak: preconditionFailure("Handled without track decoding")
                }
            }
        }
        try Task.checkCancellation()
        return .init(data: data,format: request.format,filename: filename)
    }

    static func protect(_ prepared: PreparedFieldExport,password: String) async throws -> PreparedFieldExport {
        let worker = Task.detached(priority: .userInitiated) {
            guard try prepared.payload.byteCount <= UInt64(ProtectedFiles.maximumFileBytes) else {
                throw BackupError.notABackup("Too large to protect (over 16 MB). Export fewer items, or without a password.")
            }
            let sealed = try ProtectedFiles.seal(name: prepared.completeFilename,bytes: prepared.data,password: password)
            try Task.checkCancellation()
            return PreparedFieldExport(data: sealed,format: prepared.format,filename: prepared.completeFilename+".mgrsgps",protected: true)
        }
        return try await withTaskCancellationHandler(operation: { try await worker.value },onCancel: { worker.cancel() })
    }
}

@MainActor
final class FieldExportTransfer: ObservableObject {
    typealias Writer = @Sendable (FieldExportRequest) async throws -> PreparedFieldExport
    @Published private(set) var format: TextInterchangeFormat?
    private var generation = UUID()
    private var work: Task<Void,Never>?
    private let writer: Writer
    init(writer: @escaping Writer = { try await FieldExportPreparation.prepare($0) }) { self.writer = writer }

    @discardableResult
    func start(_ request: FieldExportRequest,password: String? = nil,completion: @escaping (Result<PreparedFieldExport,Error>) -> Void) -> Bool {
        guard format == nil else { return false }
        let token = UUID(), writer = writer
        generation = token; format = request.format
        work = Task {
            let result: Result<PreparedFieldExport,Error>
            do {
                let plain = try await writer(request)
                try Task.checkCancellation()
                if let password { result = .success(try await FieldExportPreparation.protect(plain,password: password)) }
                else { result = .success(plain) }
            }
            catch { result = .failure(error) }
            guard generation == token,!Task.isCancelled else { return }
            work = nil; format = nil
            completion(result)
        }
        return true
    }

    @discardableResult
    func cancel() -> Task<Void,Never>? {
        generation = UUID()
        let previous = work; work = nil; format = nil
        previous?.cancel()
        return previous
    }
}
