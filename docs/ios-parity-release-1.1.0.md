# Remaining parity with Android release/1.1.0

Reference: `Artemis2028/gridfix` branch `release/1.1.0`, commit `482b417`,
24 October 2026. This inventory supplements the earlier 1.0.4 milestone notes.
It is not a claim of full Android parity.
The release branch was rechecked through GitHub on 27 October and still points to this commit.
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
| Military symbols | Full Android curated catalog: 496 unit images, 20 tasks, 15 basic markers; search, affiliation/echelon/designation/type/rotation editing, imported MilGPS appearance editor, shared map/library/target-chooser rendering and night transform | Physical map readability at field distances; the catalog matches Android rather than the entire MIL-STD specification |
| Tactical graphics | All 30 Android control measures, doctrine rendering, map drawing, draggable points and segment handles, metadata, show/visibility/delete, day/night labels; worker-prepared archive edits | Physical field readability and very large-library performance |
| Routes | Waypoint-based and map-based route editors, waypoint snapping, draggable bends, numbered legs, route cards, worker-staged stable generated waypoint ownership with source/cancellation guards and visible errors, GPX, automatic following, durable staged interactive target selection, failure-aware checkpoint transitions and mixed library batches | Physical long-route/readability checks; ordinary settings persistence follow-up validation |
| Navigation | Target metrics, relative steering readout, Android guide settings/policy, arrival cues, ordered checkpoint advance, pause/resume, worker-staged runtime session/target saves with source/intent/cancellation guards, background route GPS/milestone notifications; post-release checkpoint/route lanes with separate drawn/linked limits, library/map editing, early warnings and crossing-notification requests | Physical direction-pattern/locked-screen crossing validation; continuous Android-style locked-screen steering haptics cannot be promised on iOS |
| Boundaries | Editable perimeter and draggable bends, quiet inside, confirmed exit/reentry handling, background location and notification requests | Physical locked-screen alert validation; Android re-export drops the optional iOS-only quiet-boundary section |
| Maps/offline | Android raster catalog/key gating, USGS area download/resume, raster MBTiles, grid/shading, elevation caching/downloads and contours; ruler/area measurement and save-as-area; map lasso with freehand/corner selection, highlights, explicit Hide and confirmed Delete; persistent map-button visibility with active escape controls and coordinate Go to; day/night leave-map completion and offline relaunch regression; atomic area Rename, cache-bypassing Update with persistent refresh retry, stored tile counts/size/update date and overlap priority | Physical lasso/large-text and offline/storage-pressure validation; polar UTM measurements are labeled as extrapolated |
| Terrain visibility | Elevation/slope readouts, Android LOS/curvature and uncertainty policy, route profiles/charts, 1/2/4 km day/night viewsheds, offline DEM sampling and cancellation | Physical terrain comparison, outdoor legibility and battery validation; vegetation/structures are outside the terrain model |
| Waypoint library | Coordinates, cross-section search, persisted favourites, distance/name/newest sorting, mixed waypoint/graphic/track selection, visibility swaps, confirmed batch deletion, folder creation/rename/merge/remove, map focus and local persistence; cached background search/order with generation-safe mixed selection; durable worker-prepared map/library editor and ordinary favourite/visibility/folder/mixed-batch saves, visible failure/retry, first-target selection and unreadable-file protection; compact-height phone library controls, staged folder action choices; explicit retry, preserve/share and confirmed archive-before-fresh recovery with retained history | Other runtime-session startup reads, older library actions and dense-map rendering/accessibility performance work; physical large-library storage checks; physical field validation and storage/interchange limits below |
| Tracks/practice | Background recording/recovery with worker-staged durable finalization, independent immutable point logs and atomic index, legacy migration, saved tracks/overlays, moving folders, temporary viewing, confirmed deletion, reverse backtrack routes with endpoint-preserving simplification, GPX, random/folder practice courses, checkpoint navigation lock, strict arrival scoring, persisted pause/recovery and split/results history with worker-staged course progress, random checkpoints, target locks and result finalization, stable retry and duplicate-free recovery | Independent finished logs remove combined/per-log backup-derived caps; orphan maintenance and dense/very-large-library performance remain work; physical course/guide validation; large-course eligibility/list rendering and other runtime-session startup IO |
| Interchange/sharing | GPX/CSV/GeoJSON/KML/KMZ/ATAK import preview and native Files export, password-protected single-file export/import and track GPX, Android-compatible retry IDs and ordered additive persistence, document associations, route-card text/A4 PDF preview/Files sharing, Android streaming ZIP backup contract and optional compatible password protection, guide preferences in backup, bounded ZIP64 metadata/descriptor support, coordinated mapped reads, cancellable background backup preparation, revision-checked staged backup/interchange writes and confirmed-import progress; cancellable worker-prepared library/single-track exports | Remaining ordinary persistence costs, older library actions, full hosted confirmation and physical large-library performance checks; physical provider/Open In and ATAK client validation, storage-pressure validation and physical PDF sharing/printing; active sessions/offline maps remain separate from v1 backup; optional quiet-boundary geometry extension and Android compatibility fixtures pass |
| Field tools | Resection/intersection worksheets, per-point north-reference conversion, safe ray solver and angle-of-cut warnings; waypoint projection; local/Zulu sun/moon planning with date controls; TN/GN/MN declination diagram; map-menu course/LOS entry points | Physical field/compass/model comparisons; astronomy retains Android's approximate model and 24-hour local-day moon-scan policy |
| Live TAK (user follow-on) | Native CoT/TCP/mutual TLS, PKCS #12/DER/PEM CA import, explicit CA/name/pin verification and trust reset, Keychain credentials, default-off position/folder sharing, presence/pings/reconnect, per-server offline withdrawal journal, separate remote layer/list/map focus; real iOS ↔ Android positions, shared point/drawing, deletes and reconnect confirmed through local OpenTAKServer; shared 14-event Android fixtures and hosting-kit CA bag compatibility; native device-key certificate sign-in with explicit bootstrap trust, ATAK link entry and transactional credential replacement, client certificate UTC dates/fingerprint/30-day notices and manual renewal preserving active sessions/sharing; separate bounded read-only remote scene on both watches | Live renewal verification and crash-time orphan-key recovery, unsupported certificate-container forms, official TAK Server/ATAK/iTAK and sustained reliability checks, Wear paired named-lane crossings and physical background checks; see [evidence and gaps](tak-server-interoperability.md) and [certificate sign-in](tak-certificate-enrollment.md) |
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


