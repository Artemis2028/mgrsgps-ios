# Current parity gates — 29 October 2026

This short ledger supplements the chronological inventory. Older “next” and
“missing” notes are historical; check source and the latest evidence before
repeating an implementation or runtime test.

Latest snapshot, 29 October: hosted119 on `40e7e63` is terminal. Field and map
shards pass (map UI:52 total,51 passed,1 skipped). Library has60 total:59 passed,
one dense-map300-second timeout,zero skips. The complete library ZIP is SHA256
verified; see hosted119-library-triage.md. The full dense follow-up now passes
locally in121.051s with original assertions/deadlines, after using the Go to
form's existing prefix and waiting for SDK annotation readiness. A full hosted
pass still needs confirmation on the combined follow-up. Current production
passes641core cases and watchsimulator/unsigned phone-watch-widgetRelease.
The native renewal harness remains offline-validated only; no private fixture
was read or staged and no live renewal/enrolled exchange is claimed.

Wear cached-terrain phone transfer, round/night readout, repeated delivery,
missing-cache handling and phone-off recovery from retained SDK Assets now have
native emulator evidence. Foreground selected-target steering has separate native
permission-revocation and in-process provider-loss evidence. These close only the
specific emulator paths described in the linked reports. Physical radio, GPS,
compass, haptics, storage, background and battery gates remain open. All local
build/test parents are terminal and owned test devices are off. No live TAK round
has been authorized; the server remains off.

The table is the current summary. Dated entries below it retain historical run
status and limitations; their old “next” steps do not override this snapshot.

| Area | Current evidence | Remaining work |
| --- | --- | --- |
| Phone route following, haptics, quiet-inside boundaries | Native owners and separate modes implemented; previous hosted107 dedicated background checks green; current local native/UI suites pass | Hosted111 field/dedicated background stages pass; physical locked-screen/GPS/haptic/battery checks |
| Military catalog, tactical graphics and route drawing | Android catalog port, renderer cases, seven current drawing/military UI workflows; automatic names and tight marker labels verified | Broader physical/VoiceOver readability |
| Layers, offline maps and terrain | Phone workflows implemented and scoped/previous hosted map suites pass | Every hosted111 map failure has a local iOS26.2 pass after chrome navigation repairs; dense annotation/accessibility repair retains all visible markers; full hosted confirmation, cold/pressure and physical provider tests remain |
| Waypoints, courses, interchange and field tools | Durable workers/retry, duplicate review, field tools, native Files/protected formats and course workflows implemented | Every hosted111 library failure has a local pass; ordinary/protected backup and dense map workflows repaired; full hosted confirmation, real cross-device/provider and wider accessibility checks remain |
| Sparse settings restore | Already implemented in0d84a55; key-presence roundtrip, null/false/zero and stale preparation/rebase tests pass | Closed; see settings-presence-audit.md |
| Watch grid/precision/target/map/overlay and phone guidance | Both apps implemented; real paired local-scene replacement and named-lane states/expiry verified, as recorded in wear-paired-validation.md and watch-phone-guidance.md | Physical wrist/radio/GPS/battery/touch checks |
| Independent watch guidance | Both platforms implement foreground owners, complete cached-route progression and optional background lane owners. Apple native Start/Pause/Resume/Stop, Home pause, same-process permission loss/regrant with explicit Resume, and callback-outage stale withholding/fresh recovery pass. Route picker freshness is repaired locally. Wear native selected-target permission and provider interruption/reconfirmation pass | Apple actual OS provider-error delivery, positive calibrated compass steering, physical wrist/lock/GPS/haptics/battery; Wear route/background permission/provider faults and physical delivery. Callback outage is distinct from an OS error. See watch-own-route.md and watch-background-alerts.md |
| Watch offline/terrain | Cached field overlays/native maps plus bounded, source-bound offline Terrarium cache/sampler implemented on both platforms; shared fixtures/core and Wear native cache runtime pass | Apple acknowledged foreground delivery/readout and Wear native Asset transfer/readout, repeat/miss handling and retained-SDK recovery pass. Apple physical queued-file delivery, other sizes/day-mode Wear checks, source/queue faults, terrain overlays/analysis, offline raster areas and physical resource/provider checks remain open. See watch-terrain-transfer.md and the Wear reports linked below |
| Saved logs | Deferred validated log visitors, cache upgrades and owned file-backed GPX/KML/GeoJSON/KMZ/ordinary backup writers implemented and validated; protected backups retain bounded eager authenticated encryption. Native Files roundtrips, cleanup and aggregate budgets pass | Physical peak-memory, cold-device/storage-pressure and provider profiles; no claim of fully incremental manifest encoding or encryption. See backup-streaming-output.md, kmz-streaming-output.md, geojson-streaming-output.md, kml-streaming-output.md and track-streaming.md |
| TAK | Package/TLS/pinning/enrollment/renewal and CoT owner/receive/share implemented; fixture/stand-in and historical non-enrolled runtime evidence exist | Historical Oct 26 enrolled exchange is recorded; current-build enrolled exchange and live renewal remain open pending coordinated GO. New native renewal harness has offline guard/Keychain passes and a safe live skip; see tak-local-renewal-proof.md. Server stays off |
| Distribution | Unsigned phone/watch/widget device Release passes | Signing, privacy/distribution and actual physical installation gates; no merge/release approval requested |

