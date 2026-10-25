# Map layers and offline maps

The implementation follows GridFix Android 1.0.4 (`94c4cc4`), inspected on
24 October 2026. Android uses raster tiles, not downloadable vector maps.

## Android's three storage options

- **Browse cache:** recently viewed online tiles, up to roughly 600 MiB. HTTP
  cache headers still apply; viewing an area does not guarantee offline coverage.
- **Download an area:** USGS Topo and USGS Imagery only. These public-domain
  basemaps cover the United States. Android pins downloaded tiles in its shared
  cache; older downloads can eventually be evicted when that cache fills.
- **Import raster MBTiles:** an existing offline SQLite map file. Its coverage
  can be anywhere in the world. Vector PBF MBTiles are unsupported on Android
  and on this iOS port. GeoTIFF/photo-map models in Android are not currently
  wired into its map screen and are not implemented here.

## iOS behaviour

Open **Map → Layers**. Choose Streets, Topographic, Satellite, USGS Topo,
USGS Imagery, or Hillshade where enabled in the build. The MGRS grid, terrain
shading and contour switches, selected base map, offline-only setting, and camera
are saved across launches. Switching base maps preserves waypoints, routes,
saved tracks and the live recording trace. Day/night raster colouring follows
Android. Imported maps suppress the separate terrain-shading overlay.

For USGS, move to the desired area and choose **Download visible area for
offline**. Review the name, tile count, zoom range and estimated size, then
Download. The range starts at the displayed tile zoom (at least 3) and includes
up to four more zoom levels. USGS Topo stops at download zoom 15, Imagery at 16;
both can be viewed online through 16. MapLibre's 512-pixel camera zoom is
translated to the provider's 256-pixel tile zoom. Requests exceeding 12,000 tiles
are rejected before fetching anything. Saved parent tiles can be enlarged for
viewing at closer zooms; this adds no detail and never counts as downloaded
higher-resolution tiles.

Progress, Pause, Resume, Show map and Delete appear in the saved-map library.
A failed request stops the batch and retains completed tiles; Resume fills in
missing tiles in the same area. Downloads continue when switching tabs or
closing the Layers sheet while the app stays active. Leaving the app pauses area downloads. Keep the
app open to finish them, then resume manually when needed. This is separate from
live track recording, whose background location manager continues independently.
Downloads do not claim iOS background execution after the app is suspended.

**Import MBTiles file…** copies a raster PNG/JPEG/WebP archive into the app,
validates its schema and a sample tile before publishing it, and selects it.
The original file can then be moved or deleted. Standard TMS rows, optional XYZ
scheme metadata, and normalized `tiles` views are supported. Duplicate display
names receive a numeric suffix. A map only has the coverage and zoom levels
actually contained in its file. There is no online fallback for missing imported
tiles. Use Show map to return to its declared bounds.

**Offline only** stops map network requests and pauses active downloads.
The renderer uses imported files, saved USGS areas, saved elevation, and available
browse-cache tiles. A cache miss stays blank; no replacement geographic data is
invented. Grid and basic Latin label glyphs are bundled. Other Unicode glyph
ranges need to have been cached while online to render offline.

## Terrain overlays

The shading switch uses the same Esri hillshade source and darkness-to-opacity
transform as Android. It is an online/browse-cached overlay, not part of a USGS
area download. Hillshade can also be selected as the base layer when enabled.

Contour lines use the same AWS/Mapzen Terrarium elevation source at zoom 13,
valid height range, marching-squares saddle decisions, and 10/20/50 metre
interval thresholds as Android. Every fifth contour is major and labelled;
very large relief increases the interval to bound work. At most 72 elevation
tiles are considered per visible view. Zoom out too far and the UI requests a
closer view. Missing elevation stays unknown. **Download elevation for this
area** saves at most 400 zoom-13 tiles for offline contours, including over
imported maps. Elevation/LOS/viewshed field-tool screens remain future work.

## Storage and backup

USGS areas are app-owned MBTiles archives kept until explicitly deleted. Their
size reduces the remaining 600 MiB HTTP browse-cache budget. Unlike Android's
shared-cache eviction, iOS refuses additional named tiles when its area budget
is full; remove an area and Resume. Clear browse cache keeps all named areas
and imported maps. Imported MBTiles are separate from this budget and limited
by available device storage.

Elevation has a separate 300 MiB budget. Named elevation downloads are retained;
automatically fetched elevation uses the remaining space with oldest-use
eviction. Saved areas live in Documents/OfflineMaps and elevation cache tiles
in Documents/ElevationTiles. Map preferences are separate from field settings.
GridFix's version-1 complete backup/GPX exports do not include offline maps,
elevation tiles, or map preferences. Keep the original MBTiles files separately.