The map-centre grid now places zone/square above the full easting/northing,
with vertical space for wrapping and the unchanged canonical VoiceOver label.
This fixes the truncated coordinate exposed by the day viewshed screenshot.
All three map-tool workflows, offline-map relaunch and offline LOS/profile/viewshed
pass with the new readout: `/tmp/gridfix-map-grid-readability.xcresult`. Final
phone/watch/widget Release passes: `/tmp/gridfix-map-grid-readability-final-release.log`.

The final offline-map day/night workflow also passes with screenshots inspected: `/tmp/gridfix-map-grid-final.xcresult`.


## Course-session startup and preserved reset

Practice sessions now prepare with waypoints/maps on the shared startup worker.
Saved run identity/order/splits remain intact; field readiness still gates target
reconciliation, with no automatic navigation restart or scoring. Damaged-session
copy and empty replacement also prepare on a worker, preserving the original
before reset and keeping navigation locked through durable acknowledgement.
Changed source files refuse stale recovery. The confirmation has an explicit
Keep saved session action for native popovers.

Full core validation passes 484 tests; the full native suite executes 255 cases
with four unstaged opt-in skips and no failures. Five course UI workflows pass,
including day/night preserve/reset/cancel/cold relaunch and target-save failure
retry. Screenshots were inspected; final phone/watch/widget Release passes.
See [course startup and recovery evidence](course-startup-recovery.md).
Large-course rendering, other runtime-session startup, physical storage
pressure and field/background validation remain work.


## Navigation-session worker startup

Saved navigation now prepares before live services, with the existing 2 MiB
limit checked before reading, worker route validation and source-change retry.
Saved route/index/haptic preferences remain intact; restored routes stay paused
until explicit resume. Damaged sessions remain preserved and cannot start GPS
or cue playback. Full native validation passes 259 cases (four unstaged opt-in
skips), and actual simulator navigation passes cold relaunch at point 2, manual
resume, background completion and completed-state relaunch. Screenshots and the
final phone/watch/widget Release build pass. See [startup evidence](navigation-startup.md).

Hosted run 40349066649 on 2fdd91e has finished with all three UI shards failed.
Eight cases remain under investigation: large GPX Files reopen, track-detail
export filename access, TAK preview opening, backup filename focus, two protected
GPX workflows, navigation-lane reopening and target-selection error presentation.
The prior interaction fixes did not establish a complete hosted pass. Native
Files video confirms the track-detail save picker opens without its filename
footer; that remains a separate presentation investigation. Local acknowledgement
repairs are being replayed without removing the affected cases or assertions.

