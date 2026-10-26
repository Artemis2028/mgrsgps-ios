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
read-only phone guidance and a separate TAK watch scene are implemented; Android 4db6b21 startup/cue switches
are now implemented. It does not replace the separate quiet-inside perimeter.

| Area | Implemented on iOS | Still missing or incomplete |
| --- | --- | --- |
| Coordinates/position | Validated MGRS/decimal entry and UTM readouts, units, north reference, WMM, precision/accuracy gates, spherical waypoint projection with saved/current/entered bases, readable phonetic callout, native position/waypoint QR, persisted USNG naming and labelled entry, native Auto/Portrait/Landscape/Flipped controls, compact landscape Position layout, Android age/accuracy/trust labels, screen-relative fresh compass, Android GPS-course source/fallback rules, speed readouts and selected-target visual steering | Physical receiving-camera QR, compass and worn-device checks |
| Military symbols | Full Android curated catalog: 496 unit images, 20 tasks, 15 basic markers; search, affiliation/echelon/designation/type/rotation editing, imported MilGPS appearance editor, shared map/library rendering and night transform | Physical map readability at field distances; the catalog matches Android rather than the entire MIL-STD specification |
| Tactical graphics | All 30 Android control measures, doctrine rendering, map drawing, draggable points and segment handles, metadata, show/visibility/delete, day/night labels; worker-prepared archive edits | Physical field readability and very large-library performance |
| Routes | Waypoint-based and map-based route editors, waypoint snapping, draggable bends, numbered legs, route cards, worker-staged stable generated waypoint ownership with source/cancellation guards and visible errors, GPX, automatic following, durable staged interactive target selection, failure-aware checkpoint transitions and mixed library batches | Remaining session/settings startup reads and physical long-route/readability checks |
| Navigation | Target metrics, relative steering readout, Android guide settings/policy, arrival cues, ordered checkpoint advance, pause/resume, worker-staged runtime session/target saves with source/intent/cancellation guards, background route GPS/milestone notifications; post-release checkpoint/route lanes with separate drawn/linked limits, library/map editing, early warnings and crossing-notification requests | Physical direction-pattern/locked-screen crossing validation; continuous Android-style locked-screen steering haptics cannot be promised on iOS |
| Boundaries | Editable perimeter and draggable bends, quiet inside, confirmed exit/reentry handling, background location and notification requests | Physical locked-screen alert validation, boundary interchange/backup contract |
| Maps/offline | Android raster catalog/key gating, USGS area download/resume, raster MBTiles, grid/shading, elevation caching/downloads and contours; ruler/area measurement and save-as-area; map lasso with freehand/corner selection, highlights, explicit Hide and confirmed Delete; persistent map-button visibility with active escape controls and coordinate Go to; day/night leave-map completion and offline relaunch regression; atomic area Rename, cache-bypassing Update with persistent refresh retry, stored tile counts/size/update date and overlap priority | Physical lasso/large-text and offline/storage-pressure validation; polar UTM measurements are labeled as extrapolated |
| Terrain visibility | Elevation/slope readouts, Android LOS/curvature and uncertainty policy, route profiles/charts, 1/2/4 km day/night viewsheds, offline DEM sampling and cancellation | Physical terrain comparison, outdoor legibility and battery validation; vegetation/structures are outside the terrain model |
| Waypoint library | Coordinates, cross-section search, persisted favourites, distance/name/newest sorting, mixed waypoint/graphic/track selection, visibility swaps, confirmed batch deletion, folder creation/rename/merge/remove, map focus and local persistence; cached background search/order with generation-safe mixed selection; durable worker-prepared map/library editor and ordinary favourite/visibility/folder/mixed-batch saves, visible failure/retry, first-target selection and unreadable-file protection; compact-height phone library controls, staged folder action choices; explicit retry, preserve/share and confirmed archive-before-fresh recovery with retained history | Remaining session/settings startup reads, damaged-session preservation/reset and older library actions and dense-map rendering/accessibility performance work; physical large-library storage checks; physical field validation and storage/interchange limits below |
| Tracks/practice | Background recording/recovery with worker-staged durable finalization, independent immutable point logs and atomic index, legacy migration, saved tracks/overlays, moving folders, temporary viewing, confirmed deletion, reverse backtrack routes with endpoint-preserving simplification, GPX, random/folder practice courses, checkpoint navigation lock, strict arrival scoring, persisted pause/recovery and split/results history with worker-staged course progress, random checkpoints, target locks and result finalization, stable retry and duplicate-free recovery | Independent finished logs remove the combined archive cap; per-log application bounds and orphan-maintenance/startup performance remain work; physical course/guide validation; startup and damaged-session recovery IO |
| Interchange/sharing | GPX/CSV/GeoJSON/KML/KMZ/ATAK import preview and native Files export, password-protected single-file export/import and track GPX, Android-compatible retry IDs and ordered additive persistence, document associations, route-card text/A4 PDF preview/Files sharing, Android streaming ZIP backup contract and optional compatible password protection, guide preferences in backup, bounded ZIP64 metadata/descriptor support, coordinated mapped reads, cancellable background backup preparation, revision-checked staged backup/interchange writes and confirmed-import progress; cancellable worker-prepared library/single-track exports | Startup reads, damaged-session preservation/reset and older library actions and physical large-library performance checks; physical provider/Open In and ATAK client validation, storage-pressure validation and physical PDF sharing/printing; active sessions/offline maps/boundaries are separate from v1 backup |
| Field tools | Resection/intersection worksheets, per-point north-reference conversion, safe ray solver and angle-of-cut warnings; waypoint projection; local/Zulu sun/moon planning with date controls; TN/GN/MN declination diagram; map-menu course/LOS entry points | Physical field/compass/model comparisons; astronomy retains Android's approximate model and 24-hour local-day moon-scan policy |
| Live TAK (user follow-on) | Native CoT/TCP/mutual TLS, PKCS #12/DER/PEM CA import, explicit CA/name/pin verification and trust reset, Keychain credentials, default-off position/folder sharing, presence/pings/reconnect, per-server offline withdrawal journal, separate remote layer/list/map focus; real iOS ↔ Android positions, shared point/drawing, deletes and reconnect confirmed through local OpenTAKServer; shared 14-event Android fixtures and hosting-kit CA bag compatibility; native device-key certificate sign-in with explicit bootstrap trust, ATAK link entry and transactional credential replacement; separate bounded read-only remote scene on both watches | Enrollment renewal/crash recovery, unsupported certificate-container forms, official TAK Server/ATAK/iTAK and sustained reliability checks, Wear paired populated-local preservation/guidance and physical background checks; see [evidence and gaps](tak-server-interoperability.md) and [certificate sign-in](tak-certificate-enrollment.md) |
| Release | Unsigned simulator/device builds, automated tests and draft PR; native menu/presentation and hit-target repairs; Android launcher artwork for phone/iPad/watch with runtime icon evidence | Full hosted CI pass, privacy/distribution metadata, StoreKit/purchases, signing, physical field validation, TestFlight/App Store release |

