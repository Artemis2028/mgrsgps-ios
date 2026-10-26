# TAK remote scene on the watches

Both companions display the phone's remote TAK contacts, markers, lines and
areas in a separate read-only map layer. The watch never connects to a TAK
server and receives no server addresses, account details, keys or certificates.
Its current position and waypoint metrics still require its own usable GPS fix.
Remote items never enter the saved waypoint library or become navigation targets.
Map labels have a TAK prefix; map details distinguish contacts, markers, lines
and areas, source connection state, cache age and omissions.

On iOS, Show TAK layer hides/clears the watch remote layer too. Android's current
TAK phone implementation always displays its remote layer; TAK-disabled releases
send an explicit disabled empty scene. Both use the canonical phone TAK scene,
not another server parser or connection. Local fields and lanes retain their own
map packet, visibility and cache semantics. Phone-guidance status and quiet-inside
boundary behavior are unchanged.

## Complete replacement contract

`WatchTAKSnapshot` is version 1 JSON, WatchConnectivity key `gridfix.tak.v1` and
Wear Data Layer path `/gridfix/tak/v1`, string `snapshot`.

| Field | Meaning |
| --- | --- |
| sourceID / revision | Stable phone publisher identity and increasing publication counter |
| at | Frame time, epoch milliseconds |
| enabled / connected | Remote layer enabled / phone's actual TAK connection state |
| omitted | Eligible items omitted by application geometry/count/byte budgets |
| items | Complete replacement of the previous remote scene |
| item id | SHA-256 of the complete original uid; identities are not truncated |
| name / affiliation | Callsign, at most 120 Unicode characters; friendly/hostile/neutral/unknown |
| points / closed / contact | Complete WGS84 decimal-degree geometry and item classification |
| expiresAt | Original TAK stale deadline, epoch milliseconds, capped at one hour ahead |

The application budget is **8 KiB actual UTF-8 JSON**, at most **64 items**,
**384 total vertices** and **128 vertices per drawing**. Whole drawings are
retained or omitted, never thinned into another boundary. Invalid/zero positions,
coordinates beyond ±85° latitude, dateline-crossing shapes, malformed contacts,
duplicate ids and oversized geometry are refused or counted as omissions.
Already stale source items are excluded. These are deliberate shared preview
budgets, not assertions about platform transport limits.

Empty or disabled scenes explicitly clear remote items. Lower/equal revisions
cannot reapply an old scene, and older frames from another publisher cannot undo
a newer source. A frame more than two seconds in the future is refused. Item
stale times remain authoritative when the phone disconnects: there is no periodic
transport heartbeat that extends a teammate's position.

## Expiry and caching

A watch receipt anchors each expiry to monotonic time as well as wall time.
A new frame with an unchanged/earlier item stale time retains the earlier local
monotonic deadline. Wall-clock drift of more than two seconds or an uptime reset
hides the cached scene. A fresh newer source frame can reconcile the clock; it
still cannot extend an unchanged item's retained deadline.

The bounded private cache preserves the snapshot, receipt clock and per-item
monotonic deadlines across process relaunch. Cache decoding checks size, ids,
finite deadlines and coherence with the packet; it does not re-anchor an old
item as newly received. Cache storage is capped at 24 KiB. Only unexpired items
render or appear in the item list. A stale phone scene may still have unexpired
markers, which are explicitly labelled cached; it is not proof a teammate is
currently moving or connected.

WatchConnectivity uses a complete context plus immediate messages while
reachable. The iOS bridge prepares remote data on a generation-checked worker
without rebuilding local map geometry. An application-level 60 KiB whole-context
cap reserves the remote packet budget; an oversized local map produces an
explicit cached-overlay warning while a remote clear can still travel. The
same remote revision never has two differently trimmed wire payloads.

Wear observes `Tak.items` and `Tak.status` from Android `6f9865f` plus Claude's
canonical TAK-disabled status API `56acca2`. The Wear branch's earlier evaluation
fields remain additive; the user's separate Android checkout is untouched.
Application/request callbacks publish the latest authoritative scene. Wear reuses
the phone's remote overlay renderer with a TAK label prefix and keeps watch GPS
above that layer. No watch editing or outbound TAK sharing action is added.

## Validation and limits

- Shared Swift/Kotlin golden packets contain a friendly device, accented hostile
  marker, bent line and area, with exact stable ids and stale times.
- Core tests cover all packet bounds, Unicode byte limits and omission counts,
  complete geometry, deletion/hidden replacement, wrong-order/future frames,
  clock changes, renewed vs unchanged stale times and cache relaunch/tampering.