The final local Files replay now passes all seven selected backup/export/
protected-file cases. Together with the lane, target and TAK preview replay,
all eight hosted failure cases pass locally. Native filename focus, scoped
search results, actual Files selection and dismissal remain exercised; full
hosted green and older-runtime filename-footer verification are still open.

## Practice setup rendering and older-runtime Files replay

Practice folder setup now counts the library once per folder-mode render,
preserving folder order and hidden checkpoints. Random setup avoids that scan.
Existing folder lock/relaunch/end, random setup and readable night form workflows
pass on iOS 26.2, as does the final Release build. Course history/list scaling
and the other performance work above remain separate.

All seven native Files cases also pass at pushed head `90391ec` on iOS 26.2
(23C52); missing filename UI did not reproduce locally. Hosted run 40366024560
remains in progress. The available local runtime build and Xcode differ from
the hosted environment; see the bounded claim in [CI evidence](ci-field-ui-activation.md).


## Settings startup on the shared worker

Saved settings now prepare before the live service graph too, preserving night
appearance, pinned orientation, coordinate/guide choices, hidden tools and local
Live Activities. A changed source retries before publication; the temporary
loading view stays red on black until appearance is known. Existing defaults,
normalization and malformed-settings fallback are unchanged. Full validation of 264 native cases, day/night cold-library and actual early recording-link UI, pinned
orientation cold relaunch and final Release pass. See [settings startup](settings-startup.md).
Other runtime-session startup sources, ordinary preference writes were still work at this milestone; see the later
[settings persistence follow-up](settings-persistence.md). Per-log/lazy reads and
the remaining performance/physical gates remain work.

## Boundary library startup

Saved quiet-inside perimeters now decode and validate on the shared startup
worker too, including the existing size/count/geometry checks and source-change
retry. Interrupted monitoring stays off; unreadable files remain kept and
read-only. Full native validation passes 268 cases (four opt-in local skips),
and real simulator drawing/direct dragging/background crossing and interrupted
worker cold relaunch pass. Final Release passes. See
[boundary startup evidence](boundary-startup.md). Physical locked-screen alerts,
ordinary boundary writes were still open at this milestone; the later
[worker persistence follow-up](boundary-persistence.md) covers those writes.
Physical alert delivery and the other remaining gates remain open.

## Native export presentation and hosted follow-up

Hosted run 40366024560 finished failed with seven UI cases, while core484 and
native259 pass. The earlier TAK preview, target selection, lane reopening and
backup/protected-file failure cases now pass there. Field video confirms one
Save picker without its filename footer and another with a visible, focused
field rejected by the harness. The field export document/type/name now remain
complete and immutable in a dedicated presenter before Files opens and while it
closes. Menu/input acknowledgement repairs retain all original content checks.

At final local source, all 268 native cases pass (four opt-in local skips), all
13 selected UI cases pass, and the strengthened native cancellation/re-export
case separately verifies exact complete fixture counts. Phone/watch/widget
Release passes. Day/night import and cancellation review screenshots were
inspected. Full hosted green and the hosted-only missing-footer explanation
remain open; [CI evidence](ci-field-ui-activation.md) records the bounded claim.

The Wear companion phone fork separately ports the agreed 30-second/1-km TAK
sharing policy, rejecting unknown accuracy and nanosecond future/expiry edges
and retaining actual CoT accuracy. It is pushed as e6a702f to the companion draft:
458 phone and 34 watch tests, Debug and TAK-enabled unsigned Release builds pass.
This is policy/build evidence, not a new live server exchange. The watch remains
a read-only remote-layer receiver; physical and paired guidance gates remain.

## Recording background evidence

The real-location iOS 26.2 recording workflow now requires host-observed journal
growth while the app stays on Home, before foreground activation. The same
session grew from 3 to 6 complete saved records in that interval; save/library/map,
confirmed discard and interrupted recovery through the shared startup worker all
pass. Eight Python harness cases pass. Recording screenshots remain readable.
See [recording evidence](track-recording.md). This strengthens simulator evidence;
physical locked-screen GPS, Data Protection and battery checks remain open.

## TAK preferences on the startup worker

