import XCTest
@testable import GridFixCore

final class FieldLogSummaryTests: XCTestCase {
    private func fixture(count: Int = 3) throws -> (URL,Backup.Document) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        addTeardownBlock { try? FileManager.default.removeItem(at:root) }
        let points = (0..<count).map { TrackPoint(lat:24+Double($0%50)*0.0001,lon:54,time:Int64($0)) }
        let (meta,bytes) = try TrackCodec.imported(name:"Summary CAFÉ patrol",points:points,now:1)
        var doc = Backup.Document(); doc.hasSettings = false; doc.tracks = [meta]; doc.trackFiles[meta.id] = bytes
        _ = try FieldDataStore(directory:root).restore(doc)
        return (root.appendingPathComponent(FieldDataDisk.indexName),doc)
    }
    private func index(_ url: URL) throws -> [String:Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:Any])
    }
    private func rewrite(_ url: URL,_ change: (inout [String:Any]) throws -> Void) throws {
        var value = try index(url); try change(&value)
        try JSONSerialization.data(withJSONObject:value,options:.sortedKeys).write(to:url,options:.atomic)
    }
    private func changeReference(_ url: URL,_ id: String,_ change: (inout [String:Any]) -> Void) throws {
        try rewrite(url) { value in
            var logs = try XCTUnwrap(value["logs"] as? [String:[String:Any]])
            var ref = try XCTUnwrap(logs[id]); change(&ref); logs[id] = ref; value["logs"] = logs
        }
    }
    func testValidatedLargeLogSkipsPointParsingButKeepsExactMetadataAndBytes() throws {
        let (url,doc) = try fixture(count:20_000), before = try Data(contentsOf:url)
        var parsed = 0
        let start = Date()
        let (loaded,_) = try FieldDataDisk.read(url) { bytes in parsed += 1; return try TrackCodec.summarizeLocal(bytes) }
        let cachedSeconds = Date().timeIntervalSince(start)
        XCTAssertEqual(parsed,0)
        XCTAssertEqual(loaded.tracks,doc.tracks); XCTAssertEqual(loaded.trackFiles,doc.trackFiles)
        XCTAssertEqual(try Data(contentsOf:url),before,"Reading a receipt cannot rewrite saved files")
        try changeReference(url,doc.tracks[0].id) { $0.removeValue(forKey:"summary") }
        let uncachedStart = Date()
        let (uncached,_) = try FieldDataDisk.read(url) { bytes in parsed += 1; return try TrackCodec.summarizeLocal(bytes) }
        let uncachedSeconds = Date().timeIntervalSince(uncachedStart)
        XCTAssertEqual(parsed,1); XCTAssertEqual(uncached.tracks,loaded.tracks); XCTAssertEqual(uncached.trackFiles,loaded.trackFiles)
        // Informational measurement; correctness and parser-call counts are
        // deterministic checks, rather than a machine-dependent speed limit.
        print("20000-point startup seconds: cached \(cachedSeconds), legacy \(uncachedSeconds)")
    }
    func testLegacyReferenceParsesOnceAndReceiptPersistsOnlyOnNextConfirmedEdit() throws {
        let (url,doc) = try fixture(), id = doc.tracks[0].id
        try changeReference(url,id) { $0.removeValue(forKey:"summary") }
        let original = try Data(contentsOf:url)
        var parsed = 0
        let (loaded,refs) = try FieldDataDisk.read(url) { bytes in parsed += 1; return try TrackCodec.summarizeLocal(bytes) }
        XCTAssertEqual(parsed,1); XCTAssertEqual(loaded.tracks,doc.tracks)
        XCTAssertNotNil(refs[id]?.summary); XCTAssertEqual(try Data(contentsOf:url),original)
        let store = FieldDataStore(directory:url.deletingLastPathComponent())
        XCTAssertNil(store.loadError); try store.moveTrack(id,to:"Changed folder")
        let logs = try XCTUnwrap(index(url)["logs"] as? [String:[String:Any]])
        XCTAssertNotNil(logs[id]?["summary"])
        parsed = 0
        let (edited,_) = try FieldDataDisk.read(url) { bytes in parsed += 1; return try TrackCodec.summarizeLocal(bytes) }
        XCTAssertEqual(parsed,0); XCTAssertEqual(edited.tracks[0].folder,"Changed folder")
        XCTAssertEqual(edited.trackFiles,doc.trackFiles)
    }
    func testCachedStatisticsNeverBypassChangedPointChecksumOrPreservation() throws {
        let (url,doc) = try fixture(), original = try Data(contentsOf:url)
        let logs = try XCTUnwrap(index(url)["logs"] as? [String:[String:Any]])
        let name = try XCTUnwrap(logs[doc.tracks[0].id]?["name"] as? String)
        let file = url.deletingLastPathComponent().appendingPathComponent(FieldDataDisk.logsName).appendingPathComponent(name)
        let damaged = Data("24 55 0\n".utf8); try damaged.write(to:file,options:.atomic)
        var parsed = 0
        XCTAssertThrowsError(try FieldDataDisk.read(url) { bytes in parsed += 1; return try TrackCodec.summarizeLocal(bytes) })
        XCTAssertEqual(parsed,0,"Checksum fails before either cached or recomputed statistics are accepted")
        let store = FieldDataStore(directory:url.deletingLastPathComponent())
        XCTAssertNotNil(store.loadError); XCTAssertThrowsError(try store.setTrackVisible(doc.tracks[0].id,visible:false))
        XCTAssertEqual(try Data(contentsOf:url),original); XCTAssertEqual(try Data(contentsOf:file),damaged)
    }
    func testDamagedUnknownOrMalformedOptionalReceiptFallsBackToStrictRows() throws {
        for variation in 0..<5 {
            let (url,doc) = try fixture(), id = doc.tracks[0].id
            try changeReference(url,id) { ref in
                if variation == 4 { ref["summary"] = "damaged cache"; return }
                var summary = ref["summary"] as! [String:Any]
                switch variation {
                case 0: summary["version"] = 999
                case 1: summary["count"] = 200
                case 2: summary["distanceM"] = -1
                default: summary["receipt"] = String(repeating:"0",count:64)
                }
                ref["summary"] = summary
            }
            let before = try Data(contentsOf:url)
            var parsed = 0
            let (loaded,_) = try FieldDataDisk.read(url) { bytes in parsed += 1; return try TrackCodec.summarizeLocal(bytes) }
            XCTAssertEqual(parsed,1); XCTAssertEqual(loaded.tracks,doc.tracks)
            XCTAssertEqual(loaded.trackFiles,doc.trackFiles); XCTAssertEqual(try Data(contentsOf:url),before)
        }
    }
    func testReceiptIsBoundToItsExactPointChecksum() throws {
        let (a,doc) = try fixture(count:3), (b,other) = try fixture(count:4)
        let otherLogs = try XCTUnwrap(index(b)["logs"] as? [String:[String:Any]])
        let copied = try XCTUnwrap(otherLogs[other.tracks[0].id]?["summary"])
        try changeReference(a,doc.tracks[0].id) { $0["summary"] = copied }
        var parsed = 0
        let (loaded,_) = try FieldDataDisk.read(a) { bytes in parsed += 1; return try TrackCodec.summarizeLocal(bytes) }
        XCTAssertEqual(parsed,1); XCTAssertEqual(loaded.tracks,doc.tracks)
    }
    func testValidatedReceiptOverridesManifestStatisticsWithoutTrustingStaleValues() throws {
        let (url,doc) = try fixture()
        try rewrite(url) { value in
            var changed = doc; changed.tracks[0].pointCount = 100; changed.tracks[0].distanceM = 12345
            value["manifest"] = try Backup.encodeManifest(changed).base64EncodedString()
        }
        var parsed = 0
        let (loaded,_) = try FieldDataDisk.read(url) { bytes in parsed += 1; return try TrackCodec.summarizeLocal(bytes) }
        XCTAssertEqual(parsed,0); XCTAssertEqual(loaded.tracks,doc.tracks)
    }
}
