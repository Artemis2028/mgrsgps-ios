# iOS parity with GridFix 1.0.4

Baseline: `Artemis2028/gridfix` main `94c4cc4` (Android version 1.0.4,
version code 65), inspected 24 October 2026. The older 0.9.32 checklist describes
the original port; this is the current implementation roadmap. It does not
claim that all Android features are present on iOS.

## First milestone: coordinate entry, waypoint overlays, native glass

Implemented:

- Create and edit a waypoint by full MGRS (4/6/8/10 numeric digits) or WGS84
  decimal latitude/longitude. Validation blocks empty, unbalanced, non-finite,
  and out-of-range entries; explicit 0°, 0° remains a valid coordinate.
- Typed grids resolve to cell centres. Editing a name/folder or switching the
  display format preserves the original exact coordinate. Edited waypoints
  retain ID, creation date, visibility, and interchange metadata.
- Add at a recent precise fix or at the map centre. The editor captures the
  supplied coordinate rather than looking it up again at Save time.
- Map markers and persistent name labels follow waypoint and folder visibility.
  A selected navigation target does not override a hidden folder.
- MilGPS marker colours, shapes, and characters are rendered independently of
  tactical affiliation. Unsupported symbols use the generic pin; the full NATO
  and tactical symbol catalog remains a separate task.
- Tap a marker for its coordinate and a Navigate action. Locate and fit-to-visible
  waypoints are explicit camera actions; ordinary position/store updates do not
  continuously recenter the map.
- Folder chips, folder/waypoint visibility controls, waypoint cards with distance,
  and direct navigation actions. Current precision/units apply to the list.
- System TabView navigation and native glass buttons on iOS 26+. Custom floating
  readouts use regular glass; iOS 16–25 use system material/bordered controls.
  Content cards remain solid/readable. Native controls handle interaction motion.
- Night mode retains opaque red-on-black navigation and controls. Custom glass
  surfaces also become opaque with Reduce Transparency. The reference image is
  visual direction, not a specification; compass artwork was not redesigned.
- An authorised precise-location fix no older than 10 seconds with accuracy at
  most 25 metres is required for Add at fix,
  Locate, and navigation calculations. Freshness uses uptime after receipt, and
  the entire accuracy circle must fit inside the 50 m arrival ring. These rules
  match Android 1.0.4. Manual coordinate entry works without GPS.

## Routes, saved tracks, and Android interchange

Implemented:

- Create and edit routes from ordered waypoints. Route cards show per-leg
  distance, forward azimuth, back azimuth, destination grid, and paces using the
  selected units/north reference. Reverse bearings are solved at the destination,
  including its magnetic/grid correction. Share the card as text.
- Generate route waypoints using Android's route ID / vertex index ownership.
  Repeating generation preserves IDs and the selected target. Unrelated
  same-name waypoints are never taken over. Navigate to a chosen route vertex.
- Import/export GPX routes and saved tracks as well as waypoints. Each track
  segment remains separate so gaps never become invented connecting legs.
  MilGPS metadata uses the current namespace; old iOS exports remain readable.
- A Routes & Tracks library with route editing, saved track statistics, map
  visibility, deletion, individual track GPX export, and restored practice history.
- Routes, saved tracks, and basic imported graphic geometry draw on the map,
  follow record/folder visibility, and participate in Show all visible data.
  Route/track dateline crossings are split rather than drawn across the world.
- Complete backup snapshots and additive restore of settings, graphics/routes,
  track logs, course history, waypoints, and folders. Track statistics are
  recalculated from logs. Existing records win; duplicate course results are
  merged and the latest 30 retained. GPX imports preserve current settings.
- Android streaming ZIP/data descriptors are supported. Archives are checked
  before writes, with CRC, record, and decompressed-size limits. Failed writes
  retain saved data and report which sections were restored so retry is safe.
- Keep screen on and pace-count settings, included in backup/restore.
- Fresh installs use Android's ten-digit grid precision and Lensatic face;
  existing saved preferences are retained.

## Live recording

