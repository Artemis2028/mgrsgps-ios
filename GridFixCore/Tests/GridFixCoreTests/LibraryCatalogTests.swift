import XCTest
@testable import GridFixCore

final class LibraryCatalogTests: XCTestCase {
    func testIndexedListingMatchesAndroidPolicyAcrossQueriesFoldersAndOrders() throws {
        let names = ["Zulu","alpha","ALPHA","İ","i","ı","ß","SS","Σ","ς","σ","𐐀","𐐨"]
        var points: [Waypoint] = []
        for (i,name) in names.enumerated() {
            let lon = -79.5+Double(i)*0.0001
            let folder = i%2 == 0 ? "Base" : "Lane"
            points.append(Waypoint(id: String(i),name: name,lat: 35.5,lon: lon,createdAt: Int64(i),folder: folder,favorite: i%3 == 0))
        }
        points[0].designation = "1 PLT"
        let grid = MGRS.string(lat: points[3].lat,lon: points[3].lon,digits: 10)!
        let index = try LibraryListing.Index(points)
        for query in [""," alpha ","lane","1 plt",grid,grid.replacingOccurrences(of: " ",with: ""),"17","absent","σ"] {
            for folder: String? in [nil,"BASE","Lane","Missing"] {
                for sort in WaypointSort.allCases {
                    for origin: GeoPoint? in [nil,.init(lat: 35.5,lon: -79.5)] {
                        XCTAssertEqual(try index.listed(folder: folder,origin: origin,query: query,sort: sort),LibraryListing.waypoints(points,folder: folder,origin: origin,query: query,sort: sort),"\(query) \(folder ?? "all") \(sort)")
                    }
                }
            }
        }
    }

    func testReusedIndexInstallsEditsAndReorderedStableTies() throws {
        let a = Waypoint(id: "a",name: "Same",lat: 35.5,lon: -79.5)
        let b = Waypoint(id: "b",name: "SAME",lat: 35.5,lon: -79.5)
        let index = try LibraryListing.Index([a,b])
        let reordered = try LibraryListing.Index([b,a],reusing: index)
        XCTAssertEqual(try reordered.listed(folder: nil,origin: nil,query: "",sort: .name).map(\.id),["b","a"])
        var edit = a; edit.name = "Changed"; edit.folder = "New"; edit.designation = "HQ"; edit.favorite = true; edit.visible = false; edit.lat = 24; edit.lon = 54
        let changed = try LibraryListing.Index([b,edit],reusing: index)
        for query in ["changed","new","hq",MGRS.string(lat: 24,lon: 54,digits: 10)!] {
            XCTAssertEqual(try changed.listed(folder: nil,origin: nil,query: query,sort: .name),[edit])
        }
        let oldGrid = MGRS.string(lat: a.lat,lon: a.lon,digits: 10)!
        XCTAssertEqual(try changed.listed(folder: nil,origin: nil,query: oldGrid,sort: .name),[b])
    }

    func testCanonicallyEquivalentRenameInvalidatesJavaNameKey() throws {
        var renamed = Waypoint(id: "a",name: "é",lat: 0,lon: 0)
        let other = Waypoint(id: "b",name: "Zulu",lat: 0,lon: 0)
        let original = try LibraryListing.Index([renamed,other])
        XCTAssertEqual(try original.listed(folder: nil,origin: nil,query: "",sort: .name).map(\.id),["b","a"])
        renamed.name = "e\u{301}"
        let changed = try LibraryListing.Index([renamed,other],reusing: original)
        XCTAssertEqual(try changed.listed(folder: nil,origin: nil,query: "",sort: .name).map(\.id),["a","b"])
    }

    func testCatalogFolderMergeMatchesPreviousUnicodePolicyAndKeepsVisibility() throws {
        let names = ["İ","i","ı","I","ß","SS","Σ","ς","σ","é","e\u{301}","ﬁ","fi","Base"]
        let stored = [FolderInfo(name: "BASE",visible: false)]
        let graphics = names.enumerated().map { Backup.Graphic(id: String($0.offset),name: "G",type: "route",points: [],folder: $0.element) }
        var expected = stored
        for name in names where !expected.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { expected.append(.init(name: name)) }
        expected.sort { a,b in
            if a.name == Folders.defaultFolder { return b.name != Folders.defaultFolder }
            if b.name == Folders.defaultFolder { return false }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        let catalog = try LibraryListing.Catalog(index: .init([]),folders: stored,graphics: graphics,tracks: [])
        let result = try catalog.snapshot(folder: nil,origin: nil,query: "",sort: .name)
        XCTAssertEqual(result.folders,expected)
        XCTAssertEqual(result.routeCount,names.count)
        XCTAssertEqual(result.allIDs.graphics,Set(graphics.map(\.id)))
        XCTAssertEqual(result.selection.graphics,result.allIDs.graphics)
        let filtered = try catalog.snapshot(folder: "missing",origin: nil,query: "",sort: .name)
        XCTAssertEqual(filtered.selection.count,0)
        XCTAssertEqual(filtered.allIDs,result.allIDs)
    }
}
