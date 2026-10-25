# Remaining parity with Android release/1.1.0

Reference: `Artemis2028/gridfix` branch `release/1.1.0`, commit `482b417`,
24 October 2026. This inventory supplements the earlier 1.0.4 milestone notes.
It is not a claim of full Android parity.
The release branch was rechecked on 25 October and still points to this commit.
The user also requested the subsequent development work: see the
[25 October Android audit](android-overnight-2026-10-25.md) for navigation
lanes, protected backups, map-button preferences, fixes and the experimental
TAK branch. Those additions are tracked separately from this pinned release.
The first [navigation-lane UI and guidance integration](navigation-lanes.md)
now includes optional lane backup/restore and shared screen/text/PDF leg limits;
watch status remains an implementation gap; Android 4db6b21 startup/cue switches
are now implemented. It does not replace the separate quiet-inside perimeter.

| Area | Implemented on iOS | Still missing or incomplete |
| --- | --- | --- |
| Coordinates/position | Validated MGRS/decimal entry and UTM readouts, units, north reference, WMM, precision/accuracy gates, spherical waypoint projection with saved/current/entered bases, readable phonetic callout, native position/waypoint QR, persisted USNG naming and labelled entry, native Auto/Portrait/Landscape/Flipped controls, compact landscape Position layout, Android age/accuracy/trust labels, screen-relative fresh compass, Android GPS-course source/fallback rules, speed readouts and selected-target visual steering | Physical receiving-camera QR, compass and worn-device checks |
| Military symbols | Full Android curated catalog: 496 unit images, 20 tasks, 15 basic markers; search, affiliation/echelon/designation/type/rotation editing, imported MilGPS appearance editor, shared map/library rendering and night transform | Physical map readability at field distances; the catalog matches Android rather than the entire MIL-STD specification |
| Tactical graphics | All 30 Android control measures, doctrine rendering, map drawing, draggable points and segment handles, metadata, show/visibility/delete, day/night labels; worker-prepared archive edits | Physical field readability and very large-library performance |
| Routes | Waypoint-based and map-based route editors, waypoint snapping, draggable bends, numbered legs, route cards, generated waypoint ownership, GPX, automatic following and mixed library batches | Broader interchange/output actions tracked below |
| Navigation | Target metrics, relative steering readout, Android guide settings/policy, arrival cues, ordered checkpoint advance, pause/resume, background route GPS/milestone notifications; post-release checkpoint/route lanes with separate drawn/linked limits, library/map editing, early warnings and crossing-notification requests | Phone-to-watch lane status; physical direction-pattern/locked-screen crossing validation; continuous Android-style locked-screen steering haptics cannot be promised on iOS |
| Boundaries | Editable perimeter and draggable bends, quiet inside, confirmed exit/reentry handling, background location and notification requests | Physical locked-screen alert validation, boundary interchange/backup contract |
| Maps/offline | Android raster catalog/key gating, USGS area download/resume, raster MBTiles, grid/shading, elevation caching/downloads and contours; ruler/area measurement and save-as-area; persistent map-button visibility with active escape controls and coordinate Go to | Physical offline/storage-pressure validation; polar UTM measurements are labeled as extrapolated |
| Terrain visibility | Elevation/slope readouts, Android LOS/curvature and uncertainty policy, route profiles/charts, 1/2/4 km day/night viewsheds, offline DEM sampling and cancellation | Physical terrain comparison, outdoor legibility and battery validation; vegetation/structures are outside the terrain model |
| Waypoint library | Coordinates, cross-section search, persisted favourites, distance/name/newest sorting, mixed waypoint/graphic/track selection, visibility swaps, confirmed batch deletion, folder creation/rename/merge/remove, map focus and local persistence; cached background search/order with generation-safe mixed selection | Synchronous-edit and dense-map rendering/accessibility performance work; physical large-library storage checks; physical field validation and storage/interchange limits below |
| Tracks/practice | Background recording/recovery, saved tracks/overlays, moving folders, temporary viewing, confirmed deletion, reverse backtrack routes with endpoint-preserving simplification, GPX, random/folder practice courses, checkpoint navigation lock, strict arrival scoring, persisted pause/recovery and split/results history | Larger-library storage and physical course/guide validation |
| Interchange/sharing | GPX/CSV/GeoJSON/KML/KMZ/ATAK import preview and native Files export, Android-compatible retry IDs and ordered additive persistence, document associations, route-card text/A4 PDF preview/Files sharing, Android streaming ZIP backup contract and optional compatible password protection, guide preferences in backup, bounded ZIP64 metadata/descriptor support, coordinated mapped reads, cancellable background backup preparation, revision-checked staged backup/interchange writes and confirmed-import progress; cancellable worker-prepared library/single-track exports | Remaining waypoint/mixed-folder/session edits and physical large-library performance checks; physical provider/Open In and ATAK client validation, storage-pressure validation and physical PDF sharing/printing; active sessions/offline maps/boundaries are separate from v1 backup |
| Field tools | Resection/intersection worksheets, per-point north-reference conversion, safe ray solver and angle-of-cut warnings; waypoint projection; local/Zulu sun/moon planning with date controls; TN/GN/MN declination diagram; map-menu course/LOS entry points | Physical field/compass/model comparisons; astronomy retains Android's approximate model and 24-hour local-day moon-scan policy |
| Release | Unsigned simulator/device builds, automated tests and draft PR; native menu/presentation and hit-target repairs with local regression evidence | Full hosted CI pass, app icon, privacy/distribution metadata, StoreKit/purchases, signing, physical field validation, TestFlight/App Store release |

