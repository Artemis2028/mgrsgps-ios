import XCTest
import Combine
import GridFixCore
@testable import MGRSGPS

@MainActor
final class LibraryPresentationTests: XCTestCase {
    private func ready(_ model: LibraryPresentation) async throws {
        let end = Date().addingTimeInterval(5)
        while !model.isReady && Date() < end { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(model.isReady,model.error ?? "Library did not become ready")
    }

    func testLatestQueryWinsAndOldWorkerIndexCanBeReusedOffMain() async throws {
        let entered = expectation(description: "old query entered")
        let gate = DispatchSemaphore(value: 0)
        let cached = expectation(description: "new query reused catalog")
        let model = LibraryPresentation { request in
            XCTAssertFalse(Thread.isMainThread)
            if request.query == "old" {
                entered.fulfill()
                XCTAssertEqual(gate.wait(timeout: .now()+5),.success)
            }
            if request.query == "new" { XCTAssertNotNil(request.cachedCatalog); cached.fulfill() }
            return try LibraryPresentation.compute(request)
        }
        model.setWaypoints([.init(id: "a",name: "old",lat: 24,lon: 54),.init(id: "b",name: "new",lat: 24,lon: 54)])
        model.setQuery("old"); model.activate()
        await fulfillment(of: [entered],timeout: 3)
        var observed: [[String]] = []
        let subscription = model.$snapshot.compactMap { $0 }.sink { observed.append($0.waypoints.map(\.id)) }
        model.setQuery("new"); XCTAssertFalse(model.isReady)
        gate.signal()
        await fulfillment(of: [cached],timeout: 3)
        try await ready(model)
        XCTAssertEqual(observed,[["b"]]); XCTAssertEqual(model.snapshot?.selection.waypoints,["b"])
        subscription.cancel(); model.deactivate()
    }

    func testSourceEditCancelsOldResultAndClearsDeletedIDs() async throws {
        let model = LibraryPresentation()
        model.setWaypoints([.init(id: "a",name: "First",lat: 24,lon: 54)])
        model.activate(); try await ready(model)
        XCTAssertEqual(model.snapshot?.allIDs.waypoints,["a"])
        model.setWaypoints([])
        XCTAssertFalse(model.isReady)
        try await ready(model)
        XCTAssertEqual(model.snapshot?.allIDs.waypoints,[])
        XCTAssertEqual(model.snapshot?.selection.count,0)
        model.deactivate()
    }

    func testDeactivatedWorkerCannotOverwriteReactivatedRun() async throws {
        let entered = expectation(description: "first run entered")
        let gate = DispatchSemaphore(value: 0)
        let model = LibraryPresentation { request in
            if request.query == "old" {
                entered.fulfill(); XCTAssertEqual(gate.wait(timeout: .now()+5),.success)
            }
            return try LibraryPresentation.compute(request)
        }
        model.setWaypoints([.init(id: "a",name: "old",lat: 24,lon: 54),.init(id: "b",name: "new",lat: 24,lon: 54)])
        model.setQuery("old"); model.activate()
        await fulfillment(of: [entered],timeout: 3)
        model.deactivate(); model.setQuery("new"); model.activate()
        try await ready(model)
        gate.signal()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(model.isReady); XCTAssertEqual(model.snapshot?.waypoints.map(\.id),["b"])
        model.deactivate()
    }

    func testLateSourceResultCannotResurrectDeletedRecords() async throws {
        let entered = expectation(description: "old source prepared")
        let gate = DispatchSemaphore(value: 0)
        let model = LibraryPresentation { request in
            let result = try LibraryPresentation.compute(request)
            if request.points.contains(where: { $0.id == "deleted" }) {
                entered.fulfill(); XCTAssertEqual(gate.wait(timeout: .now()+5),.success)
            }
            // Simulate work that completed just before cancellation.
            return result
        }
        model.setWaypoints([.init(id: "deleted",name: "Old",lat: 24,lon: 54)])
        model.activate(); await fulfillment(of: [entered],timeout: 3)
        var observed: [[String]] = []
        let subscription = model.$snapshot.compactMap { $0 }.sink { observed.append(Array($0.allIDs.waypoints)) }
        model.setWaypoints([.init(id: "current",name: "New",lat: 25,lon: 55)])
        gate.signal(); try await ready(model)
        XCTAssertEqual(observed,[["current"]])
        XCTAssertEqual(model.snapshot?.waypoints.first?.name,"New")
        subscription.cancel(); model.deactivate()
    }

    func testGPSRefreshCoalescesAndNameOrderDoesNotRebuildOnLocation() async throws {
        let entered = expectation(description: "distance calculation entered")
        let latest = expectation(description: "latest origin calculated")
        let gate = DispatchSemaphore(value: 0)
        let model = LibraryPresentation { request in
            if request.origin?.lat == 25 {
                entered.fulfill(); XCTAssertEqual(gate.wait(timeout: .now()+5),.success)
            }
            if request.origin?.lat == 27 { latest.fulfill() }
            return try LibraryPresentation.compute(request)
        }
        model.setWaypoints([.init(id: "a",name: "Alpha",lat: 24,lon: 54)])
        model.setOrigin(.init(lat: 24,lon: 54)); model.activate(); try await ready(model)
        model.setOrigin(.init(lat: 25,lon: 54))
        await fulfillment(of: [entered],timeout: 3)
        XCTAssertTrue(model.isReady)
        model.setOrigin(.init(lat: 26,lon: 54)); model.setOrigin(.init(lat: 27,lon: 54))
        gate.signal(); await fulfillment(of: [latest],timeout: 3)
        model.setOrigin(nil); XCTAssertFalse(model.isReady); try await ready(model)
        model.setSort(.name); try await ready(model)
        let snapshot = model.snapshot?.waypoints
        model.setOrigin(.init(lat: 28,lon: 54))
        XCTAssertTrue(model.isReady); XCTAssertEqual(model.snapshot?.waypoints,snapshot)
        model.deactivate()
    }
}
