import Foundation
import GridFixCore
import XCTest
@testable import MGRSGPS

@MainActor
final class GPXFileExportTests: XCTestCase {
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        addTeardownBlock { try? FileManager.default.removeItem(at:root) }
        return root
    }
    private func fixture(count: Int) async throws -> (URL,FieldDataStore,Backup.TrackMeta) {
        let root = try directory(),id = UUID().uuidString.lowercased()
        let data = await Task.detached {
            Data((0..<count).map { "24 54 \(Int64($0+1)*1000) 12.75\n" }.joined().utf8)
        }.value
        let track = Backup.TrackMeta(id:id,name:"Long CAFÉ & patrol",startedAt:1,endedAt:Int64(count)*1000,distanceM:0,pointCount:count)
        var document = Backup.Document(tracks:[track],trackFiles:[id:data]); document.hasSettings = false
        let eager = FieldDataStore(directory:root)
        try await FieldEditAction.apply(.saveRecordedTrack(document),to:eager)
        let field = FieldDataStore(directory:root,loadImmediately:false)
        await field.load { try $0.prepare(deferTrackContents:true) }
        XCTAssertNil(field.loadError); XCTAssertTrue(field.document.trackFiles.isEmpty)
        return (root,field,track)
    }
    func testWholeLibraryLongLogUsesFilePayloadAndRetainsEveryPointBeyondImportLimits() async throws {
        let (_,field,_) = try await fixture(count:300_003)
        let result = try await FieldExportPreparation.prepare(.library(.gpx,[],field.document))
        guard case .file(let file) = result.payload else { return XCTFail("Production GPX must stream to a file") }
        let parser = try XCTUnwrap(XMLParser(contentsOf:file.url)),counter = GPXFilePointCounter()
        parser.delegate = counter
        XCTAssertTrue(parser.parse(),String(describing:parser.parserError))
        XCTAssertEqual(counter.points,300_003); XCTAssertEqual(counter.times,300_003); XCTAssertEqual(counter.elevations,300_003)
        XCTAssertGreaterThan(try result.payload.byteCount,UInt64(ProtectedFiles.maximumFileBytes))
        XCTAssertTrue(field.document.trackFiles.isEmpty)
        let document = FieldExportDocumentFile(result)
        guard case .file = document.payload else { return XCTFail("Native presentation must retain the file payload") }
        do { _ = try await FieldExportPreparation.protect(result,password:"local-test-only"); XCTFail("Protected envelope size limit") }
        catch { XCTAssertTrue(error.localizedDescription.contains("Too large to protect")) }
        XCTAssertTrue(FileManager.default.fileExists(atPath:file.url.path))
    }
    func testWholeLibraryKMLUsesFilePayloadAndRetainsLongDeferredTrack() async throws {
        let (_,field,_) = try await fixture(count:300_003)
        let result = try await FieldExportPreparation.prepare(.library(.kml,[],field.document))
        guard case .file(let file) = result.payload else { return XCTFail("Production KML must stream to a file") }
        XCTAssertEqual(result.format,.kml); XCTAssertEqual(file.url.pathExtension,"kml")
        let parser = try XCTUnwrap(XMLParser(contentsOf:file.url)),counter = KMLFileCoordinateCounter()
        parser.delegate = counter
        XCTAssertTrue(parser.parse(),String(describing:parser.parserError)); XCTAssertEqual(counter.count,300_003)
        XCTAssertTrue(field.document.trackFiles.isEmpty)
        let document = FieldExportDocumentFile(result)
        XCTAssertEqual(document.contentType,.gridFixKML)
        guard case .file = document.payload else { return XCTFail("KML native presenter must retain a file") }
    }
    func testKMLLateChecksumFailureRemovesPartialFileWithoutChangingSavedSource() async throws {
        let (root,_,_) = try await fixture(count:5000)
        let index = root.appendingPathComponent("field-data-v2.json"),originalIndex = try Data(contentsOf:index)
        let log = try XCTUnwrap(FileManager.default.contentsOfDirectory(at:root.appendingPathComponent("field-track-logs-v2"),includingPropertiesForKeys:nil).first)
        let changed = Data(String(repeating:"25 55 1000 12.75\n",count:5000).utf8)
        try changed.write(to:log,options:.atomic)
        let field = FieldDataStore(directory:root,loadImmediately:false)
        await field.load { try $0.prepare(deferTrackContents:true) }
        XCTAssertNil(field.loadError)
        let output = try directory()
        do {
            _ = try await FieldExportPreparation.prepare(.library(.kml,[],field.document)) { try FieldExportPreparation.buildForPresentation($0,root:output) }
            XCTFail("Checksum-invalid KML returned a file")
        } catch { XCTAssertTrue(error.localizedDescription.contains("checksum")) }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:output.path).isEmpty)
        XCTAssertEqual(try Data(contentsOf:log),changed); XCTAssertEqual(try Data(contentsOf:index),originalIndex)
    }
    func testApprovedNativeFilenameCopiesCompleteIndependentFileWithoutReadingItsPayload() async throws {
        let (_,field,track) = try await fixture(count:100)
        let result = try await FieldExportPreparation.prepare(.savedTrack(field.trackReadSnapshot(track.id)))
        guard case .file(let source) = result.payload else { return XCTFail("Expected streamed selected-track export") }
        let expected = try Data(contentsOf:source.url),root = try directory(),document = FieldExportDocumentFile(result)
        let staged = try await Task.detached { try PreparedNativeExport.prepare(payload:document.payload,filename:"CAFÉ patrol",extension:"gpx",root:root) }.value
        XCTAssertEqual(staged.url.lastPathComponent,"CAFÉ patrol.gpx"); XCTAssertNotEqual(staged.url,source.url)
        source.discard()
        let deadline = Date().addingTimeInterval(3)
        while FileManager.default.fileExists(atPath:source.directory.path) && Date() < deadline { try await Task.sleep(nanoseconds:1_000_000) }
        XCTAssertFalse(FileManager.default.fileExists(atPath:source.directory.path))
        XCTAssertEqual(try Data(contentsOf:staged.url),expected)
    }
    func testLateChecksumFailureDeletesPartialExportAndKeepsSourceAndIndex() async throws {
        let (root,_,track) = try await fixture(count:5000)
        let index = root.appendingPathComponent("field-data-v2.json"),originalIndex = try Data(contentsOf:index)
        let log = try XCTUnwrap(FileManager.default.contentsOfDirectory(at:root.appendingPathComponent("field-track-logs-v2"),includingPropertiesForKeys:nil).first)
        let changed = Data(String(repeating:"25 55 1000 12.75\n",count:5000).utf8)
        try changed.write(to:log,options:.atomic)
        let field = FieldDataStore(directory:root,loadImmediately:false)
        await field.load { try $0.prepare(deferTrackContents:true) }
        XCTAssertNil(field.loadError)
        let output = try directory()
        do {
            _ = try await FieldExportPreparation.prepare(.savedTrack(field.trackReadSnapshot(track.id))) { try FieldExportPreparation.buildForPresentation($0,root:output) }
            XCTFail("Checksum-invalid export returned a file")
        } catch { XCTAssertTrue(error.localizedDescription.contains("checksum")) }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:output.path).isEmpty)
        XCTAssertEqual(try Data(contentsOf:log),changed); XCTAssertEqual(try Data(contentsOf:index),originalIndex)
    }
    func testCancellationAfterFirstOutputChunkRemovesStagedFile() async throws {
        let (_,field,_) = try await fixture(count:100_000),root = try directory(),snapshot = field.document
        let work = Task {
            try await FieldExportPreparation.prepare(.library(.gpx,[],snapshot)) { try FieldExportPreparation.buildForPresentation($0,root:root) }
        }
        let deadline = Date().addingTimeInterval(5)
        var started = false
        while !started && Date() < deadline {
            let children = try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil)
            for folder in children {
                for file in (try? FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:[.fileSizeKey])) ?? [] {
                    if (try? file.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0) ?? 0 > 0 { started = true }
                }
            }
            if !started { try await Task.sleep(nanoseconds:1_000_000) }
        }
        XCTAssertTrue(started,"Wait for actual output before cancellation")
        work.cancel()
        do { _ = try await work.value; XCTFail("Cancelled export returned a file") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:root.path).isEmpty)
        XCTAssertTrue(field.document.trackFiles.isEmpty)
    }
}

private final class GPXFilePointCounter: NSObject,XMLParserDelegate {
    var points = 0,times = 0,elevations = 0
    func parser(_ parser:XMLParser,didStartElement name:String,namespaceURI:String?,qualifiedName:String?,attributes:[String:String]) {
        if name == "trkpt" { points += 1 }; if name == "time" { times += 1 }; if name == "ele" { elevations += 1 }
    }
}

private final class KMLFileCoordinateCounter: NSObject,XMLParserDelegate {
    var count = 0
    private var reading = false,inToken = false
    func parser(_ parser:XMLParser,didStartElement name:String,namespaceURI:String?,qualifiedName:String?,attributes:[String:String]) { if name == "coordinates" { reading = true; inToken = false } }
    func parser(_ parser:XMLParser,foundCharacters string:String) {
        guard reading else { return }
        for character in string {
            if character.isWhitespace { inToken = false }
            else if !inToken { count += 1; inToken = true }
        }
    }
    func parser(_ parser:XMLParser,didEndElement name:String,namespaceURI:String?,qualifiedName:String?) { if name == "coordinates" { reading = false } }
}
