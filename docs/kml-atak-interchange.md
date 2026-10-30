# KML, KMZ and ATAK mission packages

Reference: Android `release/1.1.0`, currently still `482b417` (remote branch
rechecked during this milestone). Behavior comes from `InterchangeFiles.kt`,
`DataPackage.kt`, `ImportArchive.kt`, `ImportCoordinator.kt`, the graphic export
geometry and the actual `GridFixApp.kt` export call sites.

## Native workflows

Waypoints → actions → **Import field file** accepts GPX, KML, KMZ, CSV, GeoJSON,
ATAK ZIP and DPK. **Paste text** includes KML; binary archives are file imports.
The Export submenu adds KML, KMZ and ATAK package alongside existing formats.
Standard KML/KMZ, DPK and ZIP document types are registered for Open In/Files.
Incoming files use the existing Review banner and preview-before-save flow.

KML and KMZ export all stored waypoints, graphics and finished tracks, including
hidden items and records outside the current search/folder filter. ATAK exports
all stored waypoints and only route graphics, matching Android. It deliberately
omits other graphics, finished tracks, active sessions and terrain. Use backup to
preserve the full library's symbols/settings; none of these are complete backups.

## Geometry and metadata

The KML reader scopes coordinates to their own geometry. Point, LineString,
Polygon and nested MultiGeometry are supported. Siblings cannot exchange their
positions/types. Foreign namespace geometry and coordinates hidden in unrelated
extensions cannot become field objects. Current and legacy Google Earth KML
namespaces are accepted. Raw XML bytes retain declared encodings, including
UTF-16, and CDATA labels/coordinates work for KML and GPX.

Nearest named Folder and Placemark names are retained. Points become waypoints,
lines become routes, and polygon outer rings become assembly areas. Closed lines
retain the return leg; only polygons drop their duplicated closing vertex.
Polygons with holes reject the whole KML/package instead of being filled. Altitude,
styles, icons, raster GroundOverlays, NetworkLinks and original tactical types
are not imported. No external resources or network links are fetched.

Range rings export as sampled closed lines, sectors as sampled area outlines,
and point graphics as placemarks with Android's type label prefixes. Graphic
exports are grouped under Graphics; tracks under Tracks. Tracks reimport as
routes if they have at least two valid points. A single-fix track remains a
LineString on export and is skipped on import, rather than inventing a waypoint.
KMZ export wraps this KML as `doc.kml`; KMZ import reads the first KML member in
local ZIP stream order and still validates/budgets later ignored entries.

ATAK ZIP/DPK reads CoT marker events and bundled GPX/KML/KMZ. CoT callsign falls
back to UID then ATAK point, with Android's 30 UTF-16-unit name limit. Affiliation
comes from the CoT type; imported markers use the target symbol and Imported
folder. Route/drawing/chat event types, bad/unlocated positions and the source's
(0,0) unknown-position case are skipped. CoT route events do not become routes;
route geometry arrives through bundled GPX/KML. CoT altitude, uncertainty, UID,
times, remarks and full unit classifications are not retained as waypoint metadata.

Export emits one `.cot` per waypoint, GPX routes and
`MANIFEST/manifest.xml` version 2. Unit waypoints use coarse affiliation CoT types;
other markers use `b-m-p-w`. Exported `GRIDFIX-<waypoint-id>` UIDs remain stable
when list order changes, so ATAK can recognise a resent marker. This is file
interoperability, not a TAK server connection or live position stream. Actual ATAK
client/device ingestion remains a physical interoperability check.

## Bounds, staging and retry

One shared decompression budget follows a package and its nested KMZ members:
32 MiB per member, 128 MiB total expanded bytes and 2,048 entries. Ignored files
and directories consume the same budget. ZIP sizes, headers, stream order and
CRCs are validated; supported malformed GPX/KML members reject the whole package.
Malformed/unsupported CoT events are skipped, matching Android's CoT path.

Members are decoded one at a time. Native file reads remain security scoped and
coordinated through parsing, mapping the container when the filesystem permits.
The additional compressed-container input cap is 512 MiB. STORE and DEFLATE,
including Java streaming data descriptors, work. ZIP64, encrypted and multi-volume
archives remain unsupported by this reader; ZIP64 is an implementation gap,
not an asserted iOS restriction. Package names are never extraction paths: no
archive member is written to disk by its name. Backup's original stricter path,
duplicate-name and smaller archive limits remain unchanged.

A shared parsing budget now follows every package member, including GPX segments,
so splitting excessive records/vertices across files cannot bypass the bounds.
The old GPX aggregate-across-kinds cap is replaced with per-kind record and
shape/track point budgets matching the import plan. All members form one raw
content namespace before IDs are assigned. Original historical track timestamps
participate in identity before persistence normalises them. Stable unchanged-file
retry and the ordered track → waypoint/folder → graphic commits retain their
existing behavior and partial-save reporting. Changed/reordered parsed content
is a new import, as on Android.

GridFix backup ZIPs opened through field import show an explicit **Import backup**
message instead of being silently treated as an empty mission package. Their
settings/course restore still uses the separate backup action. A package with
more than 2,048 members exceeds the import limit even if another application can
produce it; this limit also exists on Android.

## Verification and remaining checks

Core tests cover scoped/closed/nested geometry, holes, names/folders, foreign
extensions, Unicode encodings/CDATA, export ring/sector geometry, CoT filtering,
manifest/type/UID behavior, shared record/point budgets, ignored-member CRCs and
nested decompression limits. `scripts/GenerateAndroidMissionFixture.java` creates
Java ZipOutputStream fixtures with streaming descriptors, nested KMZ and a
reordered central directory; local stream order and IDs must stay unchanged.

App integration exercises the Java mission fixture through coordinated native
file preview, partial-save retry, favourite/visibility/selection preservation and
reopened stores, plus the document associations. Simulator UI workflows cover
KML preview/import, route/area map display and persistence, hole rejection with no
partial save, readable night mode, and native ATAK/KMZ export/reimport previews.

Physical provider/Open In and ATAK client checks, ZIP64 support, large-container
memory/storage-pressure validation, PDF/strip-map outputs and the remaining field
tools are still open. See the main parity inventory for the complete goal scope.