See [hosted field UI repairs](ci-field-ui-activation.md) for the five older-runtime cases now passing locally; a full new hosted run is still required.

See [protected interchange files](protected-interchange-files.md) for format dispatch, retry/confirmation and queued review.

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
reset, direct ruler and Go to. Both watches now display complete cached lane overlays and a separate, expiring
read-only phone-guidance status. Independent wrist crossing/haptic/background
guidance remains a separate implementation gap. See the
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
below. Physical field checks and the other
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
review details need audit. Live TAK was subsequently implemented and tested as
recorded above; this earlier milestone did not yet include it.

## Unreadable waypoint recovery

The native recovery workflow now preserves the original before any confirmed
empty-library replacement, offers retry without rewriting and retains shareable
originals after relaunch. See [behavior and validation](waypoint-recovery.md).
All 422 core tests and the 188-case native integration suite pass (two unstaged
opt-in local TAK checks skipped). Three final recovery UI workflows pass, including
day/night cancellation, recovery, create/relaunch and an actual Files export.
Release phone/watch/widget build passes. Hosted run 40231275491 was cancelled in
the integration/UI step; it is not a full hosted pass.

Hosted run 40231275491 reached the job timeout after further favourite-menu and
night-projection UI failures. Those workflows are repaired without dropping
outcome checks. The workflow now partitions every UI class into exhaustive
library/map/field jobs and retains all five dedicated location-feed phases.
See [CI repair and partition details](ci-field-ui-activation.md). All three hosted
job conclusions remain required; local passes alone do not close that gate.

## Watch TAK scene

Both companions now display a separate bounded read-only TAK layer with complete
contacts, markers, lines and areas, explicit omissions and watch-side stale expiry.
See [contract and runtime evidence](watch-tak-layer.md). The current suite passes
433 core tests and 191 native integrations (two unstaged local TAK skips).
Hosted run 40244289326 passes the map shard; library and field shards still fail
four UI cases. Full hosted CI remains open.

Ordinary library writes now use [staged library mutations](library-worker-persistence.md),
including partial-retry protection and retained day/night folder drafts.