Hosted111/run40767120285 on c712229 is terminal: field all stages pass;
library56/59 and map40/51 UI pass. All14 failed cases now have corresponding
local passes. The map/navigation repair bundle passes11 cases on iOS26.2;
the three lane/Files timeout cases pass unchanged in127/134/115s; ordinary and
protected backup workflows pass; the unchanged dense5,000-waypoint workflow now
passes in45.558s after a product accessibility repair. Six final large-library/
marker-selection cases pass, and an extended hide/show/camera/night count check
passes in172.351s. See hosted111-map-repair.md, hosted111-library-repair.md and
dense-map-accessibility.md. Current unsigned phone/watch/widget Release and ten
harness cases pass. Full hosted confirmation on the follow-up source is still
required. Invalid-frame warnings and physical-density profiling remain open.

The paired Wear named-limit sequence already proved INSIDE, left/right exits,
backstop crossing and return using production phone guidance/Data Layer, including
phone-launcher background phases. It did not prove independent watch crossings
or wrist haptics. Do not reopen the completed delivery gate as a request for the
user to pair the emulator again. No Android devices were running during this
audit; the read-only inventory started adb, not another emulator.


Hosted112 on2740063 is terminal: map passes; field has one Files reopen
failure and library has two failures (ordinary backup time allowance and dense
map options responsiveness). Native357 cases complete with four opt-in skips;
40 field UI cases complete with five skips and one failure. Dedicated later
field steps were skipped; earlier111 background evidence is historical.
Field artifact12864152223 SHA-256 is verified as
f5d4c7564bc4ab1ea072c322a507d1a36adfe0b61d1adb35880d20d2985f608b.
Library artifact12866601557 SHA-256 is verified as
fa0bd20a7f68dd08677f19baa372b2febeada20cc48b203553fb232b98307c1f.
Map artifact12865129169 is also SHA-256 verified as
82cf1161959f982f66c20781d4c77ef3b1e22afd030e139d879911c8f1c9a759;
its extracted UI log confirms51 cases, zero failures and TEST SUCCEEDED.
All three shard artifacts are extracted. The backup log spends most of its allowance repeatedly
querying/tapping the native Files thumbnail, then restores successfully before
hitting the allowance during later verification. Its app spindump shows an idle
run loop/accessibility snapshots, not evidence of a product deadlock.

Filename-first native Files activation passes seven local ordinary/protected
backup, large GPX, icon-to-list, long-name, cancel/retry and selected-track UI
workflows in /tmp/mgrsgps-ci112-file-label-repair.xcresult (678.952s total).
The selected filename must still match exactly; counts, timeouts and full
restore/relaunch assertions are unchanged. Exported large-GPX preview and
restored night-library screenshots inspected. This validates the helper against
the earlier app binary. Fresh file-backed GPX output and dense accessibility
cache validation pass together:364 native cases (four opt-in skips), all eight
selected UI cases, and unsigned Release. Captures inspected; Xcode parent
finalized with exit0/TEST SUCCEEDED after its diagnostic collector timeout.
Full hosted confirmation remains open.