The local TAK profile and endpoint sharing journal now prepare on the shared
worker too, preserving first-install UID, saved trust and default-off position
sharing. Source replacement/removal/creation retries before one service graph;
damaged bytes stay preserved with the existing error/disabled-sharing behavior.
No Keychain read or connection is started by this preparation. Full native274
passes with four unstaged opt-in checks skipped; all three real recording UI
cases and the unsigned device Release build pass. See [TAK startup](tak-startup.md).
The earlier enrolled simulator round remains separate; no server was contacted
for this change. Ordinary TAK writes and physical/renewal/crash checks remain.


## Paired Wear populated-library and guidance gate

The real dedicated emulator pair now verifies a populated local waypoint/route/track
scene and selected target survive remote TAK add/clear unchanged. Actual phone
service decisions reach the watch as active, unavailable and stopped states; after
the phone is killed, the watch expires steering instead of retaining it. No watch
receiver cache was injected and no server used. Screenshots and receiver payloads
were inspected. See [paired evidence](wear-paired-validation.md), pushed as a788dbf
to the companion draft PR. Both emulators and the fake feed are stopped. Named
lane crossings on paired Wear and physical background/radio/wrist checks remain.


## Long local recordings independent of backup bounds

The Android local recorder/reader has no 250,000-point/16-MB cap. iOS now follows
that behavior for recording, recovery, local persistence/readback, map/focus and
backtrack, while external backup/import and watch budgets remain bounded. Local
statistics validate every row without a complete point array; legacy newline
forms still parse and malformed trailing rows fail. Individual GPX export keeps
all points beyond the backup count limit. See [storage details](finished-track-storage.md).

Final core486 pass; native275 pass with four unstaged local checks skipped; all
three real Core Location recording UI cases and unsigned device Release pass.
The oversized recovery test saves/reopens/moves a 300,001-point,17,400,058-byte
log; a native XMLParser counts every point in the 250,001-point GPX export. Normal
recording again grows3→6 durable points while on Home, then saves/maps/reopens.
Evidence: `/tmp/gridfix-long-local-track-core-verified.log`,
`/tmp/gridfix-long-local-track-native-verified.xcresult`,
`/tmp/gridfix-long-local-track-native-verified-background-check.log`,
`/tmp/gridfix-long-local-track-release.log`. All tests ended before the exact
owned auxiliary simctl diagnostic was shortened; xcodebuild finalized exit0.
Storage pressure, physical lock/Data Protection and huge map memory remain open.

Hosted run40379715936: map succeeds; field finishes with two remaining UI
failures (large GPX filename footer and route-PDF filename focus). Library still
runs. Full hosted green remains unproven; later iOS commits stay local until that
run ends so it is not cancelled.

## Direct native Files export and complete local replay

Hosted 40379715936 is terminal: map succeeds; library has one final favourite
ordering failure; field has the large GPX footer and PDF focus failures. The
retrieved videos show a genuinely absent footer for GPX and a selected PDF name
with keyboard while XCTest retained a stale earlier share-service snapshot.
The final candidate stages an immutable source on a worker and lets UIKit own
the native export modal. Input focus is re-resolved after foreground activation;
favourite removal/order is acknowledged before the existing assertions.

All 277 native cases pass (four unstaged opt-in skips). Eleven primary UI cases
pass, including all three hosted failures and exact complete GPX reopening and
cancel/re-export contents; seven additional backup/protected-file/lane restore
regressions pass. Final unsigned device Release passes. Both xcodebuild parents
exit 0 without diagnostic interruption. Day/night review/restoration screenshots
were inspected. No case, assertion, count or shard is excluded. Full hosted
confirmation remains open. See [CI evidence](ci-field-ui-activation.md).


## Worker-prepared saved-track map geometry

Saved logs now decode once off Main and use Android release/1.1.0 drawing stride
plus the final endpoint. Full-log fit extrema remain exact, including unsampled
excursions. Cancellation/generation guards reject old drawings after hide/delete;
loading and retry are explicit. Deferred Show All cannot override a newer Go To
or manual pan. Core490, native281 (four unstaged opt-in skips), all12 selected
map/lasso/interchange/recording UI workflows and unsigned device Release pass.
Both test/build parents exit0 naturally. Day/night/recording screenshots inspected;
300001-point worker check observed a maximum Main pulse gap of0.00724seconds.
See [implementation and limits](map-geometry-preparation.md). Full hosted run
40395046579 remains live on d153810; this validated change is held locally to
avoid cancelling it. Huge-log memory and dense tactical rendering remain work.


