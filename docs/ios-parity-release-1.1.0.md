# Remaining parity with Android release/1.1.0

Reference: `Artemis2028/gridfix` branch `release/1.1.0`, commit `482b417`,
24 October 2026. This inventory supplements the earlier 1.0.4 milestone notes.
It is not a claim of full Android parity.
The release branch was rechecked through GitHub on 28 October and still points to this commit.
For the current open work, use the [short gate ledger](parity-open-gates.md).
The long entries below retain historical failures and “next” notes; they are
not all still-open gaps. Sparse settings restore and paired Wear named-limit
Data Layer delivery are already verified; independent wrist guidance is not.
Current pushed checkpoint: c712229 (28 October) includes all held storage,
map chrome, export focus, filename, naming, marker-label and TAK-sheet changes.
Full hosted111/run40767120285 is queued on that exact head; no full hosted pass
is claimed. Hosted110 is terminal before this push. The one-minute handoff
checker remains active, and all local parents/simulator feeds are terminal/off.
Latest requested UI work: [automatic names and compact marker labels](automatic-names-and-marker-labels.md)
now covers waypoints, military units, map/library routes, graphics and generated
route points. Custom names/IDs survive regeneration; number reservations and
stale-edit rebasing are tested. TAK fills its sheet without gray side gutters.
557 core and357 native cases (four opt-in skips/no failures) pass, along with
ten final drawing/military/route/TAK UI workflows. Current unsigned phone/watch/
widget Release and ten harness checks pass; screenshots were inspected.
Long import names now wrap in a selectable full-filename header, including the
extension. The real Files export/import UI workflow passes with a92-character
unbroken filename; its screenshot and current phone/watch/widget Release were
verified. The system Files search field still scrolls horizontally.
Latest hosted repair candidate: [field export focus dismissal](hosted110-field-repair.md)
clears keyboard focus before closing the naming sheet. Both previously failed
export workflows and full-display map day/night/landscape checks pass locally;
phone/watch/widget device Release passes. Hosted confirmation is still required.
Latest UI follow-up: [compact map chrome](map-chrome-2026-10-28.md) replaces the
upper-right cluster with a bottom-right animated rail and a grid disclosure card.
Map details include selected-format lat/lon and UTM; redundant settings copy is
removed. Day selected-tab contrast is repaired. Scoped validation is recorded
there; full current-source hosted confirmation remains open. Hosted110 is now
terminal: map47/library59 pass; field exceeds its two-hour job allowance with
Files/export failures and skipped dedicated background suites.
The29 October source audit confirms the newer Android missing-key settings
restore behavior was already implemented in0d84a55. All production restore entry
points retain key presence; existing core/native tests pass. It is not an open
gap. See [settings-presence audit](settings-presence-audit.md).
Latest held storage milestone: [on-demand saved-track reads](track-on-demand.md)
now cover normal startup, retry and recorder entry points for validated references.
551 core cases pass; the full356-case native suite has four opt-in skips/no
failures, with final affected-native and cold-map checks after cleanup hardening.
Seven distinct UI workflows pass across the scoped bundles. Receiptless/v1
fallback and physical profiling remain open. These commits remain local;
hosted110 validated the earlier98c5c17 source with the partial outcome above.
Latest resume checkpoint,28 October: the preserved20-case native Files regression
passes on iOS26.5. Both backup/saved-log workflows and both final active-course
cases pass across the scoped resume bundles, including largest-night end/restart
reachability. All local parents are terminal and the owned simulator is off.
Hosted109 is fully terminal with map success, one field UI failure and three
library UI failures plus finalization timeout/artifact failure. The same draft
PR is being updated with all held source and the [109 repairs](hosted109-repairs.md);
current-source full hosted confirmation remains open. Earlier live/paused
checkpoints below are historical. The one-minute Claude checker is active again.
The user also requested the subsequent development work: see the
[25 October Android audit](android-overnight-2026-10-25.md) for navigation
lanes, protected backups, map-button preferences, fixes and the experimental
TAK branch. Those additions are tracked separately from this pinned release.
The first [navigation-lane UI and guidance integration](navigation-lanes.md)
now includes optional lane backup/restore and shared screen/text/PDF leg limits;
read-only phone guidance and a separate TAK watch scene are implemented; Android 4db6b21 startup/cue switches
are now implemented. It does not replace the separate quiet-inside perimeter.

Current validation checkpoint, 27 October: **hosted107 is green** on
`02d67f611070a6006a9e4ef0d2cc1c505de3bfa0` (run40496657566).
Field passes346 native cases (four opt-in skips),36 main UI cases (five
opt-in TAK skips), real-fix recovery, GPS course/speed, five background boundary
cases, automatic background route following and fourteen practice cases.
Map passes41 UI cases; library passes52 UI cases. All jobs pass518 core tests.
The earlier activation failures pass on the hosted runtime. All three artifact
digests and representative captures are verified. This validates that pushed source, not full physical parity.

Subsequent local follow-ups below cover accessible waypoint cards, cached
practice folder eligibility, complete finished/active split lists, large-course
missing-checkpoint validation and recording-handoff work. The latest local
core suite passes532 cases; scoped native UI, screenshots, final device Release
and ten harness checks are recorded with each milestone. Hosted108 on7fbeab5
is terminal: map passes; two field activation cases and one largest-night course
visibility case fail. Dedicated field background checks were skipped after the
UI failure. Later local live-completion, write-source, orphan-maintenance and
pace-entry work is outside that hosted source. Repairs are being validated;
no live job is cancelled or duplicated.

Local saved-library follow-up, 27 October: worker reads now retain source
metadata and validate it again before publication. Index replacement, a new v2
index during legacy reading, and a library appearing after an empty read cause
at most three shared worker attempts, then a visible failure. Failed reads keep
the saved files and refuse edits/exports/false empty point reads. Both library
screens offer an explicit retry; healthy stores are never reset. Empty-library
prompts are suppressed while reading or after a read error. This candidate
passes 518 core tests (including seven new source-change/retry regressions),
the unsigned phone/watch/widget Release build and eight harness checks.
Both native day/night recovery workflows now pass: an unreadable source stays
unreadable after retry; repairing the synthetic source alone does not publish
it; retry then recovers the named route and two-point track without restart,
and both survive relaunch. The primary error/retry is above the list so an
otherwise empty library cannot hide it. Four display-level screenshots were
inspected. The repair control exists only in the explicitly enabled DEBUG
synthetic fixture. An initial night run exposed automatic List-row activation
of both fixture buttons; borderless hit handling fixes it, and both final tests
pass. Bundles: `/tmp/mgrsgps-field-read-ui.xcresult` (initial failure retained)
and `/tmp/mgrsgps-field-read-ui-final.xcresult` (both pass). Final Release log:
`/tmp/mgrsgps-field-read-recovery-final-release.log`. All local parents ended
naturally and the single owned simulator/fake feed is off. This does not make
finished logs lazy, detect every in-place external write, or protect later
writes from all external changes. Android release/1.1.0 TrackRepository keeps
metadata and point logs separate; large-library startup costs remain open.
The product display name is **MGRS GPS** on phone and both watch platforms;
verified in the iOS/watchOS project settings and Android/Wear resources.

Accessibility library follow-up, 27 October: the real global
AccessibilityXXXL setting exposed truncated Waypoints/error/retry/library labels
that ordinary recovery tests did not detect. At accessibility sizes the whole
library workspace now scrolls, with lazy record rows in that same scroll
container; ordinary sizes retain the separate scrolling record list. The
heading, action controls, route-library label and counts stack/wrap, with bounded
search/action artwork and a shorter search prompt. Two largest-text recovery
workflows now exercise day and night, including retry after source repair,
saved-track access and relaunch. The initial large-text bundle
`/tmp/mgrsgps-field-read-ax.xcresult` retains the clipped UI evidence. The first
layout bundle `/tmp/mgrsgps-library-ax-layout.xcresult` retains a test reveal
failure: dragging blank edge space did not scroll the content. The corrected
native content drag is used in the final workflow; no data assertions were
removed. Full-app accessibility, spoken VoiceOver and physical readability
remain separate gates; large waypoint-card action layouts still need wider
coverage. Startup still eagerly validates saved logs; no lazy-load or orphan
cleanup implementation is claimed by this UI milestone.
Final validation: all five workflows in
`/tmp/mgrsgps-library-ax-scroll-final.xcresult` pass (ordinary day/night recovery,
largest-text day/night recovery, and ordinary 5,000-waypoint/1,000-graphic
search/grid-selection/night cards). Screenshot review then found a truncated
native large sheet title; accessibility sizes now use the native inline title.
The subsequent `/tmp/mgrsgps-library-ax-title-final.xcresult` passes and its images
show the complete title. The recording icon is bounded to 22 points after
largest-text review showed it outgrowing its control; the final
`/tmp/mgrsgps-library-record-icon-final.xcresult` passes with the icon contained.
Final unsigned phone/watch/widget Release
(`/tmp/mgrsgps-library-record-icon-release.log`) and eight harness checks pass.
Key full-display day/night/large-text screenshots are inspected. Repeat runs
are not counted as extra distinct workflows. All owned simulators/feeds are off
and all local parents ended naturally. The wider core remains at its previously
validated 518 cases; no new core behavior is part of this layout change.

