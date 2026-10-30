import XCTest
@testable import GridFixCore

final class ProtectedFilesTests: XCTestCase {
    private let password = "Nørth 雪 🧭"
    private func fixture(_ name: String,ext: String) throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: name,withExtension: ext)))
    }
    func testIndependentJavaDeflatedFilesAllSixFormatsAndFreshSwiftExports() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("gridfix-protected-file-interop")
        try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: true)
        for format in TextInterchangeFormat.allCases {
            let stem = "protected-file-"+format.rawValue
            let expected = try fixture(stem,ext: "plain"), sealed = try fixture(stem,ext: "mgrsgps")
            let name = "OP CAFÉ."+(format == .atak ? "zip" : format.rawValue)
            XCTAssertEqual(try ProtectedFiles.open(sealed,password: password),.file(name: name,data: expected))
            let preview = try TextInterchange.preview(expected,filename: name,now: 1000)
            XCTAssertEqual(preview.document.waypoints.map(\.name),["OP CAFÉ"],format.label)
            let swift = try ProtectedFiles.seal(name: name,bytes: expected,password: password)
            XCTAssertNotEqual(swift,sealed)
            XCTAssertEqual(try ProtectedFiles.open(swift,password: password),.file(name: name,data: expected))
            try swift.write(to: directory.appendingPathComponent("swift-"+stem+".mgrsgps"))
        }
    }
    func testAuthenticatedBackupIsDistinguishedWithoutTreatingManifestAsAnExport() throws {
        var document = Backup.Document(); document.hasSettings = false
        document.waypoints = [.init(id: "point",name: "Saved",lat: 35,lon: -79)]
        let archive = try Backup.exportZip(document)
        guard case let .backup(bytes) = try ProtectedFiles.open(BackupCrypto.seal(archive,password: password),password: password) else { return XCTFail("Backup was treated as an export") }
        XCTAssertEqual(try Backup.importZip(bytes).waypoints,document.waypoints)
    }
    func testWrongPasswordTamperAndUnsafeAuthenticatedLayoutsAreRejected() throws {
        let sealed = try fixture("protected-file-gpx",ext: "mgrsgps")
        XCTAssertThrowsError(try ProtectedFiles.open(sealed,password: "incorrect"))
        var changed = sealed; changed[changed.count-1] ^= 1
        XCTAssertThrowsError(try ProtectedFiles.open(changed,password: password))
        let data = Data("gpx".utf8)
        let layouts: [[ZipArchive.Entry]] = [[],[.init(name: "a.gpx",data: data),.init(name: "b.gpx",data: data)],
            [.init(name: "folder/",data: Data()),.init(name: "a.gpx",data: data)],
            [.init(name: "folder/a.gpx",data: data)],[.init(name: "../a.gpx",data: data)],
            [.init(name: "a\\b.gpx",data: data)],[.init(name: "a\0.gpx",data: data)]]
        for entries in layouts {
            let input = try BackupCrypto.seal(ZipArchive.write(entries: entries),password: password)
            XCTAssertThrowsError(try ProtectedFiles.open(input,password: password),entries.map(\.name).joined(separator: ","))
        }
    }
    func testWriterAndReaderHaveMatchingSixteenMegabyteLimitAndSafeBasename() throws {
        let oversized = Data(repeating: 0,count: ProtectedFiles.maximumFileBytes+1)
        XCTAssertThrowsError(try ProtectedFiles.seal(name: "big.gpx",bytes: oversized,password: password))
        let tooLarge = try BackupCrypto.seal(ZipArchive.write(entries: [.init(name: "big.gpx",data: oversized)]),password: password)
        XCTAssertThrowsError(try ProtectedFiles.open(tooLarge,password: password))
        XCTAssertEqual(try ProtectedFiles.open(ProtectedFiles.seal(name: "/folder/OP CAFÉ.gpx",bytes: Data(),password: password),password: password),.file(name: "OP CAFÉ.gpx",data: Data()))
        XCTAssertThrowsError(try ProtectedFiles.seal(name: "..",bytes: Data(),password: password))
        XCTAssertThrowsError(try ProtectedFiles.seal(name: String(repeating: "x",count: 65536),bytes: Data(),password: password))
    }
}
