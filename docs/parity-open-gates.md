# Current parity gates — 29 October 2026

This short ledger supplements the chronological inventory. Older “next” and
“missing” notes are historical; check source and the latest evidence before
repeating an implementation or runtime test.

| Area | Current evidence | Remaining work |
| --- | --- | --- |
| Phone route following, haptics, quiet-inside boundaries | Native owners and separate modes implemented; previous hosted107 dedicated background checks green; current local native/UI suites pass | Hosted111 field/dedicated background stages pass; physical locked-screen/GPS/haptic/battery checks |
| Military catalog, tactical graphics and route drawing | Android catalog port, renderer cases, seven current drawing/military UI workflows; automatic names and tight marker labels verified | Broader physical/VoiceOver readability |
| Layers, offline maps and terrain | Phone workflows implemented and scoped/previous hosted map suites pass | Hosted111 map40/51 UI pass; map chrome/gesture/provider failures and dense5,000-waypoint accessibility timeout need repair; cold/pressure and physical provider tests |
| Waypoints, courses, interchange and field tools | Durable workers/retry, duplicate review, field tools, native Files/protected formats and course workflows implemented | Hosted111 library56/59 pass; two backup disclosure tests repaired and both full native Files/restore/relaunch workflows pass locally; dense-map timeout remains open; real cross-device/provider and wider accessibility checks |
| Sparse settings restore | Already implemented in0d84a55; key-presence roundtrip, null/false/zero and stale preparation/rebase tests pass | Closed; see settings-presence-audit.md |
| Watch grid/precision/target/map/overlay and phone guidance | Both apps implemented; real paired local-scene replacement and named-lane states/expiry verified, as recorded in wear-paired-validation.md and watch-phone-guidance.md | Physical wrist/radio/GPS/battery/touch checks |
| Independent watch guidance | Foreground independent lane owners now implemented on both platforms,561 Swift core cases/four Wear session tests and both builds pass; watch guide remains separate/read-only | watchOS40mm runtime verifies local entry, named sides/backstop, expiry and suspension/rearm; Wear runtime remains; independent heading/route guidance and background owners remain implementation work; physical haptic distinction |
| Watch offline/terrain | Cached field overlays and platform-native maps exist | Offline packs/terrain transfer remain implementation work, not a proven OS impossibility |
| Saved logs | Deferred validated references implemented,557 core/357 native current suites pass, checksum-gated conservative cleanup | Receiptless/v1 automatic cache migration; requested-log streaming; real cold-device/dense-map/memory profiles |
| TAK | Package/TLS/pinning/enrollment/renewal and CoT owner/receive/share implemented; fixture/stand-in and historical non-enrolled runtime evidence exist | Real enrolled iOS/Android exchange and renewal require a coordinated GO; server stays off until then |
| Distribution | Unsigned phone/watch/widget device Release passes | Signing, privacy/distribution and actual physical installation gates; no merge/release approval requested |

Hosted111/run40767120285 on pushed c712229 is terminal: field123094138445
passes all stages; library123094139120 has56/59 UI pass; map123094138868 has40/51
UI pass. Two backup tests are repaired locally. Dense-map performance, map
chrome/gesture/provider failures and native Files/lane timeouts remain to triage
and repair. Map artifact12857117832 digest33d955593de4c7d2af419a3bf03769b3035053c2c556f89547988a01c6199504
is verified/extracted at /tmp/mgrsgps-ci111-map. Library diagnosis is in
hosted111-library-repair.md. Local evidence/audit/repair/wrist commits remain held
until the next validation checkpoint; no full hosted-green claim.

The paired Wear named-limit sequence already proved INSIDE, left/right exits,
backstop crossing and return using production phone guidance/Data Layer, including
phone-launcher background phases. It did not prove independent watch crossings
or wrist haptics. Do not reopen the completed delivery gate as a request for the
user to pair the emulator again. No Android devices were running during this
audit; the read-only inventory started adb, not another emulator.