- Native context tests cover combined budgets, retention of local map/guide data
  and an explicit map warning while a remote clear remains deliverable.

Paired radio reliability, physical wrist/touch, battery/background and real
server/client matrix checks remain required. Simulator fixtures do not prove
live on-watch server connectivity; that is deliberately not implemented.

### Verified Apple paired round

All 433 Swift core tests and 191 native integrations pass (two unstaged local
TAK opt-in skips); phone/watch/widget Release build passes. The paired 40 mm
Apple simulator received four synthetic CoT events through the real iOS TAK
scene/parser and WatchConnectivity: TEAM ONE, OP CAFÉ, a three-vertex bent ROAD
and NAI 2 area. Day/night maps and item info were inspected. Source was explicitly
a disconnected rendering preview, with no server connection or container change.

Hiding sent revision 15, disabled/zero remote items; clearing sent revision 16,
enabled/zero remote items. The one local waypoint/five field-overlay arrays stayed
byte-identical in both rounds. The corrected expiry round received revision 20
with four 45-second items, shut the phone simulator down, then relaunched the
watch. At 40 seconds the watch still showed four unexpired items; at 76 seconds
it showed zero while its raw cache still held the same four items/revision.
Local overlay arrays remained unchanged. This proves watch expiry/cache reload
without a replacement packet from the phone.

The initial app-kill-only expiry attempt is not counted: WatchConnectivity woke
the phone without test launch arguments, causing an empty test-store scene to
replace the fixture. The corrected test shuts the phone simulator down instead.

Screenshots: `/tmp/gridfix-watch-tak-day.png`, `gridfix-watch-tak-night.png`,
`gridfix-watch-tak-info-day.png`, `gridfix-watch-tak-hidden-night.png`,
`gridfix-watch-tak-phone-off-relaunch-night.png` and
`gridfix-watch-tak-expired-phone-off-night.png` in `/tmp/`.

### Verified Wear paired transport round

The user completed Google Pixel Watch setup and paired the dedicated API 37
Play Store phone with the 192 dp round Wear API 34 emulator. Both Google Data
Layer node graphs report the expected connected peer. Matching debug builds
were installed; no account credentials were handled by the test.

On 26 October, the phone's explicit synthetic CoT preview published four items
through the real `/gridfix/tak/v1` Data Layer path. The watch receiver persisted
the matching publisher/revision, names and complete geometries. Its inspected
night info screen listed TEAM ONE, OP CAFÉ, bent ROAD and NAI 2, four unexpired.
A phone clear then reached the watch as an enabled empty scene. Local empty map,
settings/target and inactive-guide payloads stayed semantically unchanged,
excluding their normal publisher timestamps/revisions; local digit/night
preferences remained unchanged. This paired round does not establish preservation
of a populated local library; the earlier standalone test covers that separately.

A new four-item scene with 45-second stale deadlines was received. The dedicated
phone emulator was shut down, and the watch process relaunched. The inspected
watch screen showed zero unexpired items while its raw cache retained exactly
the same four items, receipt anchors and revision. No receiver cache was injected
in this paired round and no server was used. Both dedicated Android emulators
were shut down afterward. Evidence: `/tmp/gridfix-wear-paired-info.png`,
`/tmp/gridfix-wear-paired-expired.png`, and before/after receiver XML snapshots
under `/tmp/gridfix-wear-paired-*.xml`.

This closes the account/setup blocker for simulator TAK transport. Physical
radio/background/battery checks, paired guidance lifecycle checks and a populated
local/remote preservation round remain. Android's current implementation passes
454 phone and 34 Wear tests, both phone Release variants and Wear Release/lint.

The phone debug build has an explicit `watchTakPreview` intent (show/expire/clear)
that parses fixed synthetic CoT into the real in-memory TAK scene, without
changing server settings or saved waypoints. Release contains only a no-op
variant. Debug transport logs count stored Data Layer items and failures without
server/user details; storing a Data Item is not evidence of delivery to a watch.

### Verified Wear standalone rendering

The 192 dp round Wear API 34 emulator renders all four synthetic remote items
over existing local fields and real emulator GPS in day/night. Map info lists
TEAM ONE, OP CAFÉ, ROAD and NAI 2. A separately seeded 18-second scene survived
process relaunch with four unexpired items, then showed zero at 30 seconds while
the private cache retained all four items/revision 7. This exercises the real
cache decoder, expiry and renderer, not paired transport. Local screenshots:
`/tmp/gridfix-wear-tak-day.png`, `/tmp/gridfix-wear-tak-night.png`,
`/tmp/gridfix-wear-tak-info-day.png` and
`/tmp/gridfix-wear-tak-expired-relaunch-night.png`.
