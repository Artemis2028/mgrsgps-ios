# GPX, CSV and GeoJSON interchange

Compared directly with Android `release/1.1.0` commit `482b417`: `TabularFormats.kt`,
`InterchangeFiles.kt`, `GraphicExportGeometry.kt`, `ImportCoordinator.kt`, and the
track sentinel/normalisation in `TrackRepository.kt` and `ImportedTracks.kt`.

## Using it

Waypoints → actions → **Import field file** opens Files. **Paste text**
has a format submenu. Parsing runs off the main thread and does not save anything.
Preview shows waypoint, graphic/route and track counts; Import is enabled only
when supported records exist. Cancel or editing the text invalidates a pending
preview, including a parse that finishes after the sheet closes. Invalid and
unsupported CSV/GeoJSON entries/coordinates are counted; the count can include
polygon holes, individual vertices and whole unsupported shapes, not just records.
GPX retains its existing valid-coordinate filtering and does not report a skip count.

Files opened through the iOS document association are held behind a **Review**
banner, so receiving a file does not interrupt an existing field sheet or mutate
the library. The user opens its preview and explicitly imports. GPX, `.csv`, `.geojson`, KML/KMZ and ATAK ZIP/DPK document associations are registered; arbitrary `.json` can also be
chosen in the importer. Only one incoming file is pending at a time. Review it
while its originating provider remains available; pending URLs are not a durable
import queue across relaunch.

The native file reader balances security-scoped access, coordinates with the
provider, and enforces format byte limits before parsing. Coordinated previews
map local files when the filesystem permits and finish parsing before scoped
access is released.
GPX is limited to 32 MiB; CSV/GeoJSON to 16 MiB. Parsing and staged-content limits
follow the Android 10,000-record/250,000-point bounds. GPX now uses a shared
per-kind budget across package members, replacing its former aggregate-across-kinds
cap. File-provider access and native Share/Open In delivery still require physical-device/provider checks.

## Format behavior

- CSV imports waypoints using header aliases or headerless name/lat/lon or
  name/grid columns, with comma, semicolon or tab delimiters. Quoted multiline
  fields and doubled quotes are supported. Latitude/longitude takes priority,
  with MGRS fallback. Labelled MGRS/USNG, hyphens and Unicode decimal digits work
  throughout coordinate entry too. Supported metadata includes folder, colour,
  MilGPS symbol code, elevation and time. CSV export includes every stored
  waypoint, including hidden/favourite points. It matches Android's leading
  `=`, `+`, `@` apostrophe protection; it is not a lossless waypoint backup.
- GeoJSON imports Points/MultiPoints as waypoints, LineStrings/MultiLineStrings
  as routes, and outer Polygon/MultiPolygon rings as assembly-area graphics.
  Geometry collections are supported with bounded nesting. Coordinates are
  longitude, latitude. Holes and original tactical types are not retained.
  Export includes all stored waypoints, graphics and finished tracks regardless
  of the current search/folder/visibility filter. Range rings are sampled
  LineStrings; sectors are sampled polygons. Exported track LineStrings become
  routes when reimported, matching Android. GeoJSON is geographic interchange,
  not a GridFix backup.
- GPX retains waypoints, routes and separate continuous track segments with
  altitude/time and MilGPS metadata. Unknown or negative track times normalise
  to zero when persisted. Imported tracks use Base, matching the Android import
  coordinator. A GridFix ZIP backup preserves library symbols and settings.

## Retry and persistence

All three text formats now use Android's `gridfix-import-v1` SHA-256 semantic
fingerprint and Java name-UUID kind/ordinal IDs. The contract includes original
folder spelling and raw historical track timestamps; local destination spelling
and import time do not change identity. Identical entries within one file remain
distinct. Retrying unchanged parsed content retains user edits, favourites,
visibility and selection; missing records can be restored. Changed or reordered
parsed content creates a different import, as on Android.

Older iOS GPX imports used random IDs. They cannot be retroactively identified,
so reimporting a file first imported by an older build can add another copy.

Save order is tracks, waypoints/folders, then graphics. Each store commits
atomically, but there is no cross-store transaction. A failure reports sections
confirmed saved and leaves the preview open for retry. No rollback deletes field
data or user edits. Import never applies device settings or changes navigation
selection. ZIP backup restore keeps its separate existing contract.

## Verification

Core tests cover delimiter/header/grid parsing, quoted exports, metadata,
geometry semantics, bounds, content detection, stable duplicate ordinals and
clock/folder independence. `scripts/GridFixImportFixture.java` independently
reproduces the JVM hash/UUID fixture (`java scripts/GridFixImportFixture.java`,
Java 17+) used by the Swift tests.

App integration checks cover bounded coordinated reads, document registrations,
partial phase failure/retry, existing edited/favourite/hidden records and reopened
stores. Simulator UI checks exercise preview/cancel/confirm/retry, malformed
input, red night mode, GPX route/track persistence and map overlays, plus native
GeoJSON Files export and reimport preview. Automatic route pause/resume/background
completion also passes through the new GPX entry flow. Its host GPS feed reads
the isolated Debug session state to hold checkpoint progression until pause/resume,
so UI/import timing cannot race the route; it never injects app location state.
See test results for the current run.

KML/KMZ and ATAK are now implemented in the same preview flow; see
[KML and mission-package behavior](kml-atak-interchange.md). PDF/strip-map output,
ZIP64, full provider/device validation and large-library/storage-pressure work remain open.