Wear28c7717 is pushed to the same draft PR: active lane/status/Stop are visible
on the small round screen, circular clipped labels replaced with wide controls,
46 cases/builds/lint pass and native GPS/vibration foreground runtime passes.
Physical feel, background/heading/route owners and other recorded gates remain.

Local KML follow-up now streams whole local logs into native Files without
import ceilings, preserving folder/shape/track semantics and validated cleanup.
All587 core cases and the full366 native cases (four opt-in skips) pass; the
real KML Files save/reopen passes54.667s after correcting a new test's expected
point-vs-line classification. Screenshot inspected; unsigned Release passes.
See kml-streaming-output.md. Held locally while hosted113/run40807863444
validates a54ac75; it is not covered by that head. GeoJSON/KMZ/backup streaming,
physical/provider checks and other listed gates remain.

Local GeoJSON follow-up streams complete tracks with Android feature metadata,
rounding and short-track rules retained. All592 core cases and368 native cases
(four opt-in skips) pass, along with two real Files/import/map workflows and
unsigned Release. Captures inspected. See geojson-streaming-output.md. Held
locally alongside the KML change while hosted113 validates a54ac75; no live
run cancelled. KMZ/backup streaming and remaining watch/physical gates stay open.


Local watchOS background lane milestone is implemented and simulator-validated;
see watch-background-alerts.md for exact scope and crash repair evidence. The
optional location owner survives the crown/clock transition, named system
notices cover both sides and the bent backstop, notification opening preserves
the repaired process, and Stop/default foreground-only rearming work. All597
core cases, twelve focused policy cases and repaired simulator/device Release
pass. Owned pair shut down, fake locations cleared and preferences restored
byte-for-byte. Wear background work and physical interruption/lock/haptic/battery
gates remain open. Hosted113 field is now successful; map/library remain live.
No push cancelled the run; local KML/GeoJSON/watch changes are not in that head.


Wear4faf220 is pushed to its existing draft PR. Optional background lane alerts
now use an explicit location foreground service with its own native GPS, cadence,
freshness clock, bounded wake ownership and run-scoped notification Stop. All46
Wear unit cases, both APKs and Release lint pass; native API34 component runtime
passes unassisted in55.583s. System UI is top resumed while real synthetic GPS
callbacks drive both sides/bent backstop; finished vibrator waveforms, quiet
return/stale holds, recovery, Stop, old-action isolation and scene deletion are
verified. This is not a visual toggle/notification or physical-wrist pass.
See the Wear checkout's docs/watch-background-lanes.md. Owned emulator is off,
original preferences/notification grant/mock-location mode restored and every
parent reaped. No TAK server or phone connection.
Hosted113/run40807863444 is now terminal: field/map pass, library has three
failures in42 UI cases: dense-library map-options acknowledgement, filtered
Select All showing0 rather than3 selected, and opening the complete checkpoint
splits screen. Failed stage log retained at
/tmp/mgrsgps-ci113-library-failed.log. Library artifact12873327051 is being
retrieved for triage; expected SHA-256 is
255d295dbfeb04e8dbac24beac434a341ad2af9ddf8f2ea83d5859946c0a6f32.
KML1370c82, GeoJSONded37ba and watche84e090 remain local while these failures
are inspected; no full hosted-green claim and no redundant rerun.


The full hosted113 result artifact corrects the library total to56 passes/four
failures across60 cases: the console final42-case block omitted an earlier
dense accessibility timeout. Verified artifact and exact local reproduction
are recorded in hosted113-library-triage.md. Three unchanged local workflows
pass; the stronger dense case exposes907 accessible markers vs924 SDK
annotations after camera return. A visibility-aware ordering-cache repair is
staged, and unsigned device Release passes. Its UI replay awaits the preserved
baseline parent's diagnostic finalization; no duplicate or cancelling run.


The visibility-cache repair passes all four unchanged hosted113 regression
workflows together (179.270/46.581/11.410/46.574s), exit0/TEST SUCCEEDED.
Unsigned phone/watch/widget Release passes; key captures inspected. See
hosted113-library-triage.md for the reproduced907/924 mismatch and exact proof.
Every local parent is reaped, fake location cleared and owned simulator off.
The repaired head needs fresh hosted confirmation; earlier local export/watch
commits are now ready to accompany that push. Other listed gates remain open.


