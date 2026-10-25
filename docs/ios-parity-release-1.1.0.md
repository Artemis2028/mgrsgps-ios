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
| Maps/offline | Android raster catalog/key gating, USGS area download/resume, raster MBTiles, grid/shading, elevation caching/downloads and contours; ruler/area measurement and save-as-area; map lasso with freehand/corner selection, highlights, explicit Hide and confirmed Delete; persistent map-button visibility with active escape controls and coordinate Go to | Physical lasso/large-text checks; leave-map download-completion regression and physical offline/storage-pressure validation; polar UTM measurements are labeled as extrapolated |
| Terrain visibility | Elevation/slope readouts, Android LOS/curvature and uncertainty policy, route profiles/charts, 1/2/4 km day/night viewsheds, offline DEM sampling and cancellation | Physical terrain comparison, outdoor legibility and battery validation; vegetation/structures are outside the terrain model |
| Waypoint library | Coordinates, cross-section search, persisted favourites, distance/name/newest sorting, mixed waypoint/graphic/track selection, visibility swaps, confirmed batch deletion, folder creation/rename/merge/remove, map focus and local persistence; cached background search/order with generation-safe mixed selection; durable worker-prepared map/library editor saves, visible failure/retry, first-target selection and unreadable-file protection | Remaining synchronous non-editor mutation and dense-map rendering/accessibility performance work; physical large-library storage checks; physical field validation and storage/interchange limits below |
| Tracks/practice | Background recording/recovery, saved tracks/overlays, moving folders, temporary viewing, confirmed deletion, reverse backtrack routes with endpoint-preserving simplification, GPX, random/folder practice courses, checkpoint navigation lock, strict arrival scoring, persisted pause/recovery and split/results history | Larger-library storage and physical course/guide validation |
| Interchange/sharing | GPX/CSV/GeoJSON/KML/KMZ/ATAK import preview and native Files export, Android-compatible retry IDs and ordered additive persistence, document associations, route-card text/A4 PDF preview/Files sharing, Android streaming ZIP backup contract and optional compatible password protection, guide preferences in backup, bounded ZIP64 metadata/descriptor support, coordinated mapped reads, cancellable background backup preparation, revision-checked staged backup/interchange writes and confirmed-import progress; cancellable worker-prepared library/single-track exports | Protected single-file interchange export/import is missing (protected backups are implemented); remaining waypoint/mixed-folder/session edits and physical large-library performance checks; physical provider/Open In and ATAK client validation, storage-pressure validation and physical PDF sharing/printing; active sessions/offline maps/boundaries are separate from v1 backup |
| Field tools | Resection/intersection worksheets, per-point north-reference conversion, safe ray solver and angle-of-cut warnings; waypoint projection; local/Zulu sun/moon planning with date controls; TN/GN/MN declination diagram; map-menu course/LOS entry points | Physical field/compass/model comparisons; astronomy retains Android's approximate model and 24-hour local-day moon-scan policy |
| Live TAK (user follow-on) | Native CoT/TCP/mutual TLS, PKCS #12/DER/PEM CA import, explicit CA/name/pin verification and trust reset, Keychain credentials, default-off position/folder sharing, presence/pings/reconnect, per-server offline withdrawal journal, separate remote layer/list/map focus; real iOS ↔ Android positions, shared point/drawing, deletes and reconnect confirmed through local OpenTAKServer; shared 14-event Android fixtures and hosting-kit CA bag compatibility | Enrollment, unsupported certificate-container forms, official TAK Server/ATAK/iTAK and sustained reliability checks, watch TAK scene sync and physical background checks; see [evidence and gaps](tak-server-interoperability.md) |
| Release | Unsigned simulator/device builds, automated tests and draft PR; native menu/presentation and hit-target repairs with local regression evidence | Full hosted CI pass, app icon, privacy/distribution metadata, StoreKit/purchases, signing, physical field validation, TestFlight/App Store release |

See [review follow-ups](android-review-followups.md) for protected interchange and offline lifetime validation; [map lasso](map-lasso.md) is now implemented.

See [durable waypoint editor saves](waypoint-editor-persistence.md) for failure/retry and remaining non-editor I/O.

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
[lane startup and cues](navigation-lanes.md). L/Z time rows and duplicate-import review are now implemented as described
below. Phone-to-watch status, physical field checks and the other
performance/distribution gates remain open.


Position now shows BMNT/SR/SS/EENT in phone-local and Zulu time on Lensatic,
Dial and scrollable Glance details, with the phone zone identified and polar
absence preserved. The existing planning tool already shows local/Zulu sun and
moon events. Duplicate interchange review now follows Android's committed
`eacf084` indexed name/place and track name/count/length policy, with
Skip/Import all/Cancel, worker preparation and stable filtered content IDs.
Incoming files queue behind the current review. See [import review](import-review.md)
and [Position solar rows](field-planning.md).

All 366 core tests and 159 app integration tests pass. The existing native CSV
cancel/import/Skip/relaunch regression and three expanded native workflows pass,
covering Cancel/Import all/stable retry, mixed Skip/night/relaunch and real-GPS
solar readouts on all three faces plus night Glance. Exported day/night screens
were inspected. Both duplicate-review workflows pass again after final copy
refinement, and the final unsigned phone/watch/activity-extension Release build
passes. Test-owned simulators are stopped. Physical external-file/provider/queue and outdoor/large-text
checks remain open. The newer Android `eacf084` lane geometry, backup-presence
and related review changes are tracked in the source audit as the next parity
pass; they are implementation work, not iOS restrictions.


Android eacf084's reviewed lane geometry/guidance and sparse-setting restore are
now ported. Objective-aware resolution is shared by editor, save, map, watch
scene preparation and guidance. Length weighting, U-turn/funnel rejection,
behind-start return, retained entry on same-lane reshaping, warning switches
and drawn-point sanitization are covered. The core suite passes 373 tests;
the final clean native bundle passes all 161 app integration tests plus the new
day/night invalid-objective correction case. The existing four native
lane/backup workflows pass in the preceding matrix. Screenshots were inspected,
the unsigned phone/watch/activity-extension Release build passes, and the
single test phone is shut down. Remaining eacf084 offline/lasso/protected-file
review details need audit. Live TAK is explicitly requested and next; it is
not yet implemented. The existing server was inspected without changing it.
