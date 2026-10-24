import XCTest
@testable import GridFixCore

final class MapOfflineTests: XCTestCase {
    private let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
    private func directory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }; return dir
    }
    private var layer: RasterLayer { MapCatalog.layers().first! }
    private var bounds: MapBounds { .init(south: 38.89, north: 38.90, west: -77.04, east: -77.03) }
    func testCatalogMatchesAndroidReleaseGatingAndProviderLimits() throws {
        let release = MapCatalog.layers()
        XCTAssertEqual(release.map(\.key), ["usgs","usgs_img"])
        XCTAssertTrue(release.allSatisfy(\.bulkDownload))
        let configured = MapCatalog.layers(esriKey: "example-key")
        XCTAssertEqual(configured.map(\.key), ["streets","topo","sat","usgs","usgs_img","hillshade"])
        XCTAssertEqual(configured.filter(\.bulkDownload).map(\.maxDownloadZoom), [15,16])
        XCTAssertEqual(configured.first?.tileSize, 512)
        XCTAssertEqual(configured.first?.url(for: .init(z: 3,x: 4,y: 5))?.path, "/arcgis/rest/services/static-basemap-tiles-service/v1/arcgis/streets/static/tile/3/5/4")
        XCTAssertEqual(MapCatalog.layers(development: true).first?.tileSize, 256)
        XCTAssertEqual(MapCatalog.layers(esriKey: "$(UNSET)").count, 2)
    }
    func testDownloadRangeClampsOverzoomAndRefusesDisallowedOrOversizedPlans() throws {
        let plan = try TileDownloadPlan(bounds: bounds, currentZoom: 21.5, layer: layer)
        XCTAssertEqual(plan.minZoom, 15); XCTAssertEqual(plan.maxZoom, 15)
        XCTAssertEqual(plan.estimatedBytes, Int64(plan.tiles.count * 32 * 1024))
        XCTAssertThrowsError(try TileDownloadPlan(bounds: bounds, currentZoom: 14, layer: MapCatalog.layers(development: true)[0]))
        XCTAssertThrowsError(try TileDownloadPlan(bounds: .init(south: -80,north: 80,west: -180,east: 180), currentZoom: 10, layer: layer))
        XCTAssertEqual(try TileDownloadPlan(bounds: bounds, currentZoom: 1e300, layer: layer).maxZoom, 15)
    }
    func testTileCoverageHandlesDatelinePolesAndWholeWorldWithoutDuplicates() throws {
        let cross = try TileDownloadPlan.coverage(.init(south: -1,north: 1,west: 179,east: -179), minZoom: 3,maxZoom: 3,limit: 20)
        XCTAssertEqual(Set(cross.map(\.x)), [0,7]); XCTAssertEqual(Set(cross).count, cross.count)
        let world = try TileDownloadPlan.coverage(.init(south: -90,north: 90,west: -180,east: 180), minZoom: 0,maxZoom: 0,limit: 1)
        XCTAssertEqual(world, [.init(z: 0,x: 0,y: 0)])
        XCTAssertEqual(try TileDownloadPlan.coverage(.init(south: -1,north: 1,west: 179,east: -179),minZoom: 0,maxZoom: 0,limit: 1),world)
        XCTAssertThrowsError(try TileDownloadPlan.coverage(.init(south: 2,north: 1,west: 0,east: 1), minZoom: 3,maxZoom: 3,limit: 100))
    }
    func testRasterArchiveTmsLookupMetadataAndMissingTiles() throws {
        let db = try MapTileArchive(url: directory().appendingPathComponent("test.mbtiles"), create: true)
        let tile = MapTile(z: 3,x: 2,y: 1)
        XCTAssertEqual(tile.tmsRow, 6)
        try db.setMetadata(["format":"png", "bounds":"-78,38,-76,40", "name":"Field map"])
        try db.put(png, tile: tile)
        XCTAssertEqual(try db.tile(tile), png)
        XCTAssertNil(try db.tile(.init(z: 3,x: 2,y: 6)))
        XCTAssertEqual(try db.inspect().bounds, .init(south: 38,north: 40,west: -78,east: -76))
        XCTAssertEqual(try db.inspect().name, "Field map")
    }
    func testVectorEmptyAndCorruptArchivesNeverPublishAnImport() throws {
        let dir = try directory(), library = try MapTileLibrary(directory: dir)
        let file = dir.appendingPathComponent("bad.mbtiles")
        try Data("not sqlite".utf8).write(to: file)
        XCTAssertThrowsError(try library.importFile(file)); XCTAssertTrue(library.maps.isEmpty)
        try FileManager.default.removeItem(at: file)
        let archive = try MapTileArchive(url: file, create: true)
        XCTAssertThrowsError(try library.importFile(file))
        try archive.put(png, tile: .init(z: 0,x: 0,y: 0)); try archive.setMetadata(["format":"pbf"])
        XCTAssertThrowsError(try library.importFile(file)); XCTAssertTrue(library.maps.isEmpty)
    }
    func testImportedMapsSurviveOriginalRemovalAndLibraryRelaunch() throws {
        let dir = try directory(), library = try MapTileLibrary(directory: dir), original = dir.appendingPathComponent("Training.mbtiles")
        let db = try MapTileArchive(url: original, create: true)
        try db.setMetadata(["format":"png"]); try db.put(png,tile: .init(z: 0,x: 0,y: 0))
        let map = try library.importFile(original)
        try FileManager.default.removeItem(at: original)
        let reloaded = try MapTileLibrary(directory: dir)
        XCTAssertEqual(reloaded.maps, [map])
        XCTAssertEqual(try reloaded.data(for: .init(z: 0,x: 0,y: 0), mapID: map.id), png)
        try reloaded.delete(map.id); XCTAssertTrue(reloaded.maps.isEmpty)
    }
    func testPausedDownloadTilesRemainReadableAndCanResumeAfterReadOnlyLookup() throws {
        let dir = try directory(), library = try MapTileLibrary(directory: dir)
        let plan = try TileDownloadPlan(bounds: bounds, currentZoom: 15, layer: layer)
        let map = try library.begin(plan, name: "Patrol area", layer: layer)
        try library.store(png,tile: plan.tiles[0],in: map.id)
        let reloaded = try MapTileLibrary(directory: dir)
        _ = try reloaded.data(for: plan.tiles[0],mapID: map.id)
        for tile in plan.tiles { try reloaded.store(png,tile: tile,in: map.id) }
        try reloaded.finish(map.id)
        XCTAssertTrue(reloaded.maps[0].complete)
        XCTAssertEqual(reloaded.pinnedTile(plan.tiles[0],layerKey: layer.key), png)
    }
    func testIndependentTmsFixturesAndNormalizedTilesViews() throws {
        for name in ["raster-tms", "raster-view"] {
            let file = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "mbtiles"))
            let db = try MapTileArchive(url: file)
            XCTAssertEqual(try db.tile(.init(z: 3,x: 2,y: 1)), png)
            XCTAssertNil(try db.tile(.init(z: 3,x: 2,y: 6)))
            XCTAssertEqual(try db.inspect().name,"Synthetic training map")
        }
    }
    func testFailedManifestWriteNeverPublishesAnImport() throws {
        let dir = try directory(), library = try MapTileLibrary(directory: dir)
        let file = try XCTUnwrap(Bundle.module.url(forResource: "raster-tms",withExtension: "mbtiles"))
        let blocked = dir.appendingPathComponent("OfflineMaps/library.json")
        try FileManager.default.createDirectory(at: blocked,withIntermediateDirectories: true)
        XCTAssertThrowsError(try library.importFile(file))
        XCTAssertTrue(library.maps.isEmpty)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(at: dir.appendingPathComponent("OfflineMaps"),includingPropertiesForKeys: nil).contains { $0.pathExtension == "mbtiles" })
    }
    func testUnknownDeleteIdCannotEscapeTheMapDirectory() throws {
        let dir = try directory(), library = try MapTileLibrary(directory: dir), outside = dir.appendingPathComponent("outside.mbtiles")
        try png.write(to: outside)
        XCTAssertThrowsError(try library.delete("../outside"))
        XCTAssertEqual(try Data(contentsOf: outside),png)
    }
    func testTerrainIntervalsDecodingAndSaddleGeometryMatchAndroid() throws {
        XCTAssertEqual(TerrainContours.elevation(red: 128,green: 1,blue: 128), 1.5)
        XCTAssertNil(TerrainContours.elevation(red: 0,green: 0,blue: 0))
        XCTAssertEqual(TerrainContours.interval(metersPerPoint: 4), 10)
        XCTAssertEqual(TerrainContours.interval(metersPerPoint: 10), 20)
        XCTAssertEqual(TerrainContours.interval(metersPerPoint: 20), 50)
        XCTAssertNil(TerrainContours.interval(metersPerPoint: 20.01))
        let levels = TerrainContours.build(elevations: [0,20,20,0],width: 2,interval: 10)
        XCTAssertEqual(levels.first(where: { $0.elevation == 10 })?.segments.count, 2)
        XCTAssertTrue(TerrainContours.build(elevations: [1,1,1,1],width: 2,interval: 10).isEmpty)
        XCTAssertTrue(TerrainContours.build(elevations: [.nan,1,2,3],width: 2,interval: 1).isEmpty)
    }
}
