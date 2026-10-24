# Remaining parity with Android release/1.1.0

Reference: `Artemis2028/gridfix` branch `release/1.1.0`, commit `482b417`,
24 October 2026. This inventory supplements the earlier 1.0.4 milestone notes.
It is not a claim of full Android parity.

| Area | Implemented on iOS | Still missing or incomplete |
| --- | --- | --- |
| Coordinates/position | Validated MGRS/decimal entry and UTM readouts, units, north reference, WMM, precision/accuracy gates | USNG naming option, projection/resection/intersection UI, callouts/QR and orientation refinements |
| Military symbols | Full Android curated catalog: 496 unit images, 20 tasks, 15 basic markers; search, affiliation/echelon/designation/type/rotation editing, imported MilGPS appearance editor, shared map/library rendering and night transform | Physical map readability at field distances; the catalog matches Android rather than the entire MIL-STD specification |
| Tactical graphics | All 30 Android control measures, doctrine rendering, map drawing, draggable points and segment handles, metadata, show/visibility/delete, day/night labels | Physical field readability and very large-library performance |
| Routes | Waypoint-based and map-based route editors, waypoint snapping, draggable bends, numbered legs, route cards, generated waypoint ownership, GPX and automatic following | Remaining bulk library/interchange actions tracked below |
| Navigation | Target metrics, relative steering readout, Android guide settings/policy, arrival cues, ordered checkpoint advance, pause/resume, background route GPS/milestone notifications | Physical direction-pattern validation; continuous Android-style locked-screen steering haptics cannot be promised on iOS |
| Boundaries | Editable perimeter and draggable bends, quiet inside, confirmed exit/reentry handling, background location and notification requests | Physical locked-screen alert validation, boundary interchange/backup contract |
| Maps/offline | Android raster catalog/key gating, USGS area download/resume, raster MBTiles, grid/shading, elevation caching/downloads and contours | Ruler/area measure; physical offline/storage-pressure validation |
| Terrain visibility | Elevation/slope readouts, Android LOS/curvature and uncertainty policy, route profiles/charts, 1/2/4 km day/night viewsheds, offline DEM sampling and cancellation | Physical terrain comparison, outdoor legibility and battery validation; vegetation/structures are outside the terrain model |
| Waypoint library | Coordinates, folders, visibility, navigation, local persistence | Favorites, search/sort and batch tools from 1.1.0, field geometry workflows |
| Tracks/practice | Background recording/recovery, saved tracks/overlays, GPX, restored practice history | Track rename/move, larger-library storage, creating/running practice courses and scoring/results UI |
| Interchange/sharing | GPX waypoints/routes/tracks, Android streaming ZIP backup contract, guide preferences in backup | CSV/GeoJSON and broader file-opening flows from 1.1.0, KML/KMZ/ATAK, PDFs/strip-map outputs; active sessions/offline maps/boundaries are separate from v1 backup |
| Field tools | Shared geodesy and supporting math | Remaining field-tool screens and workflows |
| Release | Unsigned simulator/device builds, automated tests and draft PR | App icon, privacy/distribution metadata, StoreKit/purchases, signing, physical field validation, TestFlight/App Store release |

The recording-sheet contrast regression came from the map's light colour scheme
leaking into dark field forms. Field-sheet presentation now explicitly selects
dark controls and rows to match the light text, including recording, coordinates,
map layers, boundaries and GPX import. Military symbols now have their own
validated port, followed by tactical graphics and route drawing. Terrain visibility tools are now ported too; the remaining gaps are recorded above.

See [terrain visibility and profiles](terrain-visibility.md),
[map graphics and route drawing](tactical-graphics.md),
[military symbol catalog and provenance](military-symbols.md),
[navigation behavior and limitations](navigation-guide.md),
[boundary monitoring](backstops-handrails.md), and [offline maps](offline-maps.md).
Core Location does not expose Android's GNSS satellite/status details. iOS also
controls background execution and notification/haptic delivery; platform limits
must remain visible rather than represented as complete feature parity.