## TAK choices remain unchanged when saving fails

TAK callsign/folder/layer settings and certificate pins now publish only after
successful local persistence. A failed share opt-in cannot activate sharing;
a failed withdrawal stays visibly selected with an error. Failed pin storage
retains the previous pin and approval prompt without reconnecting. Explicit
retry persists and publishes the choice. Final native283 (four unstaged skips),
three selected day/night TAK UI workflows and unsigned device Release pass;
screenshots inspected. These are mocked-transport/preview checks, independent
of the earlier live enrolled exchange. See [TAK persistence](tak-startup.md).


## Row-scanned saved-track previews

Saved-track drawing now counts actual rows, then validates each point once while
retaining only the Android preview and exact fit extrema. It no longer builds
a full coordinate array. Bad metadata, legacy separators, malformed single rows
and damaged UTF-8 are covered; saved/exported bytes stay complete. Core492,
native283 (four unstaged skips), all12 selected map/lasso/interchange/recording
UI cases and unsigned device Release pass. Final parents exit0 naturally;
screenshots inspected. Home journal growth4→6 is observed before foreground
activation. See [map evidence and limits](map-geometry-preparation.md).

Hosted40395046579 on d153810: map passes, field fails three Files interactions,
library still runs. These are being diagnosed; the local changes remain held to
avoid cancelling the library run.


## Fresh Files replay after run 98

Retrieved hosted field screenshots and the complete xcresult. Both failed focus
checks visibly show a selected filename; the root AX tree reports the exact
native editor focused while its leaf description is stale. The first export
also displays the system keyboard tutorial. The UI helper now dismisses that
specific tutorial and positively checks the exact editor's focus in a fresh
root snapshot. Exact filename replacement, native Save and complete reopening
assertions remain unchanged.

All five field-export/PDF workflows pass after erasing the owned test simulator;
the log confirms the real Continue tap. Three ordinary/protected backup/KML
regressions also pass. Day/night screenshots inspected. This test-only repair
preserves the previously verified product source and Release build. The library
shard remains live; full hosted green is still unproven. See
[hosted evidence and replay](ci-field-ui-activation.md).


## Waypoint choices and readable night secondary text

Run 98 is terminal: map passes; library has two failures and field three.
The favourite failure reproduces locally with the popup still open: the action
never ran. Waypoint actions now use the native scrolling choice sheet already
used for tracks/folders, execute after dismissal, revalidate saved identity and
preserve explicit favourite on/off intent. Edit, visibility, navigation, map
focus and confirmed deletion remain. The system-gray search prompt now uses
the field palette; muted night text changes from roughly2.79:1 to4.95:1 solid
contrast against black, retaining red/black styling.

Final native283 (four unstaged skips), all17 selected library/search/folder/
startup/coordinate UI workflows, a separate complete waypoint-choice walkthrough,
and unsigned device Release pass. Day/night screenshots inspected. The focused
walkthrough verifies cancellation, edit/save, hide/show, map focus, navigation,
cancelled and confirmed deletion, and persisted deletion after relaunch. A
Navigate-label ambiguity in its initial test was corrected to the exact action
identifier; the original failed replay remains diagnostic evidence.

All eight harness checks pass. Measured CI UI durations motivated moving the
complete protected-file class (about7.6minutes) from library to map; all tests
still run exactly once with three workers. The shared Files helper repair and
map/TAK worker changes are included in the next full hosted candidate; hosted
green remains unproven. See [CI evidence](ci-field-ui-activation.md).


## Paired Wear named-limit delivery

The real dedicated phone/watch pair now verifies INSIDE → OUT_LEFT (Bear Creek),
return INSIDE, OUT_RIGHT (Ridge Road), return INSIDE, OVERSHOT (Power Line) and
return INSIDE. The backstop/return phases run while the phone launcher is
foreground. Native backup restore, target selection and Haptic Guide plus real
emulator GPS drive the production owner and Data Layer; no watch cache or guide
decision is injected. Complete bent limits/labels arrive alongside unchanged
original local features. Native stop/delete and original-target reselection
restore the original scene, target and local watch overrides. Screenshots
inspected; both owned emulators and feed are stopped. No server or app-source
change. See [paired evidence and precise limits](wear-paired-validation.md).
Physical lock/radio/battery/wrist and independent watch detectors/haptics remain
open; the earlier watchOS paired named-crossing evidence stays separate.