Hosted106 field job `122129976193` is terminal with one failure in
`OrientationWorkflowTests.testQuickOrientationControlsAreAvailableAcrossMainScreens`
at line 17. Its 36 UI cases include five opt-in skips and one failure; dedicated
fix/course/boundary/route/practice steps are skipped. The native failure hierarchy
shows a New folder sheet after the orientation shortcut was tapped. Artifact
`12729019595` (401,938,844 bytes) is retrieved, SHA-256 verified:
`a3737ca882192cfc1b72c1a355c5c3757c24524df1c1976d4a05ffb7744ee5c0`.
Archive `/tmp/mgrsgps-ci106-field.zip`, extracted `/tmp/mgrsgps-ci106-field`;
native video and failure hierarchy are inspected. This new activation failure
remains open, not attributed to iOS limitations. Library/map jobs are still live
on pushed `7965445`; the saved-read and accessibility-library candidates remain
local to avoid cancelling that run.

| Area | Implemented on iOS | Still missing or incomplete |
| --- | --- | --- |
| Coordinates/position | Validated MGRS/decimal entry and UTM readouts, units, north reference, WMM, precision/accuracy gates, spherical waypoint projection with saved/current/entered bases, readable phonetic callout, native position/waypoint QR, persisted USNG naming and labelled entry, native Auto/Portrait/Landscape/Flipped controls, compact landscape Position layout, Android age/accuracy/trust labels, screen-relative fresh compass, Android GPS-course source/fallback rules, speed readouts and selected-target visual steering | Physical receiving-camera QR, compass and worn-device checks |
| Military symbols | Full Android curated catalog: 496 unit images, 20 tasks, 15 basic markers; search, affiliation/echelon/designation/type/rotation editing, imported MilGPS appearance editor, shared map/library/target-chooser rendering and night transform | Physical map readability at field distances; the catalog matches Android rather than the entire MIL-STD specification |
| Tactical graphics | All 30 Android control measures, doctrine rendering, map drawing, draggable points and segment handles, metadata, show/visibility/delete, day/night labels; worker-prepared archive edits | Physical field readability and very large-library performance |
| Routes | Waypoint-based and map-based route editors, waypoint snapping, draggable bends, numbered legs, route cards, worker-staged stable generated waypoint ownership with source/cancellation guards and visible errors, GPX, automatic following, durable staged interactive target selection, failure-aware checkpoint transitions and mixed library batches | Full hosted confirmation and physical long-route/readability checks |
| Navigation | Target metrics, relative steering readout, Android guide settings/policy, arrival cues, ordered checkpoint advance, pause/resume, worker-staged runtime session/target saves with source/intent/cancellation guards, background route GPS/milestone notifications; post-release checkpoint/route lanes with separate drawn/linked limits, library/map editing, early warnings and crossing-notification requests | Physical direction-pattern/locked-screen crossing validation; continuous Android-style locked-screen steering haptics cannot be promised on iOS |
| Boundaries | Editable perimeter and draggable bends, quiet inside, confirmed exit/reentry handling, background location and notification requests | Physical locked-screen alert validation; Android re-export drops the optional iOS-only quiet-boundary section |
| Maps/offline | Android raster catalog/key gating, USGS area download/resume, raster MBTiles, grid/shading, elevation caching/downloads and contours; ruler/area measurement and save-as-area; map lasso with freehand/corner selection, highlights, explicit Hide and confirmed Delete; persistent map-button visibility with active escape controls and coordinate Go to; day/night leave-map completion and offline relaunch regression; worker-coalesced camera/preferences with failure/retry and consistent offline network policy; atomic area Rename, cache-bypassing Update with persistent refresh retry, stored tile counts/size/update date and overlap priority | Broader full-app text-size and physical lasso/offline/storage-pressure validation; polar UTM measurements are labeled as extrapolated |
| Terrain visibility | Elevation/slope readouts, Android LOS/curvature and uncertainty policy, route profiles/charts, 1/2/4 km day/night viewsheds, offline DEM sampling and cancellation | Physical terrain comparison, outdoor legibility and battery validation; vegetation/structures are outside the terrain model |
| Waypoint library | Coordinates, cross-section search, persisted favourites, distance/name/newest sorting, mixed waypoint/graphic/track selection, visibility swaps, confirmed batch deletion, folder creation/rename/merge/remove, map focus and local persistence; cached background search/order with generation-safe mixed selection; durable worker-prepared map/library editor and ordinary favourite/visibility/folder/mixed-batch saves, visible failure/retry, first-target selection and unreadable-file protection; compact-height phone library controls, staged folder action choices; explicit retry, preserve/share and confirmed archive-before-fresh recovery with retained history | Dense-map rendering and wider accessibility/performance profiling; physical large-library storage checks; physical field validation and storage/interchange limits below |
| Tracks/practice | Background recording/recovery with worker-staged durable finalization, independent immutable point logs and atomic index, legacy migration, saved tracks/overlays, moving folders, temporary viewing, confirmed deletion, reverse backtrack routes with endpoint-preserving simplification, GPX, random/folder practice courses, checkpoint navigation lock, strict arrival scoring, persisted pause/recovery and split/results history with worker-staged course progress, random checkpoints, target locks and result finalization, stable retry and duplicate-free recovery; bounded worker cleanup of aged unreferenced installed logs with pending-save leases; compact result summary and complete native scrolling split log with first/last viewport controls | Saved-log eager validation/read cost; physical storage-pressure/cleanup, dense/very-large-library profiling and very-long-course field use; physical course/guide validation |
| Interchange/sharing | GPX/CSV/GeoJSON/KML/KMZ/ATAK import preview and native Files export, password-protected single-file export/import and track GPX, Android-compatible retry IDs and ordered additive persistence, document associations, route-card text/A4 PDF preview/Files sharing, Android streaming ZIP backup contract and optional compatible password protection, guide preferences in backup, bounded ZIP64 metadata/descriptor support, coordinated mapped reads, cancellable background backup preparation, revision-checked staged backup/interchange writes and confirmed-import progress; cancellable worker-prepared library/single-track exports | Very-large-library read/export/rendering profiling and full hosted confirmation; physical large-library performance checks; physical provider/Open In and ATAK client validation, storage-pressure validation and physical PDF sharing/printing; active sessions/offline maps remain separate from v1 backup; optional quiet-boundary geometry extension and Android compatibility fixtures pass |
| Field tools | Resection/intersection worksheets, per-point north-reference conversion, safe ray solver and angle-of-cut warnings; waypoint projection; local/Zulu sun/moon planning with date controls; TN/GN/MN declination diagram; map-menu course/LOS entry points; offline seven-topic Field Reference from Settings and Map tools | Physical field/compass/model comparisons; astronomy retains Android's approximate model and 24-hour local-day moon-scan policy |
| Live TAK (user follow-on) | Native CoT/TCP/mutual TLS, PKCS #12/DER/PEM CA import, explicit CA/name/pin verification and trust reset, Keychain credentials, default-off position/folder sharing, presence/pings/reconnect, per-server offline withdrawal journal, separate remote layer/list/map focus; real iOS ↔ Android positions, shared point/drawing, deletes and reconnect confirmed through local OpenTAKServer; shared 14-event Android fixtures and hosting-kit CA bag compatibility; native device-key certificate sign-in with explicit bootstrap trust, ATAK link entry and transactional credential replacement, client certificate UTC dates/fingerprint/30-day notices and manual renewal preserving active sessions/sharing; separate bounded read-only remote scene on both watches | Live renewal verification and crash-time orphan-key recovery, unsupported certificate-container forms, official TAK Server/ATAK/iTAK and sustained reliability checks, Wear paired named-lane crossings and physical background checks; see [evidence and gaps](tak-server-interoperability.md) and [certificate sign-in](tak-certificate-enrollment.md) |
| Release | Unsigned simulator/device builds, automated tests and draft PR; native menu/presentation and hit-target repairs; Android launcher artwork for phone/iPad/watch with runtime icon evidence | Current-source full hosted confirmation (107 passed the earlier baseline), privacy/distribution metadata, StoreKit/purchases, signing, physical field validation, TestFlight/App Store release |

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


