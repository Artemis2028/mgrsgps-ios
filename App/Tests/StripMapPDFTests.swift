import GridFixCore
import PDFKit
import XCTest
@testable import MGRSGPS

@MainActor
final class StripMapPDFTests: XCTestCase {
    func testLaneLimitsUseCheckpointPrecedenceAndOneSnapshotAcrossTextAndPDF() throws {
        let points = (0..<4).map { GeoPoint(lat: 24+Double($0)*0.001,lon: 54) }
        let settings = AppSettings(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let route = Backup.Graphic(id: "route",name: "Lane patrol",type: "route",points: points.map { .init(lat: $0.lat,lon: $0.lon) })
        var road = Backup.Graphic(id: "road",name: "Rte 12",type: "phase_line",points: [])
        let routeLane = NavLane(id: "route-lane",name: "Whole route",left: .init(graphicId: road.id),right: .init(label: "Bear Creek"),backstop: .init(label: "Power line"),scope: .route,targetId: route.id,visible: false)
        let checkpointLane = NavLane(id: "cp-lane",name: "Checkpoint",left: .init(label: "Tree line"),right: .init(label: "Draw"),backstop: .init(label: "Rail"),scope: .checkpoint,targetId: "cp2")
        let waypoint = Waypoint(id: "cp2",name: "CP2",lat: points[2].lat,lon: 54,sourceRouteId: route.id,sourceRoutePointIndex: 2)
        let input = RouteCardRequest(route: route,settings: settings,lanes: [routeLane,checkpointLane],waypoints: [waypoint],graphics: [road])
        road.name = "Edited after capture"
        let report = try RouteCardOutput.report(input)
        XCTAssertEqual(report.rows.map(\.limits),["L: Rte 12 · R: Bear Creek · BS: Power line","L: Tree line · R: Draw · BS: Rail","L: Rte 12 · R: Bear Creek · BS: Power line"])
        XCTAssertTrue(report.shareText.contains("BS: Rail")); XCTAssertFalse(report.shareText.contains("Edited after capture"))
        let pdf = try document(report), text = try XCTUnwrap(pdf.string)
        for label in ["Rte 12","Bear Creek","Power line","Tree line","Rail"] { XCTAssertTrue(text.contains(label),text) }
        assertTextInsidePage(pdf)
        try writeReview(report,name: "lane-route-card")
        let changed = RouteCardRequest(route: route,settings: settings,lanes: [routeLane],waypoints: [waypoint],graphics: [road])
        XCTAssertNotEqual(input,changed)
    }
    func testLongLaneLabelsWrapPaginateAndKeepEveryLegAndTotalsInBounds() throws {
        let points = (0..<85).map { GeoPoint(lat: 24+Double($0)*0.001,lon: 54+Double($0%7)*0.001) }
        let labels = (1..<points.count).map { index -> String? in
            String(format: "LIMIT-LEG-%04d",index)+" · L: "+String(repeating: "tree line ",count: 8)+" · R: "+String(repeating: "creek bend ",count: 8)+" · BS: "+String(repeating: "power line ",count: 8)
        }
        let report = try RouteCard.report(name: "Long lane labels",points: points,configuration: .init(),legLimits: labels) { _ in 0 }
        let pdf = try document(report), text = try XCTUnwrap(pdf.string)
        XCTAssertGreaterThan(pdf.pageCount,2)
        for index in 1..<points.count {
            let marker = String(format: "LIMIT-LEG-%04d",index)
            XCTAssertEqual(text.components(separatedBy: marker).count-1,1,marker)
        }
        XCTAssertEqual(text.components(separatedBy: "TOTAL").count-1,1)
        XCTAssertTrue(try XCTUnwrap(pdf.page(at: pdf.pageCount-1)?.string).contains("TOTAL"))
        assertTextInsidePage(pdf); try writeReview(report,name: "lane-route-long-labels")
    }
    private func writeReview(_ report: RouteCard.Report,name: String) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("gridfix-pdf-review",isDirectory: true)
        try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: true)
        try StripMapPDF.render(report).write(to: folder.appendingPathComponent(name+".pdf"))
    }
    private func request(points: [GeoPoint],name: String = "Training",north: NorthReference = .trueNorth) -> RouteCardRequest {
        let settings = AppSettings(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        settings.northRef = north; settings.mgrsDigits = 4
        let route = Backup.Graphic(id: "pdf-route",name: name,type: "route",points: points.map { .init(lat: $0.lat,lon: $0.lon) })
        return RouteCardRequest(route: route,settings: settings)
    }
    private func document(_ report: RouteCard.Report) throws -> PDFDocument {
        try XCTUnwrap(PDFDocument(data: StripMapPDF.render(report)))
    }
    func testA4KnownRouteContainsScreenAndShareNumbersAndPrintableBounds() throws {
        let report = try RouteCardOutput.report(request(points: [.init(lat: 0,lon: 0),.init(lat: 0,lon: 0.01)]),date: .init(timeIntervalSince1970: 1700000000))
        let pdf = try document(report), page = try XCTUnwrap(pdf.page(at: 0)), text = try XCTUnwrap(pdf.string)
        XCTAssertEqual(pdf.pageCount,1); XCTAssertEqual(page.bounds(for: .mediaBox),CGRect(x: 0,y: 0,width: 595,height: 842))
        for expected in ["ROUTE CARD - TRAINING","142213Z NOV 23","090°","270°","1.11 km","724","SP","RP","Page 1 of 1",report.rows[0].destinationGrid] { XCTAssertTrue(text.contains(expected),expected+" missing: "+text) }
        XCTAssertTrue(report.shareText.contains(report.rows[0].destinationGrid))
        assertTextInsidePage(pdf)
        let share = ShareableRoutePDF(data: try StripMapPDF.render(report),filename: StripMapPDF.filename(report.name))
        let first = try share.exportFile(), second = try share.exportFile()
        defer { try? FileManager.default.removeItem(at: first.deletingLastPathComponent()); try? FileManager.default.removeItem(at: second.deletingLastPathComponent()) }
        XCTAssertEqual(first.lastPathComponent,"gridfix_route_Training.pdf"); XCTAssertNotEqual(first,second)
        XCTAssertEqual(try Data(contentsOf: first),try Data(contentsOf: second))
        XCTAssertNotNil(PDFDocument(url: first))
    }
    func testMultiPageCompleteTableRepeatedHeadersTotalsAndUnicodeLongTitle() throws {
        let points = (0..<130).map { i in GeoPoint(lat: 24+Double(i)*0.001,lon: 54+Double(i%7)*0.001) }
        let report = try RouteCardOutput.report(request(points: points,name: "Patrol Café / phase line - "+String(repeating: "long route name ",count: 5)))
        let pdf = try document(report), all = try XCTUnwrap(pdf.string)
        XCTAssertGreaterThan(pdf.pageCount,2)
        for i in 0..<pdf.pageCount {
            let text = try XCTUnwrap(pdf.page(at: i)?.string)
            XCTAssertTrue(text.contains("TO GRID (8-DIGIT)")); XCTAssertTrue(text.contains("Page \(i+1) of \(pdf.pageCount)"))
        }
        XCTAssertTrue(all.contains("CAFÉ")); XCTAssertTrue(all.contains(report.rows.last!.destinationGrid))
        XCTAssertTrue(try XCTUnwrap(pdf.page(at: pdf.pageCount-1)?.string).contains("TOTAL"))
        XCTAssertEqual(all.components(separatedBy: "TOTAL").count-1,1)
        assertTextInsidePage(pdf)
    }
    func testMissingMagneticModelManualOverrideAndExpiredModelAreExplicit() throws {
        let input = request(points: [.init(lat: 1,lon: 179.99),.init(lat: 1,lon: -179.99)],north: .magnetic)
        let missing = try RouteCardOutput.report(input,model: nil)
        XCTAssertEqual(missing.rows[0].azimuth,"UNAVAILABLE")
        XCTAssertTrue(try XCTUnwrap(document(missing).string).contains("UNAVAILABLE"))
        let expired = try RouteCardOutput.report(input,date: Date(timeIntervalSince1970: 2082758400))
        XCTAssertTrue(expired.notes.contains { $0.contains("past its validity") })
        let settings = AppSettings(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        settings.northRef = .magnetic; settings.declinationOverride = 10
        let route = Backup.Graphic(id: "manual",name: "Override",type: "route",points: [.init(lat: 1,lon: 179.99),.init(lat: 1,lon: -179.99)])
        let manual = try RouteCardOutput.report(RouteCardRequest(route: route,settings: settings),model: nil)
        XCTAssertEqual(manual.rows[0].azimuth,"080°"); XCTAssertEqual(manual.rows[0].backAzimuth,"260°")
        XCTAssertTrue(manual.notes.contains { $0.contains("Manual declination") })
    }
    func testDenseAndCoincidentSketchesDoNotLoseTableRowsOrOverflow() throws {
        let points = (0..<80).map { i in GeoPoint(lat: 24+Double(i%4)*0.00001,lon: 54+Double(i%5)*0.00001) }
        let dense = try RouteCardOutput.report(request(points: points,name: "Dense route")), pdf = try document(dense)
        XCTAssertTrue(try XCTUnwrap(pdf.string).contains("Overview labels omitted")); assertTextInsidePage(pdf)
        let same = try RouteCardOutput.report(request(points: [.init(lat: 24,lon: 54),.init(lat: 24,lon: 54)],name: "Same point"))
        let coincident = try document(same)
        XCTAssertTrue(try XCTUnwrap(coincident.string).contains("SP / RP")); XCTAssertTrue(same.notes.contains { $0.contains("Zero-length") }); assertTextInsidePage(coincident)
    }
    func testSafeFilenameStaleRouteMatchAndCancelledRenderer() async throws {
        XCTAssertEqual(StripMapPDF.filename("../Patrol / west"),"gridfix_route____Patrol___west")
        let input = request(points: [.init(lat: 24,lon: 54),.init(lat: 24.01,lon: 54)])
        XCTAssertFalse(input.matches(nil))
        let report = try RouteCardOutput.report(input)
        let task = Task { try Task.checkCancellation(); return try StripMapPDF.render(report) }
        task.cancel(); do { _ = try await task.value; XCTFail("Cancelled PDF") } catch { XCTAssertTrue(error is CancellationError) }
    }
    func testExportReviewArtifactsFromActualAppRenderer() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("gridfix-pdf-review",isDirectory: true)
        try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: true)
        let routes: [(String,String,[GeoPoint])] = [
            ("route-strip-map","Patrol Alpha - sample route",(0..<70).map { i in .init(lat: 24.45+Double(i)*0.0002,lon: 54.37+Double(i%8)*0.00025) }),
            ("dateline-route","Dateline crossing",[.init(lat: 1,lon: 179.99),.init(lat: 1.01,lon: -179.99),.init(lat: 1.02,lon: 179.98)]),
            ("coincident-route","Coincident start and return",[.init(lat: 24,lon: 54),.init(lat: 24,lon: 54)])
        ]
        for (file,name,points) in routes {
            let report = try RouteCardOutput.report(request(points: points,name: name),date: .init(timeIntervalSince1970: 1700000000))
            try StripMapPDF.render(report).write(to: folder.appendingPathComponent(file+".pdf"))
        }
        NSLog("GridFix PDF review artifacts: %@",folder.path)
    }
    private func assertTextInsidePage(_ pdf: PDFDocument,file: StaticString = #filePath,line: UInt = #line) {
        for pageIndex in 0..<pdf.pageCount {
            guard let page = pdf.page(at: pageIndex) else { XCTFail("Missing page",file: file,line: line); continue }
            for index in 0..<page.numberOfCharacters {
                let box = page.characterBounds(at: index)
                if box.isEmpty || box.isNull || !box.minX.isFinite || !box.minY.isFinite { continue }
                XCTAssertGreaterThanOrEqual(box.minX,38,file: file,line: line); XCTAssertLessThanOrEqual(box.maxX,557,file: file,line: line)
                XCTAssertGreaterThanOrEqual(box.minY,12,file: file,line: line); XCTAssertLessThanOrEqual(box.maxY,805,file: file,line: line)
            }
        }
    }
}