### Quiet-boundary backup and native export sequencing — 27 October 2026

Saved custom quiet-inside perimeters now have an optional `quietBoundaries`
version-1 section in ordinary and protected backups. It is geometry only,
separate from navigation lanes. Restore is additive, retains local edits,
stages validation/writes off Main, checks the current source/session before
publication, reports partial phases and retries without duplicates. Imported
areas never start location/alerts; an existing local monitor remains unchanged.
Limits and Android re-export loss are explicit in `backup-format-v1.md`.
Claude independently opened both Swift-written fixtures using the Android
crypto/parser: two tests passed with the exact accented waypoint and safely
ignored perimeter section. No server or emulator was involved.

Files round-trip validation also caught an actual boundary editing issue:
annotation views swallowed drawing taps over saved waypoints. Those taps now
add a vertex at the waypoint, matching route snapping. Export format selection
uses the existing scrolling native choice sheet and starts preparation only
after dismissal, avoiding overlap with Files or password presentation.

Hosted run99 on6334c2e is terminal: map and field pass; library has three
interaction failures (import confirmation, ATAK Files presentation, night-mode
switch). The local confirmation/ATAK cases pass; another hosted run remains pending. The existing
one-minute Claude watcher remains coordination, not a dependency for work.

Final local validation: 494 core tests pass, including the ordinary/protected
fixture round trip. All 290 native cases pass (four unstaged opt-in local
checks skipped). Twelve distinct selected UI workflows pass across the final
passes: ordinary/protected boundary backups, large GPX, export cancellation,
single-track exports, duplicate confirmation/retry IDs, KML rejection and
preview/map/ATAK export, KMZ, protected KML/password retry, queued protected
incoming backup/file and night-mode settings/coordinate entry. The incoming
fixture now includes perimeter geometry and verifies its preview, durable
restore and inactive relaunch through RootView. The maximum 100 × 256-vertex
native restore remains responsive and reopens every vertex. External file
replacement, failed write/partial phases and cancelled confirmed retry pass.
Unsigned device Release and all eight Python harness checks pass.

Test development caught two night-map gesture hits over waypoint annotations
(fixed in product), then incorrect daytime-tab and unscoped Done lookups in the
new backup test helpers (corrected in tests). The final full native/backup pass
had all native cases and both backup workflows green, but its old incoming
Done lookup failed; the corrected standalone incoming test passes completely.
One earlier completed general regression run's owned diagnostic collection was
shortened only after every test ended; its actual failure result was retained.
Named day/night restore screenshots were inspected. Evidence:
`/tmp/gridfix-boundary-backup-core-final.log`,
`/tmp/gridfix-boundary-backup-fixture.log`,
`/tmp/gridfix-quiet-backup-validation.xcresult`,
`/tmp/gridfix-quiet-backup-final.xcresult`,
`/tmp/gridfix-quiet-backup-incoming-final.xcresult`,
`/tmp/gridfix-quiet-backup-release.log` and
`/tmp/gridfix-quiet-backup-script-checks.log`.


### Streaming track focus and presentation ownership — 27 October 2026

Opening a saved track no longer constructs full TrackPoint/coordinate arrays
just for a camera fit. A worker validates every row and returns at most six
exact normal/wrapped extrema, including one-point logs and unsampled excursions.
Track source identity/revision is checked before and after revealing the parent
folder, and again at publication. Replacement retries the current log; deletion
and cancellation cannot return old geometry. Leaving the library or issuing a
newer camera request prevents late map focus. Track visibility, stored bytes
and the selected navigation target remain unchanged. Android's temporary view /
unhide-parent behavior is retained; fitting is the existing iOS convenience.

The shared field-edit completion also checks its original presentation token,
so confirmed work finishes without dismissing a closed-and-reopened screen.
Its existing main-thread isolation remains. Screenshot review fixed compressed
night-map grid/layer captions by allowing the readout its full vertical size.

496 core,298 native (four unstaged opt-in local skips),three library UI cases and
unsigned device Release pass. A 300003-row dateline log fits using six coordinates
in about0.594s with292 main-thread pulses on the simulator. Full-source bytes,
selected target and all fit extrema are checked. A fresh day/night map workflow
passes after the layout fix; grid interval and layer name are fully visible in
inspected screenshots. Both final test parents exit0 naturally. Earlier completed
runs had owned diagnostic collection shortened only after every test passed.
See [details, Android source and remaining memory limits](track-map-focus.md).
Backtrack still materializes a full coordinate array; orphan maintenance,
dense-map aggregates and physical memory/storage/battery checks remain work.


