import Combine
import Foundation
import GridFixCore

/// Value captures only: workers never read a live repository or publish UI.
enum FieldExportRequest: Sendable {
    case library(TextInterchangeFormat,[Waypoint],Backup.Document)
    case track(Backup.TrackMeta,Data)
    var format: TextInterchangeFormat {
        if case let .library(format,_,_) = self { return format }
        return .gpx
    }
}

struct PreparedFieldExport: Sendable {
    let data: Data
    let format: TextInterchangeFormat
    let filename: String
    var protected = false
    var completeFilename: String {
        let ext = format == .atak ? "zip" : format.rawValue
        return filename + "." + ext
    }
}

enum FieldExportPreparation {
    typealias Builder = @Sendable (FieldExportRequest) throws -> PreparedFieldExport
    static func prepare(_ request: FieldExportRequest,builder: @escaping Builder = { try build($0) }) async throws -> PreparedFieldExport {
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let result = try builder(request)
            try Task.checkCancellation()
            return result
        }
        return try await withTaskCancellationHandler(operation: { try await worker.value },onCancel: { worker.cancel() })
    }

    static func build(_ request: FieldExportRequest) throws -> PreparedFieldExport {
        try Task.checkCancellation()
        let data: Data, filename: String
        switch request {
        case let .track(track,bytes):
            let points = try TrackCodec.decodeLocal(bytes)
            try Task.checkCancellation()
            data = Data(GPX.build(waypoints: [],tracks: [.init(name: track.name,points: points)]).utf8)
            let safe = track.name.replacingOccurrences(of: "[^A-Za-z0-9 _-]",with: "_",options: .regularExpression).trimmingCharacters(in: .whitespaces)
            filename = safe.isEmpty ? "track" : safe
        case let .library(format,points,document):
            filename = format == .atak ? "gridfix-datapackage" : "gridfix"
            if format == .csv { data = Data(CSV.build(points).utf8) }
            else if format == .atak { data = try ATAKPackage.build(waypoints: points,routes: document.graphics.filter { $0.type == "route" }) }
            else {
                let tracks = try document.tracks.map { track -> GPX.Track in
                    try Task.checkCancellation()
                    return GPX.Track(name: track.name,points: try TrackCodec.decode(document.trackFiles[track.id] ?? Data()))
                }
                try Task.checkCancellation()
                switch format {
                case .gpx: data = Data(GPX.build(waypoints: points,routes: document.graphics,tracks: tracks).utf8)
                case .kml: data = Data(KML.build(waypoints: points,graphics: document.graphics,tracks: tracks).utf8)
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
