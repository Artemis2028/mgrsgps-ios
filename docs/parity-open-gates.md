# Current parity gates — 29 October 2026

This short ledger supplements the chronological inventory. Older “next” and
“missing” notes are historical; check source and the latest evidence before
repeating an implementation or runtime test.

| Area | Current evidence | Remaining work |
| --- | --- | --- |
| Phone route following, haptics, quiet-inside boundaries | Native owners and separate modes implemented; previous hosted107 dedicated background checks green; current local native/UI suites pass | Hosted111 must confirm the changed source; physical locked-screen/GPS/haptic/battery checks |
| Military catalog, tactical graphics and route drawing | Android catalog port, renderer cases, seven current drawing/military UI workflows; automatic names and tight marker labels verified | Broader physical/VoiceOver readability |
| Layers, offline maps and terrain | Phone workflows implemented and scoped/previous hosted map suites pass | Current hosted111; cold/dense/pressure and physical provider tests |
| Waypoints, courses, interchange and field tools | Durable workers/retry, duplicate review, field tools, native Files/protected formats and course workflows implemented | Current hosted111; real cross-device/provider and wider accessibility checks |
| Sparse settings restore | Already implemented in0d84a55; key-presence roundtrip, null/false/zero and stale preparation/rebase tests pass | Closed; see settings-presence-audit.md |
| Watch grid/precision/target/map/overlay and phone guidance | Both apps implemented; real paired local-scene replacement and named-lane states/expiry verified, as recorded in wear-paired-validation.md and watch-phone-guidance.md | Physical wrist/radio/GPS/battery/touch checks |
| Independent watch guidance | WatchModel stops GPS when inactive; watch guide snapshot is explicitly read-only; no watch haptic driver/independent crossing detector | Implementation needed on both watchOS and Wear OS; heading/cue policy, local consent, sensor freshness and lifecycle tests before claiming background capability |
| Watch offline/terrain | Cached field overlays and platform-native maps exist | Offline packs/terrain transfer remain implementation work, not a proven OS impossibility |
| Saved logs | Deferred validated references implemented,557 core/357 native current suites pass, checksum-gated conservative cleanup | Receiptless/v1 automatic cache migration; requested-log streaming; real cold-device/dense-map/memory profiles |
| TAK | Package/TLS/pinning/enrollment/renewal and CoT owner/receive/share implemented; fixture/stand-in and historical non-enrolled runtime evidence exist | Real enrolled iOS/Android exchange and renewal require a coordinated GO; server stays off until then |
| Distribution | Unsigned phone/watch/widget device Release passes | Signing, privacy/distribution and actual physical installation gates; no merge/release approval requested |

Hosted111/run40767120285 is active on pushed c712229. Field123094138445,
map123094138868 and library123094139120 have reached main integration/UI steps.
No source push should cancel that active run. Local evidence/audit commits after
c712229 remain held. This ledger does not mark the full goal complete.

The paired Wear named-limit sequence already proved INSIDE, left/right exits,
backstop crossing and return using production phone guidance/Data Layer, including
phone-launcher background phases. It did not prove independent watch crossings
or wrist haptics. Do not reopen the completed delivery gate as a request for the
user to pair the emulator again. No Android devices were running during this
audit; the read-only inventory started adb, not another emulator.