27 October certificate follow-up: [client dates and manual renewal](tak-certificate-enrollment.md)
now match Android b31f36c notices, threshold and session-preserving replacement.
309 native cases (four opt-in skips), four day/night UI workflows and unsigned
device Release pass locally. Synthetic/mock lifecycle evidence is separate from
real enrolled peer exchange and live renewal, which remain open. Hosted100 on
57348f7 is terminal: map passes; library has one backtrack workflow failure and
field has four Files/recording failures. Full hosted green is still required.


Hosted100 follow-up: graphic actions now use the native scrolling choices and
apply after dismissal, repairing the ignored backtrack route-card popup.
All ten selected UI workflows pass locally, including all five hosted100
failures, day/night graphic visibility/cancellation, exact native Files round
trips, PDF, recording discard/background/recovery. The Home journal grows from
four to six points before foreground activation. Release and eight harness
checks pass; screenshots inspected. These changes remain local while hosted101
40429934209 runs on `39da6e4`. Full hosted green and physical checks remain open.
See [dated repair evidence](ci-field-ui-activation.md).


Backtrack source follow-up: immutable source revisions now guard worker
calculation, folder reveal and atomic route publication. Replacement during
calculation retries the latest log/name/folder; later replacement/deletion or
cancellation cannot publish old geometry. Android's exact priority simplifier
uses one forward coordinate array with reversed index access and a bounded
selection set, removing full TrackPoint/reversed/keep-array copies. Linear
coordinate memory and worst-case physical performance remain limits.
All 499 core and 316 native cases pass (four opt-in skips), all three selected
backtrack/day-night graphic UI workflows pass, and device Release passes.
The 300,003-point check keeps the source and target, returns three vertices in
about 0.659 seconds with 332 main-thread pulses. Screenshots inspected and parent
exits 0. Hosted run 101 remains live on `39da6e4`; follow-ups are local until it finishes.
See [source integrity and evidence](backtrack-source-and-memory.md).


Both watch receivers now keep a monotonic phone-guidance lifetime across cache
replay and app relaunch. Clock rollback cannot renew the original budget;
new source packets remain supported. 504 Swift core and 39 Wear unit cases pass,
as do Apple Release/paired Debug, Wear Debug/Release/lint and Android phone Debug.
Real paired delivery, expired relaunch and preserved local scene/overrides are
recorded with [exact limits and cleanup caveat](watch-guide-expiry.md).
Hosted run 101 is terminal on `39da6e4`: map passes; field and library each have one
failure. Full hosted green remains open.


Native Files viewport candidate `7b36a5d` now passes fifteen distinct local UI
workflows across the fresh and final runs. The first fresh native phase fails
two real-location checks because the private helper granted permission before
first install; its overall bundle is not green. After matching CI's
install-before-grant ordering, all 316 native cases execute with four opt-in
skips/no failures and the final backup/PDF/background UI cases pass. Home's
actual journal grows from 3 to 6 before foreground activation. Release and eight
harness checks pass; screenshots inspected and final parent exits 0 naturally.
Full hosted run 102 (40438839779) is confirmed live on `7b36a5d`. Full hosted and physical
checks remain open. [Exact evidence and limits](ci-field-ui-activation.md).


## watchOS marker artwork follow-up

The watch map now shares the phone marker renderer rather than replacing
mission-task paths with named text badges. It preserves directional rotation,
upright S/G/C badges, basic affiliation frames, echelon artwork and imported
shapes/characters. Native utility glyphs retain system rendering differences.
[Android source comparison, native bitmap checks and paired screenshots](watch-symbol-artwork.md).
The subsequent tactical drawing milestone below closes decorative path/area
rendering. Watch alerts/background guidance and phone offline-pack/terrain
transfer remain implementation gaps.


## watchOS tactical control-measure drawing

All 30 phone tactical graphic drawings now compile for watchOS rather than
reducing field graphics to plain polylines/polygons. Actual MapProxy coordinates
plus nearest-world unwrapping retain bends across the date line; continuous
camera updates keep decoration aligned during pan/zoom. The transparent layer
keeps gestures, native Legal attribution and the fresh own-location marker
available. Quiet-inside fences, L/R/BS lanes, tracks and TAK remain their
separate layers. [Source comparison, six native checks and paired screenshots](watch-tactical-graphics.md).
Phone offline/terrain transfer and independent watch alerts/background guidance
remain implementation gaps; physical rendering/battery/resource checks remain
open. Full hosted102 has new field/map UI failures under investigation.


