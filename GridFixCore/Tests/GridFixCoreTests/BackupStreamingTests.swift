import XCTest
@testable import GridFixCore

final class BackupStreamingTests: XCTestCase {
    private func document() -> Backup.Document {
        let a="00000000-0000-0000-0000-000000000001",b="00000000-0000-0000-0000-000000000002"
        return .init(waypoints:[.init(id:"point",name:"CAFÉ",lat:24,lon:54)],tracks:[
            .init(id:a,name:"A",startedAt:0,endedAt:1,distanceM:0,pointCount:2),
            .init(id:b,name:"Empty",startedAt:0,endedAt:0,distanceM:0,pointCount:0)],
            trackFiles:[a:Data("24 54 0\r\n25 55 1 -32768\u{2028}\n".utf8),b:Data()])
    }
    func testStreamedBackupRetainsLegacyRecordsRawTracksAndSparseSettingPresence() throws {
        var doc=document();doc.settingsKeys=["nightMode","declinationOverride"];doc.settings.nightMode=false;doc.settings.declinationOverride=nil
        var result=Data();try Backup.writeZip(doc) {result.append($0)}
        let old=try Backup.importZip(Backup.exportZip(doc)),new=try Backup.importZip(result)
        XCTAssertEqual(new.waypoints,old.waypoints);XCTAssertEqual(new.trackFiles,old.trackFiles)
        XCTAssertEqual(new.tracks,old.tracks);XCTAssertEqual(new.settingsKeys,old.settingsKeys)
        XCTAssertEqual(new.settings,old.settings)
        doc.hasSettings=false;result=Data();try Backup.writeZip(doc) {result.append($0)}
        XCTAssertFalse(try Backup.importZip(result).hasSettings)
    }
    func testAggregatePointLimitAndUnknownTrackCannotEmitPartialBackup() throws {
        var doc=document();let id=doc.tracks[0].id
        doc.trackFiles[id]=Data(String(repeating:"24 54 0\n",count:130_001).utf8)
        doc.trackFiles[doc.tracks[1].id]=Data(String(repeating:"24 54 0\n",count:130_000).utf8)
        var result=Data()
        XCTAssertThrowsError(try Backup.writeZip(doc) {result.append($0)})
        XCTAssertTrue(result.isEmpty)
        doc=document();doc.trackFiles[UUID().uuidString.lowercased()]=Data()
        XCTAssertThrowsError(try Backup.writeZip(doc) {result.append($0)})
        XCTAssertTrue(result.isEmpty)
    }
    func testTrackAndMemberBudgetsAreRetainedBeforeOutput() throws {
        var doc=document();doc.trackFiles[doc.tracks[0].id]=Data(count:16*1024*1024+1)
        var result=Data();XCTAssertThrowsError(try Backup.writeZip(doc) {result.append($0)});XCTAssertTrue(result.isEmpty)
        doc.tracks=(0..<512).map {i in .init(id:String(format:"00000000-0000-0000-0000-%012x",i),name:"Empty",startedAt:0,endedAt:0,distanceM:0,pointCount:0)}
        doc.trackFiles=[:]
        XCTAssertThrowsError(try Backup.writeZip(doc) {result.append($0)});XCTAssertTrue(result.isEmpty)
    }
    func testAggregateByteBudgetIncludesManifestAcrossIndividuallyValidMembers() throws {
        var doc=document()
        let member=Data(repeating:10,count:16*1024*1024)
        for track in doc.tracks {doc.trackFiles[track.id]=member}
        var result=Data()
        XCTAssertThrowsError(try Backup.writeZip(doc) {result.append($0)}) {XCTAssertTrue($0.localizedDescription.contains("size"))}
        XCTAssertTrue(result.isEmpty,"The manifest makes two individually valid16MiB members exceed the32MiB total")
        XCTAssertThrowsError(try Backup.exportZip(doc),"Legacy and file-backed budget must agree")
    }
    func testMultiMemberStoredWriterMatchesLegacyBytesIncludingEmptyArchive() throws {
        for values in [[],[ZipArchive.Entry(name:"manifest.json",data:Data("{}".utf8)),.init(name:"tracks/a.txt",data:Data()),.init(name:"tracks/b.txt",data:Data("payload".utf8))]] {
            var result=Data()
            try ZipArchive.writeStored(entries:values.map {value in .init(name:value.name,produce:{try $0(value.data)})}) {result.append($0)}
            XCTAssertEqual(result,ZipArchive.write(entries:values))
        }
    }
    func testLateMemberValidationAndChangedSecondVisitCannotFinishArchive() throws {
        enum Failure:Error {case checksum}
        var output=Data()
        let bad=ZipArchive.StoredEntry(name:"bad",produce:{try $0(Data([1]));throw Failure.checksum})
        XCTAssertThrowsError(try ZipArchive.writeStored(entries:[.init(name:"good",produce:{try $0(Data([2]))}),bad]) {output.append($0)})
        XCTAssertTrue(output.isEmpty,"Every member must validate before any ZIP output")
        var calls=0
        let changed=ZipArchive.StoredEntry(name:"changed",produce:{sink in calls += 1;try sink(Data([calls==1 ? 1 : 2]))})
        XCTAssertThrowsError(try ZipArchive.writeStored(entries:[.init(name:"empty",produce:{_ in}),changed]) {output.append($0)})
        XCTAssertThrowsError(try ZipArchive.read(output))
    }
}
