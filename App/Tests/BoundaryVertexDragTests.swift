import CoreLocation
import GridFixCore
import XCTest
@testable import MGRSGPS

@MainActor
final class BoundaryVertexDragTests: XCTestCase {
    private func vertex(_ midpoint: Bool = false) -> BoundaryVertexAnnotation {
        .init(index: 1,point: .init(lat: 24.45,lon: 54.37),isMidpoint: midpoint)
    }
    func testPreviewIsSeparateFromOneFinalCommitAndCancellationCannotUndoCommit() {
        let annotation = vertex(); var commits: [CLLocationCoordinate2D] = []
        let drag = BoundaryVertexDrag(annotation: annotation) { commits.append($0) }
        drag.move(to: .init(latitude: 24.46,longitude: 54.38))
        XCTAssertEqual(annotation.coordinate.latitude,24.46); XCTAssertTrue(commits.isEmpty)
        drag.finish(at: .init(latitude: 24.47,longitude: 54.39))
        drag.finish(at: .init(latitude: 0,longitude: 0)); drag.cancel()
        XCTAssertEqual(commits.count,1); XCTAssertEqual(commits.first?.latitude,24.47)
        XCTAssertEqual(annotation.coordinate.longitude,54.39)
    }
    func testCancelledMidpointOrVertexRestoresItsSourceAndNeverAddsOrMovesDraftPoints() {
        for midpoint in [false,true] {
            let annotation = vertex(midpoint); var commits = 0
            let drag = BoundaryVertexDrag(annotation: annotation) { _ in commits += 1 }
            drag.move(to: .init(latitude: 25,longitude: 55)); drag.cancel()
            drag.move(to: .init(latitude: 0,longitude: 0)); drag.finish(at: .init(latitude: 0,longitude: 0))
            XCTAssertEqual(commits,0); XCTAssertEqual(annotation.coordinate.latitude,24.45); XCTAssertEqual(annotation.coordinate.longitude,54.37)
        }
    }
    func testTransactionDoesNotReadAReusedViewsNewAnnotationOrHandler() {
        let original = vertex(),replacement = BoundaryVertexAnnotation(index: 3,point: .init(lat: 30,lon: 40),owner: "graphic")
        var bound = original,oldCommits = 0,newCommits = 0
        var callback: (CLLocationCoordinate2D) -> Void = { _ in oldCommits += 1 }
        let drag = BoundaryVertexDrag(annotation: bound,commit: callback)
        bound = replacement; callback = { _ in newCommits += 1 }
        drag.finish(at: .init(latitude: 25,longitude: 55))
        XCTAssertEqual(oldCommits,1); XCTAssertEqual(newCommits,0)
        XCTAssertEqual(original.coordinate.latitude,25); XCTAssertEqual(bound.coordinate.latitude,30)
        withExtendedLifetime(callback) {}
    }
    func testMapLibreAnnotationTitleAndVoiceOverActivationRetainInsertionMeaning() {
        XCTAssertEqual(vertex(true).title,"Add point on boundary segment 2")
        XCTAssertEqual(vertex().title,"Boundary point 2")
        let view = BoundaryVertexView(reuseIdentifier: "test")
        var selected = 0; view.onSelect = { selected += 1 }
        XCTAssertFalse(view.isDraggable,"The custom long press owns dragging, not the SDK's reusable-view drag state")
        XCTAssertTrue(view.accessibilityActivate()); XCTAssertEqual(selected,1)
        view.prepareForReuse(); XCTAssertTrue(view.accessibilityActivate()); XCTAssertEqual(selected,1)
    }
    func testChangedDraftCancelsPreviewAndCannotCommitToItsReplacement() {
        let annotation = vertex(); var current = true,commits = 0
        let drag = BoundaryVertexDrag(annotation: annotation,current: { current }) { _ in commits += 1 }
        drag.move(to: .init(latitude:25,longitude:55)); current = false
        drag.finish(at: .init(latitude:26,longitude:56))
        XCTAssertFalse(drag.active); XCTAssertEqual(commits,0); XCTAssertEqual(annotation.coordinate.latitude,24.45)
    }
    func testLinePreviewUsesFreshCopyAndDoesNotAccumulateMidpointInsertions() {
        let source = [GeoPoint(lat:1,lon:2),GeoPoint(lat:3,lon:4)]
        var preview = BoundaryVertexPreview(source:source,index:0,midpoint:true,point:.init(lat:2,lon:3))
        XCTAssertEqual(preview.points,[source[0],GeoPoint(lat:2,lon:3),source[1]])
        preview.point = .init(lat:2.5,lon:3.5)
        XCTAssertEqual(preview.points,[source[0],GeoPoint(lat:2.5,lon:3.5),source[1]])
        XCTAssertEqual(preview.source,source); XCTAssertEqual(preview.points?.count,3)
    }
    func testVertexPreviewKeepsOtherPointsAndRefusesMissingIndices() {
        let source = [GeoPoint(lat:1,lon:2),GeoPoint(lat:3,lon:4)]
        let preview = BoundaryVertexPreview(source:source,index:1,midpoint:false,point:.init(lat:2,lon:3))
        XCTAssertEqual(preview.points,[source[0],GeoPoint(lat:2,lon:3)]); XCTAssertEqual(preview.source,source)
        XCTAssertNil(BoundaryVertexPreview(source:source,index:2,midpoint:false,point:source[0]).points)
        XCTAssertNil(BoundaryVertexPreview(source:source,index:-1,midpoint:true,point:source[0]).points)
    }

}