Track recording now uses Android's accuracy/movement/time thresholds, a durable
append log, a bounded live map trace, stop/save/discard controls, and recovery of
interrupted recordings. A dedicated background location manager and lock-compatible
file protection support recording after the screen locks, using foreground-started
When In Use permission. See [recording behaviour and validation](track-recording.md)
for the exact contract and physical-device verification still required.

## Remaining feature groups

| Area | Current iOS state | Remaining work |
| --- | --- | --- |
| Position and compass | MGRS/UTM/lat-lon, accuracy, declination, three instrument faces | Orientation/landscape refinement, callouts/QR |
| Waypoints | Coordinates, folders, visibility, basic navigation, local persistence | Projection/resection/intersection workflows, symbol editor/catalog, search/sort, batch operations |
| Maps | Demo basemap, MGRS grid, waypoint/route/track overlays, camera controls, map-centre add | Production basemap catalog, offline region download, MBTiles/user maps, ruler, full tactical graphic editor/overlays |
| Navigation | Target selection, bearings, back azimuth, distance, ETA | Relative-heading guidance, haptic guide and arrival state, background behaviour, automatic route following |
| Tracks and courses | Routes/editor/cards/owned waypoints, saved-track persistence/overlays/export, live recording/background configuration/recovery, restored course history | Physical locked-screen validation, track rename/move, practice course creation/running |
| Terrain | No terrain UI/cache | DEM caching/downloads, elevation, slope/hillshade, contours, LOS, viewshed |
| Interchange and backup | GPX waypoints/routes/tracks, full backup/restore, Android streaming ZIP contract fixture | KML/KMZ/ATAK, backup captured from a physical Android device |
| Field tools | Sun/moon, geodesy and some geometry helpers in core | Field tools UI, pace count, strip-map PDFs and sharing |
| Distribution | Simulator builds and CI | StoreKit products/entitlements/paywall, app icon/privacy metadata, signing, device validation, TestFlight/App Store release |

## Verification

Local validation on 24 October 2026: 140 core tests, 12 app integration tests,
and all nine iPhone simulator UI workflows have passed (the foreground-transition
workflow was rerun after making its test wait for native hit testing). The unsigned iPhone Release
build also succeeds. GPX document registration is checked on iOS so exports
use `.gpx` filenames.

`cd GridFixCore && swift test` runs the golden field-math, WMM, interchange,
coordinate-entry, and map visibility tests. The new coordinate tests include
southern/western coordinates, poles in decimal entry, exact edit preservation,
format switching, and stored metadata/identity preservation.

Generate with `xcodegen generate`, then run the `MGRSGPS` scheme's UI tests.
`App/UITests/WaypointWorkflowTests.swift` exercises invalid/valid entry,
coordinate edits after relaunch, visible markers, map-to-navigation selection,
folder hide/show, adding at the map centre, night-mode sheet continuity, and a
landscape waypoint layout, route creation/regeneration, GPX route/track import,
map overlays, navigation to a route vertex, and saved-track persistence/visibility.
App integration tests restore the Android contract archive through the real
stores and settings, check fresh defaults, and retry a failed partial restore.
Test data uses a separate Debug
store and never clears normal application data. UI attachments include screenshots.

The contract fixture is synthetic, generated by
`scripts/GenerateAndroidBackupFixture.java` using Java
`ZipOutputStream` and the inspected Android 1.0.4 schema. It is not a backup
captured from an Android device. Core tests also verify failed writes, malformed
archives, course deduplication, route ownership, and dateline geometry.

Simulator validation does not verify physical compass performance, GPS behaviour
in the field, physical locked-screen recording, or device signing.

## Design references

Use native navigation and button behaviour first. Glass belongs above content,
not on every row; keep coordinate typography monospaced and actions comfortably
sized. Native glass must remain responsive to system accessibility preferences.

- [Apple: Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)
- [Apple: Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)
- The project chat “Review Apple Liquid Glass guidance” supplies the original
  design intent: hierarchy, selective tint, accessible transparency/motion,
  platform-specific layout, and readable content below floating controls.