Local KMZ follow-up now uses complete validated local-log visitors, bounded
production output and an owned Files payload. A two-pass STORE writer retains
legacy ZIP headers with upfront CRC/size and refuses changed source bytes before
finishing its directory. All603 core cases, full370 native cases (four opt-in
skips), real KMZ Files save/reopen55.232s and unsigned Release pass. Preview
captures inspected; Java ZipInputStream independently reads the Files-saved
archive with all six expected records. Every parent is reaped and owned
simulator off/fake location cleared. Held locally while hosted114/run40821076335
validates5f73683. See kmz-streaming-output.md. Backup streaming and remaining
watch/physical/provider gates stay open; no new TAK/paired-transport proof.


### Backup file output follow-up — 29 October 2026
Ordinary/protected native Files exports now use owned file payloads. The STORE
writer validates every source before output, verifies the second visit and
preserves complete raw track bytes and existing manifest/protocol budgets.
Manifest encoding and the protected authenticated envelope remain bounded eager
steps. All609 core cases pass; full374 native cases complete with four opt-in
skips/no failures. Both ordinary/protected Files workflows and unsigned Release
pass. Actual Files-saved ZIP also passes independent Java17 member/CRC checks;
representative captures inspected. Every parent reaped and simulator off.
See backup-streaming-output.md for evidence and limits. Held locally while
hosted114/run40821076335 validates pushed5f73683; all three shards remain active.
Physical memory/provider, watch heading/route/offline/terrain and real enrolled
TAK exchange/renewal remain open. Server stays OFF; no GO or infrastructure action.


### Concise boundary panel — 29 October 2026
Moved drawing/monitoring explanatory paragraphs and the settings link into a
collapsed Boundary help disclosure. Primary draw/status/saved boundary controls
remain visible; monitoring decisions and permissions are unchanged. The existing
day draw/insert/move/save/relaunch and night edit/cancel/delete/durable-delete
workflows pass on iOS26.2 (two cases, zero failures, Xcode exit0). Day/night
captures inspected; every local parent reaped, static fake GPS cleared and owned
simulator off. Evidence: /tmp/mgrsgps-boundary-concise-ui.xcresult and
/tmp/mgrsgps-boundary-concise-images/manifest.json. No new background crossing,
physical or TAK verification claimed. Held locally while hosted114 remains live.


### Concise practice-course controls — 29 October 2026
Moved setup/scoring/navigation explanations into collapsed Practice help. Missing
location and empty eligible-folder states remain visible next to their controls;
scoring, persistence, checkpoint ordering, navigation locking and recovery stay
unchanged. Existing day folder-start/relaunch/end-preserves-checkpoints,
night progress/grid and largest-text night10,000-checkpoint active-course
first/last split/relaunch/end-control workflows all pass (three cases, no failures,
Xcode exit0). Day/night/XXXL captures inspected. Fake GPS cleared, owned simulator
off, parent reaped. Evidence /tmp/mgrsgps-practice-concise-ui.xcresult and
/tmp/mgrsgps-practice-concise-images/manifest.json. No new real-location scoring
or physical verification claimed. Held locally while hosted114 is live.


### Concise interchange previews — 29 October 2026
Shortened paste/password/backup prompt copy and moved generic preservation and
backup advice into collapsed Import details. Per-format loss/unsupported-content
notes, skipped-record counts, errors and duplicate confirmation stay visible;
parsing, preview/commit and password behavior unchanged. Existing CSV
preview/cancel/confirm/retry/relaunch, malformed input/night preview and night
skip-matches/persistence workflows pass (three cases, zero failures, Xcode exit0).
Day/night captures inspected. Evidence /tmp/mgrsgps-import-concise-ui.xcresult
and /tmp/mgrsgps-import-concise-images/manifest.json. Parent reaped, fake GPS
cleared, owned simulator off. Held locally during hosted114; no new protected
backup/physical/TAK proof claimed for this copy-only follow-up.