Route-generated point saves and startup preparation now use [staged generation](route-waypoint-staging.md).
Interactive target selection now uses staged saves; see [target persistence](navigation-target-persistence.md). [Runtime navigation saves](navigation-runtime-persistence.md) now stage target/session preparation off-main with failure/cancellation guards. Course persistence, startup reads/validation and the combined finished-track archive remain separate work.

Practice result history and final active clear now use [worker-staged finalization](practice-result-persistence.md). [Course start/scoring/reconcile/End writes](practice-progress-persistence.md) now stage off-main with expected-run/checkpoint guards, explicit retry and accepted-time preservation. [Random checkpoint generation/library writes](practice-checkpoint-persistence.md) and [practice target-lock writes](practice-target-persistence.md) also stage on workers. Startup reads, damaged-session preservation/reset and older library actions remain implementation work.


### Settings interaction follow-up

The latest local repair uses scrolling lane-reminder choices with persisted
Android minute values, readable day/night guide forms, a 44-point Live Activities
row and actual native-switch hit targets. Presented Settings also owns a scene
orientation host; its regression verifies selected Portrait and actual geometry
after pinned Flipped relaunch, then Auto rotation. Five focused UI workflows pass;
12 related native tests and the expanded night reminder workflow pass on final
source. See [hosted diagnostics and local evidence](ci-field-ui-activation.md).
Full hosted CI and physical locked-screen validation remain gates.


### Random course checkpoint writes

Random generation and checkpoint-library staging now run on workers, retaining
one proposal across retry/rebase. The course clock starts after library commit;
later course-save retry never regenerates points or restores deleted checkpoints.
End retains the saved points, matching Android. See [checkpoint ordering and
validation](practice-checkpoint-persistence.md). Practice target-lock writes now
also stage on workers; startup/damaged-course recovery remain work.


### Practice target workers

Practice lock/target preferences now stage on workers, with an immediate course
selection gate, revision/owner checks and explicit retry. Running guidance holds
cues and reports saving to watch/Live Activities until target acknowledgment;
End cancels pending work, and deleted checkpoints cannot publish a stale target.
See [target ordering and validation](practice-target-persistence.md). Startup
reads and damaged-session preservation/reset remain synchronous work.


### Independent finished logs

Finished tracks no longer share the external backup ZIP cap. [Local log storage,
migration and evidence](finished-track-storage.md) cover the new atomic index,
worker-installed immutable logs, preserved legacy archive, rollback/retry and
post-commit cleanup. Core validation includes 750,000 points across three logs,
more than 32 MB and 513 tracks. Per-log application bounds, startup cost, guarded
crash-orphan maintenance, external backup bounds and physical storage pressure
remain explicit implementation/validation work.


## Paired Wear and CI follow-up, 26 October

The user completed the dedicated Android simulator pairing. Actual Wear Data
Layer TAK receipt, inspected accented-name/item info, clear and stale-cache
expiry with the phone emulator shut down now pass. This closes the Google Play
setup gate; populated local/remote preservation, paired guidance lifecycle and
physical radio/background checks remain. Both Android emulators were shut down
when the round finished. See [watch TAK evidence](watch-tak-layer.md).

Hosted run 40273435731 is terminal: map passes, field has four UI failures and
library hit its job deadline. Local replay passes protected backup, CSV/GeoJSON,
malformed/night preview and recording Live Activity lifecycle. The final Files
helper handles valid controls under an infinite AX application window; Settings
uses bounded drags, PDF export belongs to the presentation root, and per-test
execution timeouts preserve diagnostics and later test coverage. No assertion or
UI class was removed. Final export replay and final-head hosted status are
recorded in [CI evidence](ci-field-ui-activation.md).


## Hosted 9a258c7 completed and local follow-up

Run 40295990817 completed with the library shard green, map failing its live-
recording Record-visibility switch, and field failing one practice integration,
large GPX reopen and navigation Live Activity opt-in. The practice test now uses
its feedback double instead of waiting on real notification consent. Switch
settings await acknowledgement and retry only an unchanged value; Files opens
the actual thumbnail instead of the filename edge. All assertions remain.
All seven affected UI cases pass locally (both exports, both Activities and all
map-button workflows). The final protected-file helper check and native evidence
are recorded in [CI follow-up](ci-field-ui-activation.md). Full hosted green
remains required; user-facing production permission/navigation behavior is
unchanged by this test repair.


