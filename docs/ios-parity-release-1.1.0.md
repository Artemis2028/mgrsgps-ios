# Remaining parity with Android release/1.1.0

Reference: `Artemis2028/gridfix` branch `release/1.1.0`, commit `482b417`,
24 October 2026. This inventory supplements the earlier 1.0.4 milestone notes.
It is not a claim of full Android parity.

| Area | Implemented on iOS | Still missing or incomplete |
| --- | --- | --- |
| Coordinates/position | Validated MGRS/decimal entry and UTM readouts, units, north reference, WMM, precision/accuracy gates, spherical waypoint projection with saved/current/entered bases, readable phonetic callout, native position/waypoint QR, persisted USNG naming and labelled entry, native Auto/Portrait/Landscape/Flipped controls, compact landscape Position layout, Android age/accuracy/trust labels, screen-relative fresh compass and selected-target visual steering | GPS course fallback and Position speed readout; physical receiving-camera QR, compass and worn-device checks |
| Military symbols | Full Android curated catalog: 496 unit images, 20 tasks, 15 basic markers; search, affiliation/echelon/designation/type/rotation editing, imported MilGPS appearance editor, shared map/library rendering and night transform | Physical map readability at field distances; the catalog matches Android rather than the entire MIL-STD specification |
| Tactical graphics | All 30 Android control measures, doctrine rendering, map drawing, draggable points and segment handles, metadata, show/visibility/delete, day/night labels | Physical field readability and very large-library performance |
| Routes | Waypoint-based and map-based route editors, waypoint snapping, draggable bends, numbered legs, route cards, generated waypoint ownership, GPX, automatic following and mixed library batches | Broader interchange/output actions tracked below |
| Navigation | Target metrics, relative steering readout, Android guide settings/policy, arrival cues, ordered checkpoint advance, pause/resume, background route GPS/milestone notifications | Physical direction-pattern validation; continuous Android-style locked-screen steering haptics cannot be promised on iOS |
| Boundaries | Editable perimeter and draggable bends, quiet inside, confirmed exit/reentry handling, background location and notification requests | Physical locked-screen alert validation, boundary interchange/backup contract |
| Maps/offline | Android raster catalog/key gating, USGS area download/resume, raster MBTiles, grid/shading, elevation caching/downloads and contours; ruler/area measurement and save-as-area | Physical offline/storage-pressure validation; polar UTM measurements are labeled as extrapolated |
| Terrain visibility | Elevation/slope readouts, Android LOS/curvature and uncertainty policy, route profiles/charts, 1/2/4 km day/night viewsheds, offline DEM sampling and cancellation | Physical terrain comparison, outdoor legibility and battery validation; vegetation/structures are outside the terrain model |
| Waypoint library | Coordinates, cross-section search, persisted favourites, distance/name/newest sorting, mixed waypoint/graphic/track selection, visibility swaps, confirmed batch deletion, folder creation/rename/merge/remove, map focus and local persistence | Physical large-library validation; remaining storage/interchange limits below |
| Tracks/practice | Background recording/recovery, saved tracks/overlays, moving folders, temporary viewing, confirmed deletion, reverse backtrack routes with endpoint-preserving simplification, GPX, random/folder practice courses, checkpoint navigation lock, strict arrival scoring, persisted pause/recovery and split/results history | Larger-library storage and physical course/guide validation |
| Interchange/sharing | GPX/CSV/GeoJSON/KML/KMZ/ATAK import preview and native Files export, Android-compatible retry IDs and ordered additive persistence, document associations, route-card text/A4 PDF preview/Files sharing, Android streaming ZIP backup contract, guide preferences in backup | Physical provider/Open In and ATAK client validation, ZIP64, large-container validation, physical PDF sharing/printing; active sessions/offline maps/boundaries are separate from v1 backup |
| Field tools | Resection/intersection worksheets, per-point north-reference conversion, safe ray solver and angle-of-cut warnings; waypoint projection; local/Zulu sun/moon planning with date controls; TN/GN/MN declination diagram; map-menu course/LOS entry points | Physical field/compass/model comparisons; astronomy retains Android's approximate model and 24-hour local-day moon-scan policy |
| Release | Unsigned simulator/device builds, automated tests and draft PR | App icon, privacy/distribution metadata, StoreKit/purchases, signing, physical field validation, TestFlight/App Store release |

The recording-sheet contrast regression came from the map's light colour scheme
leaking into dark field forms. Field-sheet presentation now explicitly selects
dark controls and rows to match the light text, including recording, coordinates,
map layers, boundaries and GPX import. Military symbols now have their own
validated port, followed by tactical graphics and route drawing. Terrain visibility tools are now ported too; the remaining gaps are recorded above.

See [position age and compass reference](position-fix-quality.md), [native screen orientation](screen-orientation.md), [position callouts, QR and USNG naming](position-sharing.md), [projection and field planning](field-planning.md), [resection and intersection](field-fixes.md), [route cards and strip-map PDFs](route-card-pdf.md), [KML/ATAK interchange](kml-atak-interchange.md), [text interchange](text-interchange.md), [practice courses](practice-courses.md), [field library workflows](field-library.md), [map measurements](map-measurement.md), [terrain visibility and profiles](terrain-visibility.md),
[map graphics and route drawing](tactical-graphics.md),
[military symbol catalog and provenance](military-symbols.md),
[navigation behavior and limitations](navigation-guide.md),
[boundary monitoring](backstops-handrails.md), and [offline maps](offline-maps.md).
Core Location does not expose Android's GNSS satellite/status details. iOS also
controls background execution and notification/haptic delivery; platform limits
must remain visible rather than represented as complete feature parity.

Separately requested watch companions are being developed alongside this port.
The native [watchOS companion](../Watch/README.md) has large grid and selected-waypoint
pages plus a full-screen interactive map, with foreground watch location and
latest-state visible-field overlay sync. The [shared watch contract](watch-companion-parity.md)
records the rendering, map-source and offline differences. Simulator pairing,
small-screen rendering and physical watch validation are tracked in its own
verification notes; these are not claims that main-app parity is complete.