### Reliable point dragging and live line feedback — 27 October 2026

Boundary and route handles now own a native hold/drag transaction with current
draft/source guards, grip preservation, viewport-interaction restoration and
transient line previews. Release publishes once; cancel/reuse/source replacement
restores the point. Midpoints retain direct insertion and accurate accessibility
titles. The formerly failing workflow now requires three moves without a
preparatory tap in day/night, then viewport panning without changing the geometry.
Full native validation runs 338 cases with four skips and no failures, followed
by all ten boundary/graphic UI workflows passing. Actual preview recording and
screenshots inspected; eight harness checks pass. See
[drag evidence and limits](boundary-vertex-drag.md). Final device Release passes
and all owned devices/feeds/captures are off. Hosted verification on the new
source remains open.

### Map preferences, offline policy and save failures — 27 October 2026

Compared Android release MapPrefs DataStore behavior. iOS now stages/coalesces
map choices and debounced camera saves off Main, refuses stale worker publication
or external replacement, and keeps offline-only UI and runtime policy together
when disk writes fail. Separate readable failure/retry notices remain available
in Map layers and the main app. Camera normalization covers repeated map worlds
and Mercator latitude/zoom limits. Existing map pack formats and catalog remain.

All344 native cases pass (four opt-in skips), including six new map persistence
cases; four distinct map UI workflows pass, with day/night failure/retry/relaunch
repeated after the final accessibility identifier and tap-target changes. Initial
new UI lookup failure and its native hierarchy evidence are retained. Final
screenshots inspected; phone/watch/widget device Release and eight harness checks
pass. See [map settings evidence and limits](map-preferences-persistence.md).
All local parents finish naturally; owned phone/feed off. This candidate stays
local while hosted104 runs on42def16; no full hosted green or full parity claim.

### Watch route previews retain phone leg references — 27 October 2026

Both watch map packets now retain exact source ordinals from the existing
budgeted simplifier, including repeated coordinates. Simplified segments display
original leg ranges instead of missing or misleading sequential numbers. Named
ranges are available in map info; legacy simplified scenes suppress numbers.
Ordinary iPhone numbering and quiet-inside monitoring remain separate.

All511 core and345 native cases pass (four opt-in native skips), plus the actual
phone route draw/drag/edit/relaunch workflow. Phone/watch/widget device Release,
eight harness checks,458 Android phone/42 Wear unit tests, Android Debug/Release
builds and Wear Release lint pass. Paired40mm Apple context revision131 contains
the exact retained ordinals; day/night map captures and standalone Wear cache/
map-info checks inspected. Prior watch preferences restored; all owned devices
and feeds off. [Evidence and limits](watch-route-leg-ranges.md). The iOS commits
remain local while hosted104 is running on42def16; full hosted/physical/watch
navigation and TAK verification gates remain open.

### Hosted104 is terminal — four native Files workflows fail

Run40460836747 on42def16: library succeeds, field has three Files export/reopen
failures and map has one lane-backup export filename failure. Dedicated real-fix,
course, boundary/route/practice steps are skipped. The boundary drag repair is
still missing a full hosted gate. Videos and native hierarchy show the export
picker's missing filename accessory; one saved GPX icon stays unactivated in
import. [Exact terminal evidence and candidate](ci-field-ui-activation.md).
0ca082c/cf9e4b5 remain validated local candidates, not hosted results. The new
filename/provider flow and native list activation are under local validation;
no full green or parity-complete claim.

### Accessibility-size audit finding — 27 October 2026

An actual global AccessibilityXXXL launch makes the map HUD and floating control
icons overflow the viewport; this is a real app layout gap, not an iOS platform
limit. The Settings UI helper can also activate Haptic navigation while trying
to scroll to a reference row. Recordings retained at
`/tmp/mgrsgps-reference-large-map-failure.png` and
`/tmp/mgrsgps-reference-large-settings-failure.png`. Full-app accessibility-size
navigation/readability remains implementation and validation work. A separately
scoped DEBUG reference-only Dynamic Type stress check does not close that gap.

### Reliable filename/provider flow and offline reference — 27 October 2026

The export candidate8c4e1ba supplies native styled filename entry before Files
location/provider selection, including PDF Save. Existing exact filename,
complete-record/password/restore assertions remain; native list rows avoid
hosted icon activation. All19 existing export/recovery workflows now validate
across broad/final-source bundles; the two intermediate PDF/ShareLink test-
alignment failures stay recorded. Native346 cases pass (four opt-in skips),
final device Release/eight harness checks pass, and day/night images are inspected.
[Filename/provider evidence](export-filename-provider-flow.md).

Android's seven-topic offline Field Reference is now ported, with phonetic
alphabet/digits, radio grid, grid precision/accuracy, pace/conditions, contours,
north references and military affiliation/echelon reminders. It opens from
Settings/Map tools in native day/night cards. Both entry/topic workflows pass;
the isolated page-level largest Dynamic Type check passes with a single-column
alphabet. Global largest-type map navigation/HUD overflow remains open. Combined
scope:22 distinct UI workflows, not the sum of repeated runs. [Reference evidence
and exact large-text scope](offline-field-reference.md). Local parents terminal,
owned devices/feeds off; no TAK infrastructure or wire change. Full new hosted
confirmation and the other implementation/physical gates remain required.


### Map accessibility layout candidate — 27 October 2026

Local c057d9a replaces the overflowing fixed map HUD/icon deck at accessibility
sizes with a full centre-grid summary, scrolling details and native Map actions.
Landscape active-tool panels scroll below actions; boundary/graphic/lane/ruler
rows stack, lane roles use a menu and recording-banner icons keep explicit sizes.
Normal layouts, hidden-tool/active-escape policies and quiet-inside behavior remain.
Android release MapScreen tool/landscape policy was compared.

Final-source346 native cases pass (four opt-in skips), device phone/watch/widget
Release and eight harness checks pass. Eight distinct UI workflows pass across
bundles: three ordinary map-tool cases, route draw/edit/save/relaunch and four
global AccessibilityXXXL cases for day/night details/layers, landscape reference
access, ruler/boundary exit and recording finish/discard. Intermediate scrolling
failures remain recorded. Display-level landscape screenshots and both landscape repeats pass; the
app-region capture had cropped using portrait bounds. A stronger complete-button
check exposed focused name entry shrinking the boundary panel. Native keyboard
Done and interactive scroll dismissal are added; the final typed-name/dismiss/
fully-visible-Cancel test and final device Release pass. Screenshots inspected.
[Exact scope and artifacts](map-accessibility-layout.md). Full-app Dynamic Type
and physical spoken VoiceOver remain open; this does not claim full parity.

The candidate stays local while full hosted10540472724924 on d9e7aba remains
confirmed live. No CI run was cancelled or duplicated. Real enrolled TAK,
independent watch guidance, physical and distribution gates remain unchanged.


Hosted105 partial outcome: map122083457114 and field122083457138 are terminal
failures on d9e7aba; library122083456715 is still confirmed live. Map fails
landscape area readiness, night layers reopening and protected-KML password-sheet
activation. Field fails large-GPX native picker reopening and field-fix Resection
activation. Logs retrieved; artifact metadata12722295252/12722860249 recorded,
archives not yet retrieved/verified. These five failures are open triage, not
platform limitations or cancelled jobs. No dedicated background-gate success is
claimed. The accessibility changes remain local while library runs.


### Hosted105 repair validated locally — 27 October 2026

