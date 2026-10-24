# Remaining parity with Android release/1.1.0

Reference: `Artemis2028/gridfix` branch `release/1.1.0`, commit `482b417`,
24 October 2026. This inventory supplements the earlier 1.0.4 milestone notes.
It is not a claim of full Android parity.

| Area | Implemented on iOS | Still missing or incomplete |
| --- | --- | --- |
| Coordinates/position | Validated MGRS/UTM/decimal entry, units, north reference, WMM, precision/accuracy gates | USNG naming option, projection/resection/intersection UI, callouts/QR and orientation refinements |
| Military symbols | Generic markers, MilGPS colours/shapes/characters, preserved affiliation/echelon/designation metadata | Full MIL-STD/NATO unit and tactical symbol catalog, symbol/echelon editor and matching map rendering |
| Tactical graphics | Basic imported geometry overlays and record/folder visibility | Full graphic controls, creation/editor, control measures and doctrine-specific rendering |
| Routes | Ordered waypoint-based route editor, route cards, generated waypoint ownership, GPX and automatic following | Drawing/editing routes directly on the map, richer route-management actions |
| Navigation | Target metrics, relative steering readout, Android guide settings/policy, arrival cues, ordered checkpoint advance, pause/resume, background route GPS/milestone notifications | Physical direction-pattern validation; continuous Android-style locked-screen steering haptics cannot be promised on iOS |
| Boundaries | Editable perimeter/kinks, quiet inside, confirmed exit/reentry handling, background location and notification requests | Physical locked-screen alert validation, boundary interchange/backup contract |
| Maps/offline | Android raster catalog/key gating, USGS area download/resume, raster MBTiles, grid/shading, elevation caching/downloads and contours | Ruler and remaining map drawing/control tools; physical offline/storage-pressure validation |
| Terrain visibility | Elevation tiles and contours only | Elevation/slope readout UI, point-to-point line-of-sight/profile calculations, viewshed calculation and overlays. Waypoint visibility filtering is not terrain visibility. |
| Waypoint library | Coordinates, folders, visibility, navigation, local persistence | Favorites, search/sort and batch tools from 1.1.0, full symbol editing and field geometry workflows |
| Tracks/practice | Background recording/recovery, saved tracks/overlays, GPX, restored practice history | Track rename/move, larger-library storage, creating/running practice courses and scoring/results UI |
| Interchange/sharing | GPX waypoints/routes/tracks, Android streaming ZIP backup contract, guide preferences in backup | CSV/GeoJSON and broader file-opening flows from 1.1.0, KML/KMZ/ATAK, PDFs/strip-map outputs; active sessions/offline maps/boundaries are separate from v1 backup |
| Field tools | Shared geodesy and supporting math | Remaining field-tool screens and workflows |
| Release | Unsigned simulator/device builds, automated tests and draft PR | App icon, privacy/distribution metadata, StoreKit/purchases, signing, physical field validation, TestFlight/App Store release |

The recording-sheet contrast regression came from the map's light colour scheme
leaking into dark field forms. Field-sheet presentation now explicitly selects
dark controls and rows to match the light text, including recording, coordinates,
map layers, boundaries and GPX import. This fix does not close the military-symbol,
graphics, route-drawing or visibility gaps above.

See [navigation behavior and limitations](navigation-guide.md),
[boundary monitoring](backstops-handrails.md), and [offline maps](offline-maps.md).
Core Location does not expose Android's GNSS satellite/status details. iOS also
controls background execution and notification/haptic delivery; platform limits
must remain visible rather than represented as complete feature parity.