### Hosted114 field outcome and selection acknowledgement — 29 October 2026
Field artifact12877500391 digest verified. Complete main bundle410 cases:
401 passes/nine skips/zero failures; practice14 passes/one failure out of15.
Failed night target-write workflow never reached its intended fault: video and
AX tree show Random points still selected after the From folder gesture.
Practice setup now uses existing selection-aware native segment activation.
Both day/night target-save/retry/lock/relaunch/end/preserve-checkpoint workflows
pass locally59.292s/55.275s, Xcode exit0; reopened captures inspected. Fixtures,
timeouts and recovery assertions retained. Parent reaped, GPS cleared, simulator
off. See hosted114-field-triage.md. Local result is not a fresh hosted-green
claim; other114 shards remain live, so the change is held with prior follow-ups.


### Watch Map info accuracy — 29 October 2026
Removed obsolete prose claiming simplified routes omit leg numbers and that no
wrist alerts run. Info now describes supplied original leg numbers/ranges and
Choose lane; custom quiet-perimeter monitoring remains distinct from implemented
navigation-lane wrist alerts. Removed the long artwork implementation paragraph.
Watch README/current parity summary now match the existing route/background
owners. Copy-only change; unsigned phone/watch/widget device Release passes.
No new watch touch, runtime, physical or transport verification claimed.


### Hosted114 map helper acknowledgement — 29 October 2026
Verified full map artifact51 cases:50 passes/one failure. The saved-geometry
manual pan succeeded, but the readout helper collapsed an expanded HUD during
an AX child refresh. Guarding the exposed expanded state preserves the same
user gestures and exact camera/overlay/loading assertions. All four local
portrait/landscape/night/pending-fit workflows pass; Xcode finalized exit0.
Retained-pan/new-GoTo captures inspected, fake GPS cleared and owned simulator
off. See hosted114-map-triage.md. Library114 still live; full hosted confirmation
remains open and local follow-ups are held without cancelling it.


### Watch-owned heading foundation — 29 October 2026
Foreground CoreLocation heading readout now has current-session, five-second
monotonic age and25-degree accuracy gates plus the existing fresh watch GPS and
reference conversions. Missing/uncalibrated/expired/native-true-unavailable data
stays unavailable. Foreground suspension stops/clears compass ownership even
when lane background location continues. All613 core cases and unsigned Release
pass. Native simulator/lifecycle/40mm and physical calibrated readings remain
next; steering/route progression is not claimed complete. See watch-own-heading.md.


### Tactical canvas redraw follow-up — 29 October 2026
Full hosted114 library bundle59pass/1timeout across60 cases. Tactical canvas
now skips unchanged data/camera repaint requests; visibility and native markers
are retained in full. Exact dense map count/hide/show/camera/night workflow
passes168.538s with the CI3s moving fake GPS feed. Route insert/drag/edit/relaunch
and night ring/sector workflows pass57.350s/56.005s; unsigned Release passes.
All final Xcode parents exit0, captures inspected, phone feed reaped/GPS cleared
and simulator off. Extreme-density label overlap remains, not hidden. See
hosted114-library-triage.md. Fresh hosted confirmation is still required.


### Watch compass native availability check — 29 October 2026
Native40mm watch run shows own fake-GPS distance/bearing and explicit compass
unavailable with a cached fake target; no heading injection. Night expired-fix
readout suppresses numbers; terminate/relaunch retains target. Accessibility3
uses scrolling; lower heading row/touch, fresh-GPS recovery after clear, real
heading callbacks and Home/lock transitions remain open. See watch-own-heading.md
for exact evidence/limits. All native parents/feeds reaped, both owned simulators
off, fake GPS cleared and original watch preferences restored byte-for-byte.


### Watch GPS recovery follow-up — 29 October 2026
Same native40mm watch process now verifies fresh fake GPS, expiry after source
clear and recovery when moving OS GPS resumes. Single replacement fix did not
refresh; single-fix recovery remains unverified and is not counted as passed.
Night relaunch also shows fresh distance/bearing and compass-unavailable; native
callbacks confirm5m precise foreground fixes. No heading injected. Home/lock,
actual compass callbacks/physical calibration and large-text lower-row interaction
remain open. All local parents reaped, fake GPS cleared, watch off and original
prefs restored byte-for-byte. See watch-own-heading.md. Held documentation follow-up
while hosted115 validates exact5b37bd2; no cancelling push/duplicate run.


