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
| Independent watch guidance | Foreground independent lane owners now implemented on both platforms,561 Swift core cases/four Wear session tests and both builds pass; watch guide remains separate/read-only | watchOS40mm and Wear192 dp runtime verify local entry, named sides/backstop, expiry and suspension/rearm; independent heading/route guidance and background owners remain implementation work; physical haptic distinction |
| Watch offline/terrain | Cached field overlays and platform-native maps exist | Offline packs/terrain transfer remain implementation work, not a proven OS impossibility |
| Saved logs | Deferred references, verified map/fit/backtrack streaming and automatic receiptless/v1 cache upgrades implemented;577 core/360 native (four opt-in skips) pass; checksum-gated conservative cleanup | Streaming export writers; real cold-device/dense-map/memory profiles. See track-streaming.md and track-cache-upgrade.md for current local evidence |
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
Both are extracted. The backup log spends most of its allowance repeatedly
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
cache validation are running separately; full hosted confirmation remains open.

Wear28c7717 is pushed to the same draft PR: active lane/status/Stop are visible
on the small round screen, circular clipped labels replaced with wide controls,
46 cases/builds/lint pass and native GPS/vibration foreground runtime passes.
Physical feel, background/heading/route owners and other recorded gates remain.
