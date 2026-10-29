# Current parity gates — 29 October 2026

This short ledger supplements the chronological inventory. Older “next” and
“missing” notes are historical; check source and the latest evidence before
repeating an implementation or runtime test.

| Area | Current evidence | Remaining work |
| --- | --- | --- |
| Phone route following, haptics, quiet-inside boundaries | Native owners and separate modes implemented; previous hosted107 dedicated background checks green; current local native/UI suites pass | Hosted111 field/dedicated background stages pass; physical locked-screen/GPS/haptic/battery checks |
| Military catalog, tactical graphics and route drawing | Android catalog port, renderer cases, seven current drawing/military UI workflows; automatic names and tight marker labels verified | Broader physical/VoiceOver readability |
| Layers, offline maps and terrain | Phone workflows implemented and scoped/previous hosted map suites pass | Every hosted111 map failure has a local iOS26.2 pass after chrome navigation repairs; dense annotation/accessibility repair retains all visible markers; full hosted confirmation, cold/pressure and physical provider tests remain |
| Waypoints, courses, interchange and field tools | Durable workers/retry, duplicate review, field tools, native Files/protected formats and course workflows implemented | Every hosted111 library failure has a local pass; ordinary/protected backup and dense map workflows repaired; full hosted confirmation, real cross-device/provider and wider accessibility checks remain |
| Sparse settings restore | Already implemented in0d84a55; key-presence roundtrip, null/false/zero and stale preparation/rebase tests pass | Closed; see settings-presence-audit.md |
| Watch grid/precision/target/map/overlay and phone guidance | Both apps implemented; real paired local-scene replacement and named-lane states/expiry verified, as recorded in wear-paired-validation.md and watch-phone-guidance.md | Physical wrist/radio/GPS/battery/touch checks |
| Independent watch guidance | Foreground lane owners/runtime on both platforms; optional watchOS background location/system notices and Wear location foreground service implemented;597 core cases and Release pass, native watchOS40mm UI and Wear API34 component runtime verified | New Wear toggle/notification visual checks, independent heading/route guidance, physical GPS interruption/lock, notification delivery, haptic distinction and battery. See watch-background-alerts.md |
| Watch offline/terrain | Cached field overlays and platform-native maps exist | Offline packs/terrain transfer remain implementation work, not a proven OS impossibility |
| Saved logs | Deferred references, verified map/fit/backtrack streaming and automatic receiptless/v1 cache upgrades implemented, plus file-backed GPX output;582 core/364 native (four opt-in skips), eight export/dense UI cases and Release pass; checksum-gated conservative cleanup | Other format streaming writers; real cold-device/dense-map/memory profiles. See gpx-streaming-output.md, track-streaming.md and track-cache-upgrade.md for current local evidence |
| TAK | Package/TLS/pinning/enrollment/renewal and CoT owner/receive/share implemented; fixture/stand-in and historical non-enrolled runtime evidence exist | Real enrolled iOS/Android exchange and renewal require a coordinated GO; server stays off until then |
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