### Foreground own-watch target steering — 29 October 2026
Explicit foreground-only Start/Stop, fresh own GPS/heading, sensor-gap silence,
turn confirmation/cadence and one-shot arrival now use shared native-independent
policies. Target/permission/scene changes disarm; lane and steering owners do not
compete. All620 core cases, final Release and watch simulator build pass. Native
40mm day/night layout and unsupported-compass disabled Start inspected with real
OS fake GPS and no heading injection. Positive compass/haptic/Home-lock/physical,
Wear steering, route progression and offline/terrain gates remain open. See
watch-own-steering.md. All local parents reaped/watch off/prefs restored/GPS clear.
Held locally while115 validates5b37bd2; no cancelling push or duplicate dispatch.


### Claude steering contract follow-up — 29 October 2026
Read-only Android source confirms Claude's2s heading/10s GPS policy. Watch
steering arming/decisions/queued effects now use2s; display-only5s values cannot
authorize steering cues. All622 core cases and Release pass. Quiet watch homing
has no heartbeat and does not claim Android's default30s reassurance or held-leg
azimuth/corridor mode; these differences are explicit in watch-own-steering.md.
No Android/protocol edits. Locally held while115 runs; full route progression
accepting only complete cached geometry remains next independent implementation.


### Foreground Apple watch route owner — 29 October 2026

Explicit complete-route Start/Pause/Resume/Stop now advances ordered checkpoints
from unique fresh own-GPS samples. The original source timestamp also prevents
repeat advancement when a callback's uptime conversion jitters. Simplified or
incomplete geometry is ineligible; changed/omitted routes disarm, scene suspension
pauses, relaunch never arms. RT1WP2/RT1WP3, distance/bearing and one completion
are inspected on the native40mm watch using three moving fake OS GPS phases.
All629 core cases and final unsigned Release/watch simulator builds pass. Native
Pause/Resume/Stop taps, positive compass-driven route steering, physical haptics
and Home/lock/permission transitions remain gates. See watch-own-route.md.
Hosted115 still validates5b37bd2; local follow-ups held without cancelling it.
TAK off, real enrolled exchange/renewal still requires coordinated GO.


### Wear own-compass foundation — 29 October 2026

Wear localb1a8b37 adds foreground rotation-vector heading, watch-top display remap,
local magnetic model/reference correction and target deviation. Display5s and
future-steering2s age gates are separate; uncalibrated/missing/poor sensors have
explicit unavailable states. All49 Wear unit cases, Debug/Release and Release
lint pass. Actual native emulator callbacks plus fake cached target/OS GPS show
002°TRUE/L002° in day/night. Sensorservice confirms Home unregister/resume fresh
registration; no heading injection or physical compass claim. Owned read-only
emulator terminated, original companion preferences restored byte-for-byte.
Independent Wear steering/routes, hardware compass/orientation and offline/terrain
remain open. See Wear docs/wear-os.md and /tmp/mgrsgps-wear-heading-active.json.
No phone checkout edits, TAK connections or infrastructure operations.


### Hosted115 field switch interaction — 29 October 2026

Field115 on5b37bd2 has417 cases:407pass/nine skip/one failure. Verified full
artifact/recording/AX evidence shows the graphics visibility switch remains on
after a single coordinate gesture. The two night field-edit workflows now use
existing native-switch acknowledgement; all persistence assertions remain.
Local graphics/track and route edit/hide/delete/relaunch pass56.177s/65.730s,
Xcode exit0; captures inspected, feed reaped/GPS cleared/phone off. Product
mutations unchanged. See hosted115-field-triage.md. Map/library115 still run;
no cancelling push, duplicate dispatch or full-hosted-green claim.


### Explicit Wear foreground steering — 29 October 2026

Wearb184864 adds locally armed own-GPS/compass homing with shared phone turn policy,
10°/5s confirmation, quiet on course, strict50m whole-circle one-shot arrival and
2s heading gate. All56 Wear unit cases, Debug/Release and Release lint pass. Native
round-screen Start shows Confirming turn then Turn right; OS vibrator history
records expected pairs of70ms effects. Stop quiet4s and Home-before-hold quiet6s
pass; fresh resume and night relaunch remain disarmed. Original prefs restored
byte-for-byte, owned read-only emulator off/no snapshot, all parents reaped.
Physical compass/haptic/battery and broader sensor/permission faults, Wear route
execution, held-azimuth/corridor mode and offline/terrain remain open. See Wear
checkout docs/watch-own-steering.md and /tmp/mgrsgps-wear-steering-active.json.