0b36f46 fixes the SDK camera/double-tap policy order and restores saved tap
states after vertex drags. f4b50c0 commits one choice per sheet and distinguishes
protected format identifiers. f589974 acknowledges actual native controls and
picker dismissal. Original fast-tap geometry, exact file/count/password checks
and saved coordinates remain. All six failed hosted workflows pass locally.
Across the final/source-compatible bundles24 distinct UI workflows pass, plus
346 native cases (four opt-in skips), final phone/watch/widget device Release
and eight harness checks. Original105 failures, intermediate configuration and
assertion failures stay recorded; corrected real background crossing, camera
zoom restoration and drag/lasso checks pass. Screenshots inspected, test-owned
simulator and feeds stopped. [CI evidence](ci-field-ui-activation.md).

The full new hosted gate remains open. Android release/main/claude-tak refs are
unchanged. No server GO/round or TAK/watch wire change; real enrolled exchange,
independent watch guidance and physical/distribution checks remain open.


### Hosted106 map validation and orientation activation follow-up

Run `40486646955`, source `7965445cf710c7690ca26da4bfeef3c9c23daf71`:
map job `122129976267` passes all 41 UI cases, including the formerly failing
landscape area, night offline download/reopen and protected KML workflows.
Artifact `12730601284` (431,483,026 bytes) is retrieved and SHA-256 verified:
`53832861534588b196e98fc9b5288d29f6d953062708fdc48ebfde7691c703c6`.
Native landscape area, night offline/reopen, protected-password and terrain
viewshed images are inspected from `/tmp/mgrsgps-ci106-map`. The library job
remains live; the field failure above still prevents a green full run.

`/tmp/mgrsgps-ci106-orientation-reproduce.xcresult` passes both original
orientation tests locally. The hosted video and failure hierarchy show that a
coordinate-based selection of the plain native Orientation button reached
New folder. The local candidate uses that exact button's native `tap()` and
asserts the Screen orientation destination before testing the choice. It does
not retry a different action or remove any rotation/relaunch assertion.
`/tmp/mgrsgps-ci106-orientation-native.xcresult` passes both tests: actual pinned
Landscape/Flipped, relaunch persistence, Auto rotation, and every main-screen
shortcut with the saved Portrait assertion. Full-display landscape and final
Position images are inspected. The product source is unchanged by this test
adjustment; it retains the final Release validation of `79e06de`. All local
parents ended naturally, and owned simulators and fake feeds are off. No live
CI was cancelled or duplicated. Native hosted confirmation remains required.


### Hosted106 completed: library hit-point correction

Library job `122129976070` is terminal: 48 UI cases, one failure in
`WaypointWorkflowTests.testNightModeKeepsSettingsAndWaypointEntryUsable`.
The Add waypoint button has a usable landscape frame (centre within the
844×390 window); the helper then unconditionally calls `isHittable` despite
having already accepted its frame. XCTest throws an invalid activation-point
failure at that redundant query before any tap. Only the fallback path now
checks native hittability; the successful frame path keeps its existing bounds
checks and coordinate tap. Editor appearance/cancel, saved name/grid, Routes &
tracks access, night opt-out and real rotation assertions are retained.

Artifact `12729149254` (607,909,561 bytes) exceeds the connector download cap and
was retrieved with the authenticated GitHub CLI. ZIP SHA-256 is verified:
`9f27a5340915c44bfc799e554dd44cb9f85b0dc8298d2f9bf6dc9652405651a4`.
Archive `/tmp/mgrsgps-ci106-library.zip`, extracted `/tmp/mgrsgps-ci106-library`;
video, native failure hierarchy and landscape control frames are inspected.
All three106 artifacts are now retrieved/verified. The two activation failures
are not reclassified as hosted passes.

`/tmp/mgrsgps-ci106-activation-final.xcresult` passes all three regressions:
both orientation workflows and the full night-landscape waypoint workflow.
Its landscape and coordinate-entry screenshots are inspected. The change is
test-only; the final product Release of79e06de and 518 core/eight harness results
remain applicable. No Release re-run or wider native-unit claim is invented for
this helper-only change. All local parents ended naturally and the single owned
simulator/fake feed is off.106 is fully terminal; publishing the held candidate
can now start a new full run without cancelling live work. Full hosted107 and
dedicated real-fix/course/boundary/route/practice gates remain open.


### Full-width accessible waypoint cards, 27 October

The actual global AccessibilityXXXL setting with5,000 waypoints/1,000 graphics
exposed a point-summary button only114points wide and845points high, taller
than the phone window. The grid was squeezed between its symbol and action
buttons. The failed native reveal and hierarchy are retained in
`/tmp/mgrsgps-waypoint-card-ax-before.xcresult`; no initial screenshot claim is
made for that failure. At accessibility sizes the name, complete MGRS, folder
and distance now use the card width; the same symbol and menu/navigation
controls form a separate row. Ordinary sizes keep the horizontal layout.
A first night test found that the last actions could not scroll clear of the
opaque tab bar and that the plain image menu exposed only its tiny glyph as a
hit target. The workspace uses the existing FieldTabBar control-height reserve
as bottom scroll padding at accessibility sizes, and the44point image frames
now define rectangular hit shapes. The failed first night result remains in
`/tmp/mgrsgps-waypoint-card-ax-final.xcresult`.

All three workflows in `/tmp/mgrsgps-waypoint-card-clearance-final.xcresult`
pass: the existing ordinary large-library search/grid-selection/night-card
workflow, and largest-text card workflows in day/night. They assert a full-width
summary, a44×44 menu control, the actual Edit destination with the saved name,
and navigation to the exact selected target. Final day/night screenshots show
the full five-digit easting/northing groups. The existing night-landscape
create/edit/cancel/library/night-opt-out workflow also passes on this source in
`/tmp/mgrsgps-waypoint-card-landscape-final.xcresult`; its screenshot is inspected.
Four distinct UI workflows, not repeated runs counted again. Final unsigned
phone/watch/widget Release (`/tmp/mgrsgps-waypoint-card-clearance-release.log`)
and eight harness checks pass. No shared-core behavior changed;518core remains
the prior core validation. All local test/build parents ended naturally; the
single owned simulator and fake feed are off. Long-name/mixed-symbol cards,
VoiceOver and wider whole-app accessibility remain separate coverage gates.

This candidate stays local while all three107jobs run on02d67f6; a later push
must wait for authoritative terminal state. The one-minute Claude handoff is
unchanged and no TAK server GO, infrastructure, wire or credential changes are
part of this waypoint-only layout work.


### Practice-folder caching and checklist audit, 27 October

Android `release/1.1.0`482b417 `CourseDialog.kt` lines73–75 remembers eligible
folders by folder and waypoint values. iOS previously scanned all points from
its body whenever folder mode was selected, including GPS-driven active-course
redraws. `PracticeCourseView` now keeps eligible folder names in view state and
refreshes them only on waypoint/folder publications. It retains the same
minimum of two points, includes hidden points, preserves saved folder order,
and leaves actual checkpoint selection/order to the existing practice session.
No absolute CPU/battery improvement is claimed without physical profiling.

The new large-library workflow uses5,000 waypoints/1,000 graphics, chooses
Folder099 and starts all50 checkpoints. It asserts CP1 of50 and Point0099 first,
so favourite Point4999 cannot silently reorder the course. Ending keeps the
original5,000/1,000 record counts. That workflow and the existing two-checkpoint
persisted lock/relaunch/end workflow both pass in
`/tmp/mgrsgps-practice-folder-cache.xcresult`; full-display course images are
inspected. Unsigned phone/watch/widget Release
(`/tmp/mgrsgps-practice-folder-cache-release.log`) and eight harness checks pass.
No shared-core behavior changed. All local parents ended naturally and the
single owned simulator/fake feed is off.

The checklist audit also inspected `FieldAppStartup`, `TrackRecorder.recover`
and `NavigationLaneStore`: saved settings/waypoints/maps/practice/navigation/
boundaries/TAK are prepared on the startup worker; recorder journal recovery
and lane-file reads already use their own workers. Generic remaining-startup
labels in the table were stale and are removed. Actual remaining costs include
eager finished-log validation, crash-orphan handling, dense rendering and
long-course progress/splits coverage. This is a scoped source audit, not a
claim of whole-app physical performance or all storage paths being audited.
The previous waypoint-card candidate and this course-cache follow-up stay
local while full107 runs on02d67f6. No active CI was cancelled or duplicated;
no TAK, server, watch-wire or credentials changed.