## Build configuration

Like Android, licensed global Esri layers require a map key in Release builds.
Without a key, Release exposes USGS and imported MBTiles. Debug additionally
uses Android's OpenStreetMap/OpenTopoMap/public Esri development fallbacks.
No global production key is embedded in source control.

Set the Xcode build setting `GRIDFIX_ESRI_API_KEY`, for example:

```sh
xcodebuild build -project MGRSGPS.xcodeproj -scheme MGRSGPS \
  -configuration Release GRIDFIX_ESRI_API_KEY="$ESRI_KEY"
```

For Xcode GUI builds, put the setting in a local, untracked `Maps.local.xcconfig` and apply
it as an Xcode configuration override. CI accepts the optional repository secret
`ESRI_KEY`, writes a temporary configuration without printing the value, and
applies it through `XCODE_XCCONFIG_FILE`. An absent key does not fail the build.
Do not commit keys or generated configuration files. Provider keys are shipped
in the app and should use the provider's supported usage restrictions.

## Verification

Core tests cover catalog gating, download limits, dateline/pole coverage, TMS
addressing, read-only normalized archives, malformed/vector rejection, atomic
import failures, and resumable area persistence. SQLite fixtures are generated
independently by `scripts/GenerateMapFixtures.py`.

App integration tests use a deterministic HTTP fixture to verify download →
relaunch → offline lookup with zero network calls, failure/retry, copied imports,
delete/persistence, bundled glyphs, Android colour transforms, saved-parent
viewing, and geographic contour orientation. A failed detailed download must
never publish an enlarged lower-resolution tile as new detail.

Simulator UI tests render an imported synthetic MBTiles map offline, persist
layer/grid settings across relaunch, preserve waypoint navigation across base
switches, and check USGS download availability/estimates. Screenshots are attached
to the test results. Online Topographic tiles were also rendered in a simulator.
The synthetic offline map is test data, not a real geographic basemap.

Before release, verify a real USGS area and an independently sourced raster
MBTiles archive on a physical iPhone in Airplane Mode, including relaunch,
panning across the saved boundary, contours, and storage pressure. No physical
iPhone was available for this pass. Global licensed Esri endpoints also need a
build with the deployment key; the local verification used Debug fallbacks.

## View-lifetime regression, 25 October 2026

Android `eacf084` uses repository-owned offline-region completion writes so leaving
Map cannot cancel the result. Its current source remains in `claude/tak` at
`6f9865f`. iOS already keeps `MapLayerStore` in the app's StateObject and owns the
unstructured download task there; no production ownership change was necessary.

Ten native map integration cases pass, including two new transport-gated checks:
caller cancellation leaves the store's download alive, then every planned tile
and the complete area survive reopening; offline reads make zero network calls.
Explicitly pausing a pending request leaves the area incomplete and resumable
under the same ID. Evidence: `/tmp/gridfix-offline-lifetime-native-20261025.xcresult`.

Two native UI cases pass normal Layers → estimate → Download → close Layers →
Position → complete → return to Layers → Offline only → terminate/relaunch → Ready,
in both day and night. A DEBUG-only transport holds synthetic tile replies until
the test releases them from another tab. It does not publish completion, write
tiles/area records or alter MapScreen's disappearance/cancellation behavior.
The production URLSession/raster validation/SQLite publication/reload paths do
that work. All non-fixture requests are refused; no provider/server is contacted.
The opt-in controls and protocol are compiled out of Release.

Evidence: `/tmp/gridfix-offline-lifetime-ui-scroll-20261025.xcresult`; four frames
per mode capture active/completed on Position, Ready on Map and Ready after
relaunch. The earlier combined bundle passes the three existing map-layer
workflows but fails the initial lifetime cases because their List rows needed
scrolling; it is not an overall passing bundle. Screenshot inspection also led
to a night-palette navigation title in Layers. The final two-case regression
also passes in `/tmp/gridfix-offline-lifetime-final-ui-20261025.xcresult`;
its exported day/night frames were inspected. Release phone/watch/widget build
passes in `/tmp/gridfix-offline-lifetime-final-release.log`.

Saved-area Rename, explicit fresh Update, detailed stored/expected tile counts
and size/date metadata remain Android parity gaps. See the
[concrete source follow-up](android-review-followups.md). These are separate from
physical Airplane Mode, provider and storage-pressure validation.
