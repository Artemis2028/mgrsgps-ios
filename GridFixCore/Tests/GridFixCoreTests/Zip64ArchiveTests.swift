import XCTest
@testable import GridFixCore

final class Zip64ArchiveTests: XCTestCase {
    private func fixture(_ name: String,_ ext: String = "zip") throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: name,withExtension: ext)))
    }
    private func index(_ data: Data,_ signature: [UInt8]) throws -> Int {
        try XCTUnwrap(data.range(of: Data(signature))).lowerBound
    }
    private func write<T: FixedWidthInteger>(_ data: inout Data,_ offset: Int,_ value: T) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { data.replaceSubrange(offset..<(offset+MemoryLayout<T>.size),with: $0) }
    }
    private func word(_ data: Data,_ offset: Int) -> Int { Int(data[offset]) | Int(data[offset+1]) << 8 }
    private func centralExtra(_ data: Data) throws -> Int {
        let central = try index(data,[0x50,0x4b,0x01,0x02])
        return central+46+word(data,central+28)
    }
    func testIndependentLocalZIP64StoredAndStreamedDeflate() throws {
        for name in ["python-local64-stored","python-local64-streamed","zip64-central-size","zip64-central-offset"] {
            let bytes = try fixture(name)
            let entries = try ZipArchive.read(bytes)
            XCTAssertEqual(entries.map(\.name),["doc.kml"])
            XCTAssertTrue(String(decoding: entries[0].data,as: UTF8.self).contains("ZIP64 rally"))
            let result = try KMZ.parse(bytes)
            XCTAssertEqual(result.waypoints.count,1); XCTAssertEqual(result.waypoints[0].name,"ZIP64 rally")
            XCTAssertEqual(result.waypoints[0].lat,24.4539); XCTAssertEqual(result.waypoints[0].lon,54.3773)
        }
    }
    func testFullZIP64CentralDirectoryBackupAndNestedPackageKeepOriginalContent() throws {
        let backup = try Backup.importZip(fixture("zip64-full-backup"))
        let original = try Backup.importZip(fixture("android-backup-contract"))
        XCTAssertEqual(backup.waypoints,original.waypoints)
        XCTAssertEqual(backup.trackFiles,original.trackFiles)
        XCTAssertEqual(backup.graphics.map(\.id),original.graphics.map(\.id))
        XCTAssertEqual(backup.settings.orientation,original.settings.orientation)
        XCTAssertEqual(backup.tracks.map(\.pointCount),original.tracks.map(\.pointCount))
        let package = try ATAKPackage.parse(fixture("zip64-full-datapackage"))
        let expected = try ATAKPackage.parse(fixture("android-mission-package"))
        XCTAssertEqual(package.fingerprint(),expected.fingerprint())
        XCTAssertEqual(try KMZ.parse(fixture("zip64-full-kmz","kmz")).waypoints[0].name,"ZIP64 rally")
    }
    func testZIP64FooterOverflowTruncationConflictsAndSplitArchivesReject() throws {
        let data = try fixture("zip64-full-kmz","kmz")
        let record = try index(data,[0x50,0x4b,0x06,0x06]), locator = try index(data,[0x50,0x4b,0x06,0x07])
        let end = try index(data,[0x50,0x4b,0x05,0x06])
        for offset in [record+4,record+32,record+40,record+48,locator+8] {
            var bad = data; write(&bad,offset,UInt64.max)
            XCTAssertThrowsError(try ZipArchive.read(bad),"offset \(offset)")
        }
        for (offset,value) in [(locator+4,UInt32(1)),(locator+16,UInt32(2)),(record+16,UInt32(1)),(record+20,UInt32(1))] {
            var bad = data; write(&bad,offset,value); XCTAssertThrowsError(try ZipArchive.read(bad))
        }
        var conflict = data; write(&conflict,end+10,UInt16(2)); XCTAssertThrowsError(try ZipArchive.read(conflict))
        var short = data; write(&short,record+4,UInt64(43)); XCTAssertThrowsError(try ZipArchive.read(short))
        var missing = data; write(&missing,locator,UInt32(0)); XCTAssertThrowsError(try ZipArchive.read(missing))
    }
    func testZIP64EntryValuesAreBoundedBeforeIntegerConversionOrAllocation() throws {
        let data = try fixture("zip64-full-kmz","kmz"), extra = try centralExtra(data)
        for offset in [extra+4,extra+12,extra+20] {
            var bad = data; write(&bad,offset,UInt64.max)
            XCTAssertThrowsError(try ZipArchive.read(bad))
        }
        var large = data; write(&large,extra+4,UInt64(ZipArchive.entryLimit+1))
        XCTAssertThrowsError(try ZipArchive.read(large))
        var disk = data; write(&disk,extra+28,UInt32(1)); XCTAssertThrowsError(try ZipArchive.read(disk))
        var missing = data; write(&missing,extra,UInt16(0x1234)); XCTAssertThrowsError(try ZipArchive.read(missing))
        var short = data; write(&short,extra+2,UInt16(7)); XCTAssertThrowsError(try ZipArchive.read(short))
        let localExtra = 30+word(data,26)
        var badLocal = data; write(&badLocal,localExtra+2,UInt16(8)); XCTAssertThrowsError(try ZipArchive.read(badLocal))
    }
    func testZIP64DescriptorAndLocalMetadataMustAgreeWithVerifiedData() throws {
        let data = try fixture("zip64-full-kmz","kmz")
        let descriptor = try index(data,[0x50,0x4b,0x07,0x08])
        for offset in [descriptor+4,descriptor+8,descriptor+16] {
            var bad = data; bad[offset] ^= 0xff; XCTAssertThrowsError(try ZipArchive.read(bad))
        }
        let stored = try fixture("python-local64-stored")
        var crc = stored; crc[14] ^= 1; XCTAssertThrowsError(try ZipArchive.read(crc))
        var sizes = stored; sizes[30+word(stored,26)+4] ^= 1; XCTAssertThrowsError(try ZipArchive.read(sizes))
    }
    func testEveryTruncatedPrefixRejectsWithoutTrapping() throws {
        let data = try fixture("zip64-full-kmz","kmz")
        for length in 0..<data.count { XCTAssertThrowsError(try ZipArchive.read(Data(data.prefix(length))),"prefix \(length)") }
    }
    func testCustomEntryCountAndTotalBudgetsStillApplyToZIP64() throws {
        let data = try fixture("zip64-full-backup")
        for limits in [ZipArchive.Limits(entryBytes: 16*1024*1024,totalBytes: 32*1024*1024,entries: 1),
                       .init(entryBytes: 16*1024*1024,totalBytes: 1,entries: 512)] {
            XCTAssertThrowsError(try ZipArchive.visit(data,limits: limits) { _,_ in })
        }
    }
    func testUnsignedDescriptorsAndSignatureValuedChecksum() throws {
        for name in ["python-unsigned-32","python-unsigned-64"] {
            XCTAssertEqual(try KMZ.parse(fixture(name)).waypoints[0].name,"ZIP64 rally")
        }
        let entries = try ZipArchive.read(fixture("zip64-crc-signature"))
        XCTAssertEqual(entries[0].data,Data([0xac,0x0a,0x7a,0xd5]))
    }
    func testActualBackupBudgetBoundaryIncludesIgnoredFilesAndPreservesTracks() throws {
        let data = try fixture("zip64-budget-boundary")
        var total = 0
        try ZipArchive.visit(data) { _,bytes in total += bytes.count }
        XCTAssertEqual(total,32*1024*1024)
        let restored = try Backup.importZip(data)
        XCTAssertEqual(restored.waypoints[0].id,"contract-vertex")
        XCTAssertEqual(restored.trackFiles.count,1)
        XCTAssertEqual(restored.tracks[0].pointCount,2)
        XCTAssertThrowsError(try ZipArchive.visit(data,limits: .init(entryBytes: 16*1024*1024,totalBytes: total-1,entries: 512)) { _,_ in })
    }
    func testCancellationBeforeLargeEntryDecodeDoesNotFinishImport() async throws {
        let data = try fixture("zip64-budget-boundary")
        let work = Task {
            try ZipArchive.visit(data,beforeEntry: { name,_ in
                if name == "ignored-a.bin" { withUnsafeCurrentTask { $0?.cancel() } }
            }) { name,_ in
                if name == "ignored-a.bin" { XCTFail("Cancelled large entry should not be delivered") }
            }
        }
        do { try await work.value; XCTFail("Expected cancellation") }
        catch is CancellationError { }
    }
    func testClassicDirectoryCommentCannotMasqueradeAsZIP64Locator() throws {
        var data = ZipArchive.write(entries: [.init(name: "plain.txt",data: Data("plain".utf8))])
        let central = try index(data,[0x50,0x4b,0x01,0x02]), end = try index(data,[0x50,0x4b,0x05,0x06])
        write(&data,central+32,UInt16(20))
        var comment = Data(repeating: 0,count: 20)
        write(&comment,0,UInt32(0x07064b50)); write(&comment,4,UInt32(99))
        data.insert(contentsOf: comment,at: end)
        write(&data,end+20+12,UInt32(end-central+20))
        XCTAssertEqual(try ZipArchive.read(data)[0].data,Data("plain".utf8))
    }
}