### Native complete practice split logs, 27 October

The course startup/Continue audit matches Android: Continue dismisses the
progress panel, while scoring and optional haptic guidance remain separate.
No startup/resume semantics changed. The audit found that completed result
splits were all instantiated inside one eager summary VStack. Totals and point
counts now remain compact in the summary, with an explicit View all splits
link to a native List. Every saved split remains present. First/Last controls
change only the viewport, and accessibility-size rows stack checkpoint/time.
The summary is an explicit accessibility container so its identifier does not
replace the split link's own identity. This also retains the existing summary
container used by the real-location completion workflow.

A DEBUG-only synthetic history fixture uses the existing supported 10,000-split
limit. Both native log workflows pass: ordinary day and actual global
AccessibilityXXXL night, reaching CP 1 and CP 10,000, returning to the first,
and reopening the complete log after a worker-loaded relaunch. The existing
real Core Location two-checkpoint scoring/summary/history workflow also passes
on the same product source and proper practice-location feed. These are three
distinct UI workflows, not a claim of scoring 10,000 physical checkpoints.
Initial `/tmp/mgrsgps-practice-log-native.xcresult` retains two accessibility-ID
failures (the new link inherited the summary identifier); its scoring test
passed. The explicit container correction passes all three in
`/tmp/mgrsgps-practice-log-container-final.xcresult`.

Final first/last day/night and live-scored summary screenshots are inspected.
Unsigned phone/watch/widget Release
(`/tmp/mgrsgps-practice-log-container-release.log`) and eight harness checks
pass. No shared-core/disk behavior changed, so no fresh core-suite claim is
made. All local parents ended naturally; owned simulator and practice feed
are off. Physical long-course scoring/battery checks and active-progress
profiling remain open. This follows held af90cfc/8aef669 and stays local while
hosted107 runs on02d67f6. No CI cancelled, duplicate started, TAK/server or
credential changes occurred.


### Large paused-course validation, 27 October

Missing-checkpoint membership now uses one Set per validation/pause-message
calculation instead of a linear search per checkpoint. Exact saved-list order,
uniqueness and remaining-checkpoint checks stay intact. Android
release/1.1.0 CourseNavigationPolicy confirms that any missing remaining point
pauses navigation; restored points resume without requiring completed IDs.
No pause wording, scoring threshold, timestamps or saved format changed.

All520 core cases pass in `/tmp/mgrsgps-course-missing-core.log`, including
the10,000-checkpoint paused save/reopen/restore/resume regression and malformed
missing-list original-byte/write-refusal checks. Twelve focused course cases
and eight harness checks pass separately. This is algorithmic validation, not
a physical long-course battery/performance measurement. No UI changed.

Hosted10740496657566 remains on02d67f6: map has completed successfully; field
main UI, real-fix recovery and GPS course/speed steps pass, with background
boundary testing in progress; library UI remains live. These are scoped step
results, not full hosted success. Newer local changes are not covered by107.

Final unsigned phone/watch/widget Release passes in
`/tmp/mgrsgps-course-missing-release.log`. All local test/build parents ended
naturally; no simulator or fake feed was started for this core-only change.


### Reachable active-course controls and complete recorded splits, 27 October

Android CourseDialog keeps target/time, ordered recorded splits and Continue/End
actions in one scrolling progress dialog. iOS previously placed every split
before those actions. Active runs now keep target/time and controls together,
with a link to the same complete native split List used by finished results.
The live destination observes the current run; its split arrays are computed
there rather than in the GPS-redrawn progress form. No split is capped/sampled,
no unfinished run becomes a result, and scoring/navigation lock behavior stays.

Two new UI cases pass in
`/tmp/mgrsgps-active-course-scroll-final.xcresult`: ordinary day and actual
global AccessibilityXXXL night. A DEBUG-only fixture seeds9,999 recorded splits
in a10,000-checkpoint unfinished course with its actual remaining checkpoint.
Both cases verify the current CP/target, reachable End control, first/last
recorded splits, retained progress after worker-loaded relaunch and confirmed
End returning to setup. Full-display day/night controls and last-split
screenshots are inspected. This does not claim10,000 actual location scores.

The initial `/tmp/mgrsgps-active-course-native.xcresult` passes the two existing
10,000-result-log workflows and real Core Location two-checkpoint scoring/
summary/history, but fails both new tests before their log checks: localized
10,000 grouping and offscreen root Practice activation. The next
`/tmp/mgrsgps-active-course-controls-final.xcresult` exposes the reveal helper's
assumption that the root has a native navigation bar. A native-root-aware
viewport fallback fixes that helper; exact progress, split, persistence and
End assertions remain. Five distinct UI workflows pass across these bundles;
initial failures remain recorded.

Final unsigned phone/watch/widget Release passes in
`/tmp/mgrsgps-active-course-release.log`; eight harness checks pass. No further
core change followed the520-case result in the preceding milestone. All local
parents finish naturally, and the owned simulator and practice feed are off.
Physical long-course scoring, wider live-update/performance/battery profiling
remain open. This follow-up is local while107 validates02d67f6; no CI run
was cancelled or duplicated, TAK/server/credentials changed.


### Recording finalization avoids duplicate full-log statistics, 27 October

Android TrackRepository.tracks reads metadata independently; finishTrack reads
points to calculate statistics. iOS still eagerly maps/hashes/summarizes saved
logs on its startup worker, so lazy library reads remain open. The audit also
found saveRecordedTrack unnecessarily summarizing the complete handoff before
FieldDataDisk.prepare repeats that required validation. The duplicate traversal
is removed. Journal finish statistics and full new-log validation before atomic
index publication remain. Exact-byte idempotent retries reuse validated logs;
different bytes under a saved recording ID are still refused.

All521 core cases pass in `/tmp/mgrsgps-recording-single-validation-core.log`.
The new test covers both direct and worker-prepared saves:250,001 valid points
followed by an invalid coordinate cannot publish or alter old index/log bytes;
a repaired retry saves exactly once and reopens complete. Existing long
interrupted-recording, checksum, missing-log and migration cases also pass.

Actual Core Location background-record/save/library/map UI passes in
`/tmp/mgrsgps-recording-single-validation-ui.xcresult`. The host observes the
same journal grow4→7 points while the app remains on Home, before reactivation.
The saved detail shows9 points/80m, and the recording/map captures are inspected.
Final unsigned phone/watch/widget Release
(`/tmp/mgrsgps-recording-single-validation-release.log`) and eight harness
checks pass. All parents end naturally; owned simulator/feed are off. No new
physical locked-screen/battery or lazy-read performance claim is made. Changes
stay local while107 runs on02d67f6; no CI/server/credential change.


### Hosted107 field/background and map gates verified, 27 October

Run40496657566 on pushed02d67f611070a6006a9e4ef0d2cc1c505de3bfa0
now has successful field122163714094 and map122163714387 jobs. Library
122163714264 is still running; the whole run is not yet green. The field job
passes518 core tests,346 native integration cases (four opt-in skips),36
main UI cases (five opt-in TAK skips), real-fix expiry/recovery (one), real GPS
course/speed (one), background boundary/drawing (five), automatic background
route following (one) and practice scoring/recovery (fourteen). Map passes41
UI cases, including military artwork, typed graphics, route editing, layers,
protected interchange, navigation lanes/targets and terrain analysis. The
previous orientation-shortcut failure passes on the hosted runtime.

Artifacts downloaded and SHA-256 verified before extraction:

- Field12734763542,574579765 bytes:
  `3d86aaf17656a24cb6d0b89fcd1476b659eed59a4fdb73b3e4158f8616b007a9`.
  `/tmp/mgrsgps-ci107-field.zip` and `/tmp/mgrsgps-ci107-field`.
- Map12734246031,420616775 bytes:
  `e5113f44f01280c28471ba1d5a7c758a963bf847a493c8f224c2c94c5139fe23`.
  `/tmp/mgrsgps-ci107-map.zip` and `/tmp/mgrsgps-ci107-map`.

The field archive exceeds the connector512MiB limit, so its authenticated
GitHub CLI download is verified against the same artifact digest. Hosted
boundary capture shows two exits, automatic route capture shows completion,
practice capture shows scored history/splits, and the map night viewshed
capture is inspected. These are simulator decisions/UI with synthetic fixes
and terrain, not physical buzz/compass/terrain-provider accuracy proof.