Hosted102 (`40438839779`, `7b36a5d`) is terminal with five UI failures: ordinary
and protected backup filenames, protected-GPX filename, decimal Go-to activation
and target activation after real fix recovery. Both PDF workflows pass.
[Failure trees and artifact locations](ci-field-ui-activation.md) define the next
iOS corrections. Full hosted green remains open; the watch milestones above
do not close that gate.


## Hosted102 follow-ups: Files and navigation target activation

Native Files now waits for an attached, settled presenter and uses a complete
full-screen UIKit export, with bounded cancellation/retry. Navigation target
choices use native scrolling rows and apply after dismissal/current-source
checks; Cancel and save failure retain the saved target. Chooser/header
military glyphs and grouped written MGRS follow the Android target-selector
presentation, while retaining the existing iOS precision preference. Go-to
UI verification requires acknowledged segment selection.

Eleven export integration cases and 13 distinct UI workflows pass across
separate follow-up runs, including all five hosted102 failures and actual
GPS expiry/recovery. Final device Release and eight harness checks pass;
screenshots and an independent Android NGA grid reference are inspected.
[Exact scope and artifacts](ci-field-ui-activation.md). Local iOS 26.2 build 23C52
remains separate from hosted 23C54/Xcode 26.6; full hosted green, physical
providers/iPad, dense targets and physical marker VoiceOver checks remain open.
The later marker-description follow-up fixes the known hidden-fallback label. The whole parity goal remains active.


### Quiet-boundary worker persistence — 27 October 2026

Ordinary perimeter saves/deletes and monitor start/off checkpoints now validate,
encode and stage off Main with one serialized publication gate. Stop still turns
off GPS and alerts immediately; a late pending start cannot resurrect them.
Confirmed edits/restore retain their accepted intent across view dismissal, while
source checks preserve external replacements and stale delete confirmations keep
newer edits. Draft dismissal is tied to the same visible drawing. Quiet-inside
exit/reentry and separate route guidance policies are unchanged. See
[boundary persistence evidence and limits](boundary-persistence.md). Scoped native
validation passes 69 cases and all four actual simulator boundary workflows,
including background exits and durable night edits/deletion. Screenshots inspected;
phone/watch/widget unsigned device Release and eight harness checks pass.
The owned simulator/feed are off.
Full hosted103 on bc52ed8 remains a separate live gate.


### Marker accessibility matches the artwork — 27 October 2026

Imported MilGPS shape/character now overrides the hidden fallback in the iOS
target chooser/header, map annotation value and library row, and in watchOS
map/scene descriptions. NATO affiliation follows its actual catalog key; task
paths omit echelons they do not draw. Shared descriptions preserve explicit
unknown keys and spoken punctuation. All 509 core cases pass, including all 157
imported combinations, all 496 unit keys/echelons and a real snapshot-codec round
trip. [Exact scope and remaining physical checks](marker-accessibility.md).
Seven native symbol checks and all five target UI workflows pass, including exact
day/night chooser/header/map/library description checks. Screenshots inspected;
phone/watch/widget unsigned device Release and eight harness checks pass. The
owned simulator is off. Full hosted103 still runs on
the preceding bc52ed8, so this candidate and boundary b270cc9 remain local.


### Ordinary preference persistence and visible failures — 27 October 2026

Settings now capture/coalesce immutable snapshots and encode/stage off Main.
Only the latest revision can publish; failures keep prior bytes/session choices
and expose retry on main screens and a pinned settings notice. Done drains the
accepted attempt without trapping the user in Settings on failure. Staged backup
restore preserves newer edits, checks source changes and supersedes older pending
writes/errors; local Live Activities consent remains separate. Full native
validation runs 331 cases with four opt-in skips and no failures. See
[settings evidence/limits](settings-persistence.md). Nine distinct UI workflows
and the focused final night-label rerun pass, as do final device Release and eight
harness checks. All owned devices/feeds are off. Hosted103 stays on bc52ed8:
map passes; field integration/UI, fix expiry/recovery and GPS course/speed pass,
but boundary inserted-point movement fails. Library also completes successfully;
hosted103 is fully terminal. The failure
requires a gesture follow-up; local persistence success does not close it.