See [backup preparation and restore order](backup-preparation.md) for cancellation, progress and the remaining persistence work.

The recording-sheet contrast regression came from the map's light colour scheme
leaking into dark field forms. Field-sheet presentation now explicitly selects
dark controls and rows to match the light text, including recording, coordinates,
map layers, boundaries and GPX import. Military symbols now have their own
validated port, followed by tactical graphics and route drawing. Terrain visibility tools are now ported too; the remaining gaps are recorded above.

See [ZIP64 containers](zip64-containers.md), [GPS course and speed](gps-course-speed.md), [position age and compass reference](position-fix-quality.md), [native screen orientation](screen-orientation.md), [position callouts, QR and USNG naming](position-sharing.md), [projection and field planning](field-planning.md), [resection and intersection](field-fixes.md), [route cards and strip-map PDFs](route-card-pdf.md), [KML/ATAK interchange](kml-atak-interchange.md), [text interchange](text-interchange.md), [practice courses](practice-courses.md), [field library workflows](field-library.md), [map measurements](map-measurement.md), [terrain visibility and profiles](terrain-visibility.md),
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

Optional [password-protected backups](protected-backups.md) now use Android's
`MGRSGPS-ENC1` envelope, with native export confirmation and restore password
prompts. Independent JCA vectors and reverse-direction Swift exports verify
Unicode and byte-level compatibility. Physical Android/iPhone provider checks
remain required. Map-tool preferences now persist locally and through backups;
[map-button behavior](map-tool-visibility.md) covers active-control protection,
reset, direct ruler and Go to. Both watches now display complete cached lane overlays; phone lane-status
synchronization remains a post-release implementation gap. See the
[watch contract](watch-companion-parity.md).

User-requested follow-on: optional Live Activities, off by default, for recording
and active navigation. ActivityKit surfaces session state; background location
execution remains a separate capability. Opt-in, session lifecycle and freshness
presentation are implemented; recording and navigation native workflows pass.
Recording Lock Screen day/night/stale presentation was inspected; physical
checks and navigation Lock Screen inspection remain required. See [Live Activities](live-activities.md). [Apple ActivityKit guidance](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities).


Android `4db6b21` lane startup/cue settings now apply: quiet until confirmed
between the limits, optional entry tick, Off/2/5/10-minute not-yet reminder,
independent side/backstop/inside/GPS-loss switches and a one-minute lane GPS-loss
cadence. Android backup keys/defaults/bounds persist across staged restore while
local Live Activities consent stays separate. The complete core suite passes
362 tests and all 158 app integration tests pass. A native settings workflow
passes persistence, reminder selection and day/night inspection. See
[lane startup and cues](navigation-lanes.md). Android's L/Z time rows and
duplicate-import prompt, phone-to-watch status, physical field checks and the
other performance/distribution gates remain open.