All newer local follow-ups af90cfc through1128971 remain outside107's source.
No active job was cancelled or duplicate run started. Library/full hosted
confirmation, the next-source full run, physical/watch/TAK and documented
implementation/performance gaps remain open. No local device was booted for
this artifact audit; completed download/extract parents have exited naturally.


### Written checkpoint grids and fully green hosted107, 27 October

Practice progress uses MGRS.parts.full with separated zone/square/easting/
northing groups, matching Android CourseDialog's written coordinate form. iOS
retains the user's precision instead of forcing Android's eight digits. No
coordinate conversion, saved coordinate or scoring behavior changed. Both
active10,000-checkpoint UI cases pass with exact `18S TD 26201 77156`, day and
global AccessibilityXXXL night, visible complete grid groups, recorded splits,
worker-loaded relaunch and confirmed End. Captures inspected in
`/tmp/mgrsgps-practice-written-grid-images`; passing bundle
`/tmp/mgrsgps-practice-written-grid-final.xcresult`. Final unsigned
phone/watch/widget Release (`/tmp/mgrsgps-practice-written-grid-release.log`)
and eight harness checks pass. No additional core change followed the521-case
result. All local parents finish naturally, simulator/feed off.

Hosted10740496657566 is authoritatively completed/success on02d67f6. Library
122163714264 passes52 UI cases with no skips/failures, joining the already
verified green field/map jobs above. The previously failed night-landscape
waypoint activation passes. Library artifact12734454892 is616891512 bytes;
SHA-256 `0654cbca9f589bce251352fbbb0626927897880e060e91e0703bb276d5734ef2`
is verified before extraction to `/tmp/mgrsgps-ci107-library`. Its archive is
`/tmp/mgrsgps-ci107-library.zip`; authenticated CLI download handles its size
above the connector512MiB limit. Night field-read recovery and protected-backup
restoration screenshots are inspected. All three artifact hashes now match.

The new accessible waypoint/course/log/recording follow-ups are ready for their
next full hosted run after this green source. This is not full physical/watch/
TAK validation or a release approval. No active CI was cancelled or duplicated.


### Follow-ups pushed; full hosted108 live, 27 October

Source7fbeab55f5dd875b997cc1b85d020563068a32c8 is pushed to the same draft
PR. All accumulated follow-ups through the written checkpoint-grid change are
included. Hosted107 completed successfully before this push; no live run was
cancelled. Full hosted10840508823942 is confirmed in progress on the new source:
library122205023151, field122205023505 and map122205023915. Its result remains
pending. New PracticeLogWorkflowTests is discovered once in the library shard;
no new UI class is silently omitted. All three107 artifacts have verified hashes.
The draft PR is rewritten around current behavior and scoped local/hosted
evidence. All local parents are reaped and owned devices/feeds off.


### Live recorded-log completion retains its run, 27 October

A new actual Core Location workflow reproduces a real issue in the newly
introduced active split screen. Opening the recorded log after CP1 then scoring
CP2 successfully saves history, but the destination changes to “This course is
no longer active.” Initial `/tmp/mgrsgps-live-splits-before.xcresult` retains
the failed40-second final-log assertion and hierarchy showing that text while
the root banner says Course complete. No destination assertion is weakened.

PracticeSession now publishes a transient completion containing the run ID and
result together. Summary callers still see the same result. The live split
destination can use only its own run's completed splits; new starts/dismissal
clear completion, and an unrelated/ended run stays unavailable. Saved files,
arrival rules, navigation locks, result retries and haptic feedback are unchanged.
Android's completion/result behavior remains the reference.

All33 native practice integration cases pass in
`/tmp/mgrsgps-live-splits-final.xcresult`, including a new identical-name/start-
time two-run ownership/clearance test and existing result failure/recovery. Two
real-location UI cases also pass there: the new live-log transition and existing
scoring/completion/history regression. Strengthened final transition validation
passes again in `/tmp/mgrsgps-live-splits-durable-final.xcresult`: wait for the
saved-completion banner, retain CP2, then Back/Done returns to exactly one
history result. Before/after full-display screenshots are inspected.

The test feed accepts optional host-log HOLD/ADVANCE/RELEASE markers with
matching-run tokens and a120-second expiry. The test holds real simulator fixes
at CP1 until the split screen opens, then moves to CP2. Normal alternating feeds
are unchanged; no in-app GPS mock or scoring call is introduced. Both marker
parser cases and the existing eight harness cases pass (ten total). The field
practice step supplies its own log path for this dedicated test; current108
uses the prior source and is not affected by this unpushed workflow change.

Final unsigned phone/watch/widget Release passes in
`/tmp/mgrsgps-live-splits-release.log`. No core change follows the prior521-case
core result. Parents naturally exit; the owned simulator and fake feed are off.
This follow-up stays local while full10840508823942 runs on7fbeab5; no active
run cancelled/duplicated or TAK/server/credential change. Physical and wider
watch/performance gates remain open.


### Saved-library writes retain their actual source, 27 October

A regression reproduced a lost update: an older store's prepared graphic edit
could replace a newer store's saved index. Android TrackRepository rename/
folder writes transform the current DataStore value within edit. iOS now keeps
the index/legacy source read by its store and checks it at the final atomic
publication under a short shared in-process gate. A stale edit/restore cannot
overwrite newer files. Failed staging removes only its own unique log files;
newer referenced logs survive. The visible error asks for reopening after a
source conflict. No saved format, additive-ID or record-order policy changed.

Exact-byte repaired sources may have new inodes. Worker-held metadata digests
allow those repairs to prepare again while a different source/deleted index
is refused. Hashing stays on read/preparation workers; final publication stats
and renames only. This does not claim a filesystem transaction against arbitrary
noncooperating external writers. See [publication contract](field-edit-preparation.md).

All526 core cases pass in
`/tmp/mgrsgps-field-write-source-final-core-verified.log`, including five new
cases covering stale prepared edits, direct/prepared restores and newer-track
log preservation/cleanup, legacy replacement, simultaneous live-store commits
and deleted-index refusal. Existing exact-byte repair and partial-batch
one-time visibility assertions remain and pass.

The initial `/tmp/mgrsgps-field-write-source-before.log` retains four failing
assertions demonstrating the overwrite. The first full core attempt retains
five failures; the first repair attempt retains three. Existing fault fixtures
that deleted the original index and removed a temporary directory without
restoring its bytes now restore the retained exact index before retry. This
preserves the intended I/O-failure test while testing the new source contract;
record/waypoint/selection assertions are unchanged. Initial native
`/tmp/mgrsgps-field-write-source-native.xcresult` retains these fixture failures
and subsequent unchecked array-index crashes; that parent ended naturally.

Final `/tmp/mgrsgps-field-write-source-final-native.xcresult` passes all347
native integration cases (four opt-in skips) and three UI workflows: night
route edit/visibility/delete/relaunch, typed graphic/track visibility/delete,
and actual background recording/save/library/map. The host sees the same
journal grow3→6 points while the app stays on Home; the saved detail shows
eight points/70m. Night route and recording images are inspected. Final unsigned
phone/watch/widget Release (`/tmp/mgrsgps-field-write-source-release.log`) and
ten harness checks pass. All parents reaped; owned simulator/feed off.

The older field-edit document's generic synchronous-UI backlog is corrected
to later worker-action milestones; compatibility core APIs remain synchronous.
Eager saved-log startup validation, orphan maintenance and physical profiling
remain separate work. This and the live-split fix stay local while108 runs on
7fbeab5; no active CI cancelled/duplicated or TAK/server/credential changes.


### Bounded abandoned-log cleanup after healthy startup, 27 October

Finished-save crash leftovers now have a maintenance path. Android's
StagedTrackFiles/TrackRepository separates created files from existing logs and
rolls back only its own files; iOS's uniquely named installed files can survive
process death before the metadata rename. A separate utility worker runs after
RootView's healthy field read, considering at most64 old unreferenced canonical
UUID `.txt` candidates per pass. Files must be at least24 hours old. Indexed
logs, recent files, unknown names/types, symlinks, nested directories, backups
and LiveRecording remain untouched. Missing/corrupt/legacy-only sources grant
no cleanup authority. Source changes stop remaining deletion.