Day map controls now use light symbols on dark native glass so their inherited
black foreground cannot disappear against dark imagery; the coordinate HUD keeps
its light surface and night mode remains red on black. Both final map workflows
and phone/watch/widget Release pass; screenshots were inspected. The complete
seven-case CI replay passes, as do the final protected-backup workflow and 58
related native integrations. Full hosted confirmation remains open.


## Deferred field-library startup and TAK readiness

Normal app startup now stages field-library reads on one shared worker with readable day/night loading and guarded navigation, practice scoring, recovered-track finalization, watch publication and backup writes. TAK preserves previously shared graphics while their source is unreadied/corrupt, still withdraws known hidden waypoints, and keeps explicit full unshare authoritative. See [startup behavior and evidence](field-library-startup.md). This does not close other synchronous startup sources or lazy log loading.

Latest completed hosted run 40314727241 on dfed828 passes library and map; field has one large GPX native Files reopening failure. Its dismissal acknowledgment repair passes locally with the actual recording/background-location workflow. Full hosted CI remains open.


## Enrolled TAK and bright-map follow-up

The real enrolled Android/iOS round now verifies peer/item map rendering, item deletions and reconnects. Sustained iOS position continuity remains open after a stationary simulator feed stopped delivering fresh fixes; the real-driver A/B capture confirms continuous nonzero reports with tiny movement. [Evidence and remaining gate](tak-server-interoperability.md). The app now distinguishes a sharing switch being on from having a fresh fix to send.

Bright terrain exposed native glass independently lightening behind light map symbols. Map controls and recording now retain a dark backing beneath native interactive glass. All three map-tool workflows pass, including day/night go-to, hidden active drawing/ruler and stop access during recording. Final screenshots were inspected in `/tmp/gridfix-readable-map-glass.xcresult`; the red/black night controls retain their existing treatment.

TAK sharing now applies the agreed Android/iOS strict 30-second and 1 km accuracy bounds independently of display/navigation rules, refuses 0,0, and visibly explains presence-only waiting. Final 242 native cases pass (three unstaged local skips), including the real-driver moving-feed check; final Release passes. The enrolled 90-second continuous-position extension is built but not yet verified against the server. Additional bright topographic screenshot `/tmp/gridfix-readable-map-bright.png` confirms readable symbols above pale tiles.


The corrected 90-second enrolled continuity round subsequently passed: nine consecutive nonzero iOS reports with no intervening presence, fresh inbound data, and independent Android/server confirmation. This closes the real enrolled-simulator exchange gate; physical stationary/screen-lock behavior, renewal/crash recovery and wider server testing remain open. Both sides cleaned up their fake feeds and disconnected; Claude shut down the local server and Android emulator. See the final [enrolled continuity evidence](tak-server-interoperability.md).


## Waypoint bootstrap and recording contrast follow-up

Saved waypoints now prepare on a shared worker before app services are constructed,
with replacement detection, readable day/night loading, cancellation/retry and
early OS-link preservation. The selected target and field library survive cold
launch; damaged waypoint recovery remains read-only until explicit recovery.
Full core validation passes 479 cases; native validation executes 247 cases with
four unstaged opt-in skips and no failures. The protected-backup, background
recording and day/night recovery regression also passes. See
[waypoint preparation and evidence](waypoint-startup.md).

Hosted run 40332083000 failed four UI interactions across its three shards:
coordinate-format selection, offline-grid switch, backup menu acknowledgement
and boundary vertex movement. All four workflows now pass locally with bounded
acknowledgement helpers and slower deliberate vertex drags; no assertions or
classes were removed. Full hosted green still needs confirmation on the new head.

Phone/iPad and watch now use the Android launcher crosshair artwork with explicit
sRGB assets. Actual simulator launchers and Release builds were checked; see
[app icons](app-icons.md).

The recording panel now sets explicit dark row surfaces and a readable title;
night help text stays red on black. Final active recording and day/night cold-link
workflows pass with screenshots inspected, and phone/watch/widget Release passes.
Evidence: `/tmp/gridfix-recording-contrast-final.xcresult` and
`/tmp/gridfix-recording-contrast-release.log`.


## Saved-map startup

Saved-map catalog/preferences and cache objects now prepare alongside waypoints
on the shared worker before map rendering and app-service publication. Metadata
checks refuse stale replaced/removed/new sources and retry; damaged catalogs
remain preserved/read-only. Real imported MBTiles and saved offline-only policy
are covered without network requests. All 251 native cases pass (four unstaged
opt-in skips), as do seven cold-library/map/terrain UI workflows and the final
phone/watch/widget Release build. See [contract and evidence](map-startup.md).
Other session/settings startup reads and lazy finished-log work remain open.
