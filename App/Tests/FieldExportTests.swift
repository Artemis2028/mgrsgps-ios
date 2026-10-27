import XCTest
import GridFixCore
@testable import MGRSGPS

@MainActor
final class FieldExportTests: XCTestCase {
    func testExportFilenameKeepsUnicodeAndExtensionWithoutPathsOrTruncation() throws {
        XCTAssertEqual(ExportFilename.stem("  CAFÉ patrol.GPX  ",extension:"gpx"),"CAFÉ patrol")
        for value in ["", ".", "..", ".gpx", "A/B", "A\\B", "A\nB",String(repeating:"界",count:67)] {
            XCTAssertNil(ExportFilename.stem(value,extension:"gpx"),value)
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let name = try XCTUnwrap(ExportFilename.stem("CAFÉ patrol.gpx",extension:"gpx"))
        let file = try PreparedNativeExport.prepare(data:Data("whole export".utf8),filename:name,extension:"gpx",root:root)
        defer { file.discard() }
        XCTAssertEqual(file.url.lastPathComponent,"CAFÉ patrol.gpx")
        XCTAssertEqual(try Data(contentsOf:file.url),Data("whole export".utf8))
    }
    func testNativeExportStagingKeepsIndependentCompleteFilesUntilTheirOwnCleanup() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = Data("first complete CAFÉ export".utf8),newer = Data("newer complete export".utf8)
        let first = try await Task.detached { try PreparedNativeExport.prepare(data: original,filename: "../CAFÉ\\patrol\n",extension: "gpx",root: root) }.value
        let second = try await Task.detached { try PreparedNativeExport.prepare(data: newer,filename: "../CAFÉ\\patrol\n",extension: "gpx",root: root) }.value
        XCTAssertNotEqual(first.url,second.url)
        XCTAssertEqual(first.url.pathExtension,"gpx")
        XCTAssertEqual(first.url.deletingLastPathComponent(),first.directory)
        XCTAssertEqual(first.directory.deletingLastPathComponent().standardizedFileURL.path,root.standardizedFileURL.path)
        XCTAssertEqual(try Data(contentsOf: first.url),original)
        XCTAssertEqual(try Data(contentsOf: second.url),newer)
        first.discard()
        let deadline = Date().addingTimeInterval(3)
        while FileManager.default.fileExists(atPath: first.directory.path),Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.directory.path))
        XCTAssertEqual(try Data(contentsOf: second.url),newer,"An earlier export's cleanup must not remove a later export")
        second.discard()
    }
    func testCancelledNativeExportStagingLeavesNoPartialSource() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try PreparedNativeExport.prepare(data: Data("never exported".utf8),filename: "cancelled",extension: "gpx",root: root)
        }
        do { _ = try await task.value; XCTFail("Cancelled staging produced a provider source") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }
    func testIndividualLongTrackGPXExportsEveryPointBeyondBackupCountLimit() async throws {
        let count = 250_001,id = UUID().uuidString.lowercased()
        let bytes = Data(String(repeating: "24.0000000 54.0000000 0 -32768\n",count: count).utf8)
        let track = Backup.TrackMeta(id: id,name: "Long CAFÉ & patrol",startedAt: 0,endedAt: 1,distanceM: 0,pointCount: count)
        let result = try await FieldExportPreparation.prepare(.track(track,bytes))
        let counter = ExportedTrackPointCounter(),parser = XMLParser(data: result.data)
        parser.delegate = counter
        XCTAssertTrue(parser.parse()); XCTAssertEqual(counter.points,count)
        XCTAssertEqual(counter.tracks,1)
        XCTAssertTrue(String(decoding: result.data,as: UTF8.self).contains("Long CAFÉ &amp; patrol"))
        XCTAssertThrowsError(try TrackCodec.decode(bytes),"External backup decoder remains bounded")
    }
    private func fixture() throws -> Backup.Document {
        var document = Backup.Document(); document.hasSettings = false
        document.waypoints = [.init(id: "point",name: "Hidden point",lat: 24,lon: 54,visible: false)]
        document.graphics = [
            .init(id: "route",name: "Route",type: "route",points: [.init(lat: 24,lon: 54),.init(lat: 24.01,lon: 54)],visible: false),
            .init(id: "area",name: "Area",type: "aa",points: [.init(lat: 24,lon: 54),.init(lat: 24.01,lon: 54),.init(lat: 24,lon: 54.01)])
        ]
        let (track,bytes) = try TrackCodec.imported(name: "Walk",points: [.init(lat: 24,lon: 54),.init(lat: 24.01,lon: 54)],now: 1000)
        document.tracks = [track]; document.trackFiles[track.id] = bytes
        return document
    }

    func testAllFormatsKeepTheirAndroidGeometryPolicyAndHiddenSavedRecords() async throws {
        let source = try fixture()
        for format in TextInterchangeFormat.allCases {
            let result = try await FieldExportPreparation.prepare(.library(format,source.waypoints,source)) { request in
                XCTAssertFalse(Thread.isMainThread)
                return try FieldExportPreparation.build(request)
            }
            let preview = try TextInterchange.preview(result.data,format: format,now: 1000)
            XCTAssertEqual(preview.document.waypoints.map(\.name),["Hidden point"],format.label)
            switch format {
            case .gpx:
                XCTAssertEqual(preview.document.graphics.count,1); XCTAssertEqual(preview.document.tracks.count,1)
            case .csv:
                XCTAssertTrue(preview.document.graphics.isEmpty); XCTAssertTrue(preview.document.tracks.isEmpty)
            case .atak:
                XCTAssertEqual(preview.document.graphics.count,1); XCTAssertTrue(preview.document.tracks.isEmpty)
                XCTAssertEqual(result.filename,"gridfix-datapackage")
            case .geojson,.kml,.kmz:
                // These formats encode a finished track as geographic linework.
                XCTAssertEqual(preview.document.graphics.count,3); XCTAssertTrue(preview.document.tracks.isEmpty)
            }
            XCTAssertEqual(FieldExportDocumentFile(result).data,result.data)
            XCTAssertEqual(FieldExportDocumentFile(result).contentType.preferredFilenameExtension,format == .atak ? "zip" : format.rawValue)
        }
    }

    func testUnusedTrackBytesDoNotPreventCSVOrATAKButCorruptRequiredTrackFails() async throws {
        var source = try fixture(); source.trackFiles[source.tracks[0].id] = Data("invalid log".utf8)
        for format: TextInterchangeFormat in [.csv,.atak] {
            _ = try await FieldExportPreparation.prepare(.library(format,source.waypoints,source))
        }
        do { _ = try await FieldExportPreparation.prepare(.library(.gpx,source.waypoints,source)); XCTFail("Corrupt track exported") }
        catch { XCTAssertTrue(error.localizedDescription.contains("track"),error.localizedDescription) }
    }

    func testSnapshotDoesNotMixLaterEditsAndDeletedTrackFiles() async throws {
        let source = try fixture(), directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let points = WaypointStore(directory: directory), field = FieldDataStore(directory: directory)
        _ = try points.restore(waypoints: source.waypoints,folders: [])
        _ = try field.restore(source)
        let request = FieldExportRequest.library(.gpx,points.waypoints,field.document)
        let entered = expectation(description: "worker entered"), gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        let work = Task {
            try await FieldExportPreparation.prepare(request) { captured in
                XCTAssertFalse(Thread.isMainThread); entered.fulfill()
                XCTAssertEqual(gate.wait(timeout: .now()+5),.success)
                return try FieldExportPreparation.build(captured)
            }
        }
        await fulfillment(of: [entered],timeout: 3)
        points.update(id: "point",draft: .init(name: "Edited after export",lat: 25,lon: 55))
        try field.deleteTrack(source.tracks[0].id)
        try field.deleteGraphic("route")
        gate.signal()
        let result = try await work.value
        let preview = try TextInterchange.preview(result.data,format: .gpx,now: 1000)
        XCTAssertEqual(preview.document.waypoints.first?.name,"Hidden point")
        XCTAssertEqual(preview.document.waypoints.first?.lat,24)
        XCTAssertEqual(preview.document.graphics.first?.name,"Route")
        XCTAssertEqual(preview.document.tracks.first?.name,"Walk")
        XCTAssertTrue(FieldDataStore(directory: directory).document.tracks.isEmpty)
        XCTAssertEqual(WaypointStore(directory: directory).waypoints.first?.name,"Edited after export")
    }

    func testTrackOnlyExportUsesCapturedLogAndAndroidSafeFilename() async throws {
        let source = try fixture(); var track = source.tracks[0]; track.name = "Night: 1 /2"
        let result = try await FieldExportPreparation.prepare(.track(track,source.trackFiles[track.id]!))
        XCTAssertEqual(result.filename,"Night_ 1 _2")
        let preview = try TextInterchange.preview(result.data,format: .gpx,now: 1000)
        XCTAssertTrue(preview.document.waypoints.isEmpty); XCTAssertTrue(preview.document.graphics.isEmpty)
        XCTAssertEqual(preview.document.tracks.first?.name,track.name)
        XCTAssertEqual(preview.document.tracks.first?.pointCount,2)
        track.name = "   "
        let blank = try await FieldExportPreparation.prepare(.track(track,source.trackFiles[track.id]!))
        XCTAssertEqual(blank.filename,"track")
    }

    func testCancelledLateWriterCannotPresentOrClearNewExportAndBusyStartIsRejected() async throws {
        let source = try fixture(), entered = expectation(description: "old export started"), completed = expectation(description: "new export completed")
        let gate = ExportGate()
        let transfer = FieldExportTransfer { request in
            if request.format == .gpx {
                entered.fulfill(); await gate.wait()
                // A writer/provider may finish despite cancellation.
                return .init(data: Data("old".utf8),format: .gpx,filename: "old")
            }
            return try await FieldExportPreparation.prepare(request)
        }
        XCTAssertTrue(transfer.start(.library(.gpx,source.waypoints,source)) { _ in XCTFail("Cancelled export presented") })
        await fulfillment(of: [entered],timeout: 3)
        XCTAssertFalse(transfer.start(.library(.csv,[],source)) { _ in XCTFail("Busy start accepted") })
        let cancelled = transfer.cancel()
        XCTAssertTrue(transfer.start(.library(.csv,source.waypoints,source)) { result in
            if case let .success(output) = result { XCTAssertEqual(output.format,.csv); XCTAssertTrue(String(decoding: output.data,as: UTF8.self).contains("Hidden point")) }
            else { XCTFail("New export failed") }
            completed.fulfill()
        })
        await gate.finish(); await cancelled?.value
        await fulfillment(of: [completed],timeout: 3)
        XCTAssertNil(transfer.format)
    }

    func testFailureClearsBusyStateBeforeRetryCallbackStartsNewExport() async throws {
        let source = try fixture(), completed = expectation(description: "retry export ready")
        let transfer = FieldExportTransfer { request in
            if request.format == .gpx { throw CocoaError(.fileWriteOutOfSpace) }
            return try await FieldExportPreparation.prepare(request)
        }
        XCTAssertTrue(transfer.start(.library(.gpx,source.waypoints,source)) { result in
            guard case .failure = result else { XCTFail("Expected failed preparation"); return }
            XCTAssertNil(transfer.format)
            XCTAssertTrue(transfer.start(.library(.csv,source.waypoints,source)) { result in
                if case let .success(output) = result { XCTAssertEqual(output.format,.csv) }
                else { XCTFail("Retry failed") }
                completed.fulfill()
            })
        })
        await fulfillment(of: [completed],timeout: 3)
        XCTAssertNil(transfer.format)
    }

    func testLargeSnapshotEncodingKeepsMainActorResponsiveAndRoundTripsEveryRecord() async throws {
        let source = try await Task.detached(priority: .userInitiated) {
            var document = Backup.Document(); document.hasSettings = false
            document.waypoints = (0..<5000).map { Waypoint(id: "point-\($0)",name: "Point \($0)",lat: 24+Double($0)*0.000001,lon: 54) }
            document.graphics = (0..<1000).map { i in Backup.Graphic(id: "route-\(i)",name: "Route \(i)",type: "route",points: [.init(lat: 24,lon: 54),.init(lat: 24.01,lon: 54)]) }
            let (track,bytes) = try TrackCodec.imported(name: "Large track",points: (0..<50000).map { TrackPoint(lat: 24+Double($0%1000)*0.000001,lon: 54) },now: 1000)
            document.tracks = [track]; document.trackFiles[track.id] = bytes
            return document
        }.value
        let state = ExportHeartbeat()
        let heartbeat = Task { @MainActor in
            var last = ProcessInfo.processInfo.systemUptime
            while !state.done && !Task.isCancelled {
                let now = ProcessInfo.processInfo.systemUptime
                state.maximumGap = max(state.maximumGap,now-last); last = now; state.pulses += 1
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
        }
        defer { state.done = true; heartbeat.cancel() }
        let start = ProcessInfo.processInfo.systemUptime
        let output = try await FieldExportPreparation.prepare(.library(.gpx,source.waypoints,source))
        let elapsed = ProcessInfo.processInfo.systemUptime-start
        state.done = true; await heartbeat.value
        XCTAssertGreaterThan(state.pulses,2)
        let counts = try await Task.detached {
            let preview = try TextInterchange.preview(output.data,format: .gpx,now: 1000)
            return (preview.document.waypoints.count,preview.document.graphics.count,preview.document.tracks.first?.pointCount)
        }.value
        XCTAssertEqual(counts.0,5000); XCTAssertEqual(counts.1,1000); XCTAssertEqual(counts.2,50000)
        let metrics = String(format: "GPX: 5000 waypoints, 1000 routes, 50000 track points; encode %.3f s; main-actor pulses %d; largest pulse gap %.3f s",elapsed,state.pulses,state.maximumGap)
        print("[field-export-benchmark] \(metrics)")
        let attachment = XCTAttachment(string: metrics); attachment.name = "field-export-benchmark"; attachment.lifetime = .keepAlways; add(attachment)
        // Observe performance without a device-dependent timing pass threshold.
    }

    func testCancellationReachesWorkerEvenWhenBuilderReturnsLate() async throws {
        let source = try fixture(), entered = expectation(description: "encoding began"), gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        let work = Task {
            try await FieldExportPreparation.prepare(.library(.gpx,source.waypoints,source)) { _ in
                entered.fulfill(); XCTAssertEqual(gate.wait(timeout: .now()+5),.success)
                return .init(data: Data("late".utf8),format: .gpx,filename: "late")
            }
        }
        await fulfillment(of: [entered],timeout: 3)
        work.cancel(); gate.signal()
        do { _ = try await work.value; XCTFail("Cancelled encoding returned bytes") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
}

private final class ExportedTrackPointCounter: NSObject, XMLParserDelegate {
    var points = 0,tracks = 0
    func parser(_ parser: XMLParser,didStartElement elementName: String,namespaceURI: String?,qualifiedName qName: String?,attributes attributeDict: [String:String] = [:]) {
        if elementName == "trkpt" { points += 1 }
        if elementName == "trk" { tracks += 1 }
    }
}

private actor ExportGate {
    private var done = false
    private var continuation: CheckedContinuation<Void,Never>?
    func wait() async { if !done { await withCheckedContinuation { continuation = $0 } } }
    func finish() { done = true; continuation?.resume(); continuation = nil }
}

@MainActor
private final class ExportHeartbeat {
    var done = false
    var pulses = 0
    var maximumGap = 0.0
}