New-log installation registers a preparation lease under the publication gate.
Pending saves survive the age threshold until publication/discard. Cleanup
checks source, lease and file identity inside short per-file sections; scanning
stays on a worker. It does not rewrite the metadata index or publish new
library contents. OS-owned replacement directories are excluded; this closes
bounded abandoned installed-log maintenance, not eager log startup validation
or physical storage-pressure profiling. See [storage scope](finished-track-storage.md).

All532 core cases pass in `/tmp/mgrsgps-orphan-core.log`. Six new cases cover
old/recent/indexed/foreign files and unrelated live/archive data, aged in-flight
publication, corrupt/missing/changed indexes,64+6 bounded continuation, worker
cancellation and symlinked log directories. Existing source-conflict, failed-
preparation cleanup and long-recording cases remain green.

All349 native integration cases pass (four opt-in skips) in
`/tmp/mgrsgps-orphan-native.xcresult`. Two new integration cases verify that
reads remain read-only, successful maintenance does not republish/change the
library/index, unreadable and cancelled calls retain files, and a healthy call
can later clean. Three UI workflows pass: day/night explicit field-read
recovery/relaunch and real background recording/save/library/map. Host journal
growth4→7 occurs in the same session while still on Home. Night recovery and
recorded-track detail screenshots are inspected. Unsigned phone/watch/widget
Release (`/tmp/mgrsgps-orphan-release.log`) and ten harness checks pass. All
parents end naturally; owned simulator and fake feed are off.

This follows local c259fd1/51a9287 and stays unpushed while10840508823942
validates7fbeab5. No live run cancelled/duplicated, server round, wire or
credential changes. Broader lazy-log startup, dense rendering, watch and
physical/TAK gates remain open.

### Numeric pace count entry, 27 October

[Android-matched pace entry](pace-entry.md) replaces repeated single-step taps
with a three-digit numeric field. New edits apply30...200 immediately; invalid
drafts show the retained value. Imported legacy values remain intact. Day/night
route-card totals, persistence and global largest-night validation pass across
one native/three new UI cases; the existing settings write/retry workflow also
passes. Screenshot inspection prompted a keyboard Done action and a stronger
fully-visible validation assertion before the final green result. Final unsigned
phone/watch/widget Release and ten harness checks pass. See the linked evidence.

Hosted10840508823942 is now terminal on7fbeab5: map passes; field fails large
GPX native-picker activation and Project segment activation; library fails the
largest-night active-course control visibility check. Dedicated field background
steps were skipped after its UI failure. Both field failures pass locally on the
current product with unchanged test helpers (`/tmp/mgrsgps-ci108-local-before.xcresult`);
that does not resolve the hosted failures. Artifact/tree investigation continues.


### Hosted108 repairs and night tactical labels, 27 October

[Hosted108 evidence and repairs](hosted108-repairs.md) records all three
verified artifact hashes, actual native failure recordings/trees, unchanged local
reproductions and two retained failed reveal candidates. Projection acknowledges
native segment selection. Files activates the matching filename leaf. Course
reveal uses bounded centred drags and requires the post-End Start control fully
visible. All nine Files/export cases, two projection cases and all four saved/
active long-course cases pass across the scoped final/source-compatible bundles.
The last run includes final-source day/largest-night active course checks,
terrain LOS/profile/viewshed and five tactical rendering cases. Full hosted
confirmation remains required.

The green hosted map screenshot exposed a real label contrast gap over night
viewshed shading. Tactical names and leg numbers now use bright-red-on-black
labels while geometry retains Android affiliation colors and hostile ENY suffix.
The phone/watch shared renderer and exact original route numbering stay intact;
final30-type contact sheet and actual viewshed captures are inspected. Unsigned
phone/watch/widget Release and ten harness checks pass; no new paired-watch or
physical-device claim. All local parents exited naturally; owned simulator/feed
off. No TAK server or credential changes.

### Candidate pushed; full hosted109 live, 27 October

Pushed all held live-completion/source-write/orphan/pace follow-ups and108
activation/scroll repairs plus night label contrast as
`a002f17c2abd1833d5b5e614d6f3e02bf9ae808c`. Same draft PR updated.
Hosted10940527505812 is confirmed live: map122270958719,
field122270958991, library122270959199. All108 jobs were terminal before
this push; no live CI cancelled or duplicate started. No current-source
hosted success is claimed yet. All local parents ended naturally and owned
simulators/fake feeds are off. Main parity continues; TAK remains off and
real enrolled exchange/renewal stays an open coordinated-test gate.


### Accessible Position/Navigate headers,27 October

[Instrument accessibility evidence](instrument-accessibility.md) records an
actual largest-text Position heading broken over three lines beside an oversized
QR icon, plus a36-point Settings target. Portrait accessibility headers now give
titles a full row and put bounded actions below; compact landscape uses the wide
single row. Settings and QR keep44-point targets. Native glass/night styles,
full grid/callout, QR precision gate, orientation shortcuts and target behavior
remain intact.

Two final-source real-location UI journeys pass at global AccessibilityXXXL in
day/night, portrait/landscape, including current-position QR sharing and selecting
the exact saved target. Display-level captures inspected. All ten existing USNG,
target-selection/recovery/relaunch, orientation and QR regressions pass on the
source-compatible portrait candidate. Final unsigned phone/watch/widget Release
and ten harness checks pass. Before/failure evidence is retained. All local
parents ended naturally; owned simulator/feed off. This source stays local while
hosted10940527505812 runs ona002f17; all three jobs are confirmed live in UI
workflows. No live CI cancelled, server/credential changes or full-app/physical
accessibility claim. Android release/main/claude-tak refs rechecked unchanged.


### Settings backup/restore entry point,27 October

[Settings backup](settings-backup.md) closes an Android SettingsScreen.kt gap:
ordinary/protected backup and native Files restore are now available from the
Settings sheet. Shared snapshot capture gives both Settings and waypoint actions
the same saved sections, lane/quiet-boundary checks and refusal of partial
unreadable data. Existing worker/crypto/provider/ordered additive restore paths
are reused. Committing restore blocks sheet dismissal; cancellation never claims
a saved file. Offline maps and active sessions remain separate.

All46 scoped native integration cases pass, including two new full-section and
unreadable-source preservation cases. Both new Settings native round trips pass
(day and protected night), including deleted Recon records, wrong-password retry
and exact relaunch counts. Both existing waypoint backup/quiet-boundary workflows
pass. The final AccessibilityXXXL night control/cancel test passes with native
swiping; display captures inspected. Earlier invalid-fixture and reveal failures
remain documented, including the removed button-style candidate. Ten harness
checks pass. Current-source unsigned phone/watch/widget Release succeeds in
`/tmp/mgrsgps-settings-backup-current-release.log`; all local parents ended
naturally and owned simulators/fake feeds are off. This stays local behind16fad42.
Hosted109 ona002f17 now has map success and field failure; library122270959199
remains live. The new field failure is next triage; no active job is cancelled,
server/credential changes or full physical/provider claim.

### Hosted109 partial outcome,27 October

On pusheda002f17, map122270958719 passes41 UI cases. Field122270958991
passes350 native cases (four opt-in skips) but its36 main UI cases have one
failure (five TAK opt-in skips): large GPX stays in the native Files picker.
The filename-leaf candidate did not fix this hosted activation. Dedicated
background/practice steps were skipped. The new failure tree shows a local,
List-mode file row187...251pt with its filename199.7...220pt; artifact/movie
inspection remains required before choosing another repair. Field artifact
12749242138 (459,954,694 bytes), expected SHA-256
`2159317e76d676f8382056b3d4dcfb5233725b20f2725e561b47a389b82df88c`,
is downloading to `/tmp/mgrsgps-ci109-field.zip`; digest verification is pending.
Library122270959199 remains live, so there is no whole-run outcome or new push.
Local16fad42 and31bb327 stay held; draft PR updated, no active run cancelled.

### Usage-saving pause,27 October

[Resume handoff](pause-handoff-2026-10-27.md) supersedes the preceding live/pending
CI109 statuses: all jobs are terminal. Map passes; field has one Files failure;
library reports three UI failures and then deadline/artifact-finalization failure.
Both available field/map ZIP digests are verified and captures inspected.
The new Files candidate passes two scoped local iOS26.5 large-GPX cases; shared
consumer regression is still finishing at pause. Course reveal/CI balancing
candidates are saved locally with validation limits explicit. Watcher paused at
Rafael's request; no new hosted run, push, server change, merge or release.