### Hosted115 measurement rail interaction — 29 October 2026

Verified map115 full bundle51cases:50pass/one failure. The landscape recording
shows Terrain visibility after a map-measure gesture, before ruler selection.
Local helper now waits for a fully visible rail row and slow drag/hold ends
momentum; measurement opens through the existing validated-frame native helper.
All four local measurement workflows pass29.058/44.862/48.150/36.326s with exact
geometry/zoom assertions intact. Xcode exit0, captures inspected, feed reaped/GPS
cleared/owned phone off. Product drawing/geometry unchanged. See
hosted115-map-triage.md. Library115 remains live; no full-hosted-green claim or
cancelling push.


### Hosted115 library timeout follow-up — 29 October 2026

All115 jobs are terminal failure on5b37bd2. Verified library result60cases:
58pass/two300s timeouts. Dense spindump identifies repeated O(points×folders)
Foundation visibility comparisons on the app main thread. Per-call distinct-folder
memoization retains exact comparison/first-match/orphan/order rules. Native helper
also avoids polling for already-existing controls. All631 core cases, final
unsigned phone/watch/widget Release and both exact native workflows pass:
dense160.622s/protected Files144.814s. Original marker/persistence/password and
300s assertions remain; captures inspected, all parents reaped, GPS clear/phone
off. Extreme-density label overlap remains a readability limit. See
hosted115-library-triage.md. Field/map repairs also have local passes; fresh
hosted confirmation on the combined follow-up remains required. No job cancellation
or duplicate dispatch, merge or release.


### Wear complete-route owner — 29 October 2026

Wear92f56ea adds explicit Start/Pause/Resume/Stop from complete visible cached
routes within the existing128-point line budget. Only unique post-action own-GPS
samples advance ordered checkpoints, with distance+accuracy strictly below25m.
Accepted source identity is stored locally from Data Layer metadata; wire budgets
and revision rejection are unchanged. Accepted source/geometry/hide/delete/omission
changes disarm; suspension pauses; separately armed route steering transfers only
within that run and never auto-arms after Resume or cold launch. All63 Wear unit
cases, Debug/Release and Release lint pass. Native route picker/progression,
steering checkpoint handoff, Pause/Resume, final four-point completion, Stop and
night cold-no-auto-arm pass using fake OS GPS/virtual compass. Final source-header/
compact-completion captures inspected. Initial finite feed ended before its final
point and is not counted as completion evidence; a fresh-process final replay logs
exactly1/2/3/4complete. Original prefs restored byte-for-byte, all parents reaped,
owned read-only emulator off/no snapshot. See Wear docs/watch-own-route.md and
/tmp/mgrsgps-wear-route-active.json. Physical route haptics/compass, broader native
fault/source delivery and offline/terrain/hardware/provider gates remain open.
This is additional watch route execution, not Android phone saved-route parity.
CI116 continues on2c650e8; this documentation update is held locally to preserve it.
TAK off; enrolled exchange/renewal still requires coordinated test.


### Hosted117 and dense waypoint captions —29October2026

117is fully terminal on ea06859: mapSUCCESS, field409pass/2fail/9skip in420cases,
library57pass/3fail/0skip in60cases. SHA-verified field/library artifacts and native
recordings/spindumps distinguish actual product rendering from stale Files retry,
missed switch gesture, dense transition delay and protected workflow deadline.
Field exact-case follow-ups pass52.418s/42.646s; all three final library failures
have local passes150.303s/44.573s/133.329s with original counts, persistence, night,
password and300s assertions retained. No full hosted pass is claimed.

Waypoint captions now avoid collisions and paint above every marker symbol while
retaining the full native marker/AX/tap set. Actual cold-day/night captures exposed
and resolved a nil SDK visibility snapshot despite attached views; owned native
view geometry now supplies captions. Four meaningful layout cases include5000
noncolliding labels with no cap. This does not declutter symbols or change tactical,
grid/lane/remote policies. See map-waypoint-labels.md and hosted117-field/library
triage reports. All local test/diagnostic parents are reaped and fake GPS cleared;
the disposable clone is removed. Final unsigned phone/watch/widget device Release passes; fresh hosted
confirmation remains open. TAKOFF, real enrolled exchange/renewal still requires coordinatedGO.


### Cross-platform evidence reconciliation — 29 October 2026

Current owned Wear source is `1b5fb57` on `codex/wearos-glance`. Reports in that
checkout supply the exact scope and cleanup limitations:

- [Phone/Wear terrain delivery and retained SDK recovery](../../gridfix-wearos/docs/watch-terrain-transfer.md): 71 Wear / 460 phone unit cases and build/lint baseline, actual paired raw Asset delivery, map-centre 100 m synthetic DEM readout and cold recovery with the phone emulator off. Watch datastore restoration was not verified in the terrain recovery round; temporary read-only overlays were discarded. Later permission/provider rounds validated archives before testing.
- [Permission revocation](../../gridfix-wearos/docs/watch-steering-permission.md): Android kills the steering process; restored permission and fresh sensors do not re-arm it. A new native Start is required.
- [Provider interruption](../../gridfix-wearos/docs/watch-steering-provider.md): same-process loss stays quiet, retains the existing consent and reconfirms before producing new native effects. This is selected-target foreground evidence, not route or background-owner coverage.
- [Prepared local renewal proof](tak-local-renewal-proof.md): offline guards and native Keychain/certificate cases pass; the live case skips without a private reviewed fixture. No credentials were read or staged, and no TAK connection was made. Actual renewal, native Renew-button interaction and current-build iOS/Android fake-position exchange remain coordinated gates.

No duplicate CI run, server/infrastructure change, merge, publish or release is
authorized by this ledger. The held test/report changes must not be pushed while
hosted 118 is active because doing so cancels its evidence run.


### Watch route GPS replay repair — 29 October 2026

A failing core regression exposed nonconsecutive source callback replay completing
a coincident route after Pause/Resume when converted uptime moved forward. The
Apple route policy now requires strictly increasing original source timestamps
throughout a run; explicit Start resets the watermark. All 637 core cases and
unsigned phone/watch/widget Release pass. Wear already uses strictly increasing
native elapsedRealtimeNanos. See watch-own-route.md. This does not close native
watch gesture/physical fault or live TAK gates. Held locally while CI 118 runs.


### Hosted118 follow-up validated locally

The single remaining dense case now passes in140.050s after removing duplicate
AX count snapshots and redundant delete events after native Select All. Marker,
hide/show, camera-return, night and300s assertions remain intact. Shared-helper
coverage passes long Files filename53.398s and coordinate/tool workflow123.175s.
Captures inspected; all parents reaped, fake GPS cleared, disposable phone deleted.
See hosted118-library-triage.md. The combined follow-up needs fresh hosted
confirmation; real enrolled TAK exchange/renewal and physical watch gates stay open.

### Hosted119 field and local watch lifecycle checkpoint

Hosted119/run40903664862 on40e7e63 has a successful field shard; map and library
remain in progress. No full hosted pass or cancelling push. Local held commits
1d9d16b/df8cf39/2139f9d/ccbb183/627ccbf contain the route-picker freshness fix,
Home/permission/callback-outage native evidence and nine passing focused route
policy cases. All owned local parents are reaped and disposable devices deleted.
See watch-own-route.md for precise scope: GPS callback outage is not an actual
OS provider-error event; compass/haptic/background/physical checks remain open.
TAK remains OFF; current enrolled exchange and real renewal need coordinated GO.
Routing side-project spec reviews stay in the Claude handoff, with no routing
code/docs/fixtures added to the current iOS or Wear branches.

### Hosted119 terminal triage and follow-up

Field/map pass; library59/60 has only the dense300s timeout. SHA-verified complete
bundle and native activities identify accumulated Go to selection/input latency.
Prefix completion and SDK annotation readiness preserve all count, visibility,
far/return camera and night assertions; full native case passes121.051s.
See hosted119-library-triage.md. All local parents reaped; fakeGPS cleared and
fresh disposable phone deleted. Latest watch picker/terrain repairs and native
lifecycle reports are validated and ready for a single combined follow-up push.
TAK remains off; real enrolled exchange/renewal and physical gates remain open.