### Resumed and pushed; full hosted110 live,28 October

Pushed all held Settings/instrument/Files/course/CI follow-ups as
`98c5c1764b11b68cb1c96d0067e4a191a81a1cb0`. Same draft PR rewritten around
current behavior/evidence. Full11040729291858 is confirmed live: library
122960900401, map122960900820, field122960900902. All109 jobs were terminal
before this push; no run was cancelled or duplicated. This evidence-only update
stays local while110 runs. No hosted success claimed.

The preserved20-case Files regression passes, including complete native GPX and
explicit Icons-to-List, KMZ/ATAK, ordinary/protected and Settings backup flows.
Resume validation passes six distinct backup/course workflows across final and
source-compatible bundles; two intermediate active-course failures retain the
actual117pt header versus helper125pt bound evidence. Final day/largest-night
active cases pass; ended-form images inspected. Ten harness checks pass. All
local parents end naturally; owned devices/feeds are off. Production Release
evidence from the held Settings milestone remains applicable: subsequent edits
change test interactions/CI/docs only. [Full109 investigation](hosted109-repairs.md).

The one-minute Claude watcher is ACTIVE. Android release/main refs remain
482b417/94c4cc4. Claude's e099a1a now saves/reuses its sign-in port, matching iOS
profile.enrollmentPort; note acknowledged, no wire change needed. No server GO,
infrastructure/credential changes, merge or release. Main saved-log startup
read costs, wider accessibility, independent watch features and physical/genuine
enrolled-TAK gates remain open; an unchanged handoff is not a main-task blocker.

### Reuse verified saved-track statistics,28 October

Local finished-log references now retain optional versioned summary receipts
bound to exact point-file SHA-256 and count/distance. Every startup file checksum
still runs; matching receipts skip row decoding and geodesic recomputation.
Missing/malformed/damaged/future receipts fall back to strict parsing. Successful
legacy reads gain receipts in memory, saved only on the next confirmed edit;
startup remains read-only. Changed/missing bytes still fail opening/refuse writes
and preserve original files. External backups/TAK/watch formats stay unchanged.

All538 core cases,37 scoped native startup/maintenance/backtrack/staged-restore/
backup cases and three native UI workflows pass. The UI covers selected-track
detail/menu Files export at night and day/night damaged-library retry/relaunch
with recovered route/two-point-track access. Night preview/library captures
inspected; current unsigned phone/watch/widget Release and ten harness checks
pass. All parents exit naturally; owned simulator/feed off. One synthetic warm
20,000-point read observes0.00052s cached versus0.06782s uncached; parser-call
assertions, not machine-dependent timing thresholds, prove the skipped pass.
[Receipt semantics and validation](track-summary-receipts.md).

This is a CPU/startup validation milestone, not on-demand point-file loading:
eager mapping/hash reads, dense rendering and physical profiling remain open.
The candidate stays local while hosted11040729291858 on98c5c17 has three live
jobs. Same draft PR updated with held-source status; no active CI cancellation,
server GO, infrastructure/credential change, merge or release.


### Metadata-first saved-track library,28 October

Normal app startup, both retry controls and recovered-recorder finalization now
request deferred validated sources rather than reading every point log first.
Requested map/detail/backtrack/backup/export workers verify identity and checksum
and own the bytes; missing data raises an error instead of exporting or drawing
an empty track. Local sources are not serialized in backup/TAK/watch payloads.
Metadata edits retain references with worker stamp checks and a short index
publication; watch preparation counts failed/oversized sources as omissions.

Cleanup authority is separate: metadata-only opening never authorizes deleting
unreferenced files. All deferred sources must have verified checksums and remain
unchanged before bounded maintenance proceeds. Unread/partially read/failed
sources retain recovery files. A completed map read can request maintenance
afterward without forcing hidden tracks to be read.

551 core cases pass, including13 deferred-load/cleanup regressions. The full356-
case native suite has four opt-in skips/no failures; final28 affected native
cases pass after the cleanup safeguard. Seven distinct UI workflows pass across
source-compatible/final bundles: cold selected-track native Files export, four
recovery/retry/accessibility journeys, cold route/track map persistence/visibility,
and live background recording. The actual simulator journal grows while the
app remains backgrounded, then saves/shows on the map. Cold track-present/hidden
map captures, night GPX, readable recording and largest-night library screens
inspected. Current unsigned phone/watch/widget Release and ten harness checks
pass. All local parents end naturally and owned simulator/feed is off.
[Architecture, exact bundles, failed intermediate fixtures/build and limitations](track-on-demand.md).

Older receiptless/v1 data still takes strict eager fallback until a confirmed
save persists receipts. Automatic non-destructive cache migration, streaming
very long requested logs, dense rendering and physical profiling remain work.
Current map screenshots also expose poor day selected-tab contrast; MapScreen's
forced dark tab chrome is a concrete next UI investigation. No physical locked-
screen, full accessibility or watch-radio claim is made.

Hosted110 on98c5c17 now passes map122960900820:47 UI cases, including the moved
waypoint class. Library122960900401 and field122960900902 remain live. The new
storage commits stay local and are outside that hosted source. Same draft PR
and Claude handoff updated; no cancelling push, duplicate run, server GO/round,
infrastructure/credential change, merge or release.


### Hosted110 partial green evidence,28 October

On pushed98c5c17, map122960900820 passes47 UI cases and library122960900401
passes59 UI cases. Sanitized complete job logs are preserved locally. Map
artifact12840097437 (568,089,658 bytes) has verified SHA-256
`b286a89ce05bee6f423e7e306e0555b3a954fb3210d25cf2be697054aad8942d`;
night viewshed and route/track captures inspected. Library12841300349
(585,114,018 bytes) is downloading under exec session75239, which then verifies
`df9bff377acf5b66e5d13611ad7186ae13a5e70db59372a5cb5acfd6cfc5ca8c`
before extraction. Its status is `/tmp/mgrsgps-ci110-library-artifact-status.json`;
inspect the actual process/handle and captures on continuation, not the status
file alone. Artifact review is still open until that finishes. Field122960900902
remains live in main integration/UI; full-run and dedicated field gates remain
unproven. No live run was cancelled.

Localf2e46e3 is committed with on-demand sources and cleanup authority, behind
66354c0 and evidence3f4a7f6. Draft PR and dated Claude handoff distinguish this
local source from the pushed/hosted source. One-minute coordination remains
active, server off without GO, and all owned local simulators/feeds are off.
Next main UI work is the observed pale day Map-tab selected-icon/text contrast.


## 29 October 2026 — wrist owners and hosted111 repairs

Foreground wrist lane owners are implemented on both platforms; watchOS40mm
callbacks verify entry, named limits/backstop, expiry and suspension/rearm.
Physical haptics, Wear runtime, independent heading/route guidance and background
wrist owners remain open. See watch-wrist-lanes.md and parity-open-gates.md.

Hosted111 field/dedicated background stages pass; its library/map jobs failed.
All14 failed cases now have local passes on the repaired source/workflows. A
real dense-map accessibility defect was fixed without capping/hiding markers:
MapLibre6.31 repeatedly sorted annotations for each index; FieldMapView reuses
native ordered views per camera/data snapshot, with public API fallbacks.
The original5,000-waypoint workflow passes in45.558s; the full visible-count
comparison also passes after real hide/show, camera and night changes.
The iOS26.2 map repair bundle passes11 cases, final large-library/selection
bundle6, plus both complete backup flows and the three former timeout cases.
Full hosted confirmation of the follow-up source remains open. Runtime
invalid-frame warnings lack source locations and remain under diagnosis.
See hosted111-map-repair.md and dense-map-accessibility.md for failed intermediates,
final evidence and physical gates. No server changes, merge or release.


### 29 October — requested track streaming
Map preparation, exact camera fitting and backtracking now parse deferred logs
in verified64 KiB chunks, keeping Android preview stride/exact simplification
and original point bytes. Every row and full checksum/source receipt must pass
before derived output is returned.569 core cases,21 focused native cases and
three UI workflows pass; inspected day/night map and reverse-route captures,
unsigned phone/watch/widget Release pass. See track-streaming.md. Full export
writers, automatic receiptless/v1 cache migration and physical memory/battery
remain open. This local follow-up is held while hosted112 validates2740063; it
is not covered by that run. No merge/release or TAK/infrastructure change.
