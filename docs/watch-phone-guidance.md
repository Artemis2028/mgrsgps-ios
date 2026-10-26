# Phone guidance on both watches

The watch navigation page has a separate **Phone guidance** section. It shows
what the phone navigation owner has confirmed, including the target, lane name,
NOT_YET / INSIDE / OUT_LEFT / OUT_RIGHT / OVERSHOT state and named crossed limit.
The owner's status text supplies the direction. This is read-only: no watch
haptics, independent crossing detector or background watch navigation is enabled.
Quiet-inside perimeter monitoring remains separate. Watch GPS alone supplies the
grid, map position and numeric watch-to-target bearing/distance above this section.

## Version 1 packet

Native payloads use the same JSON schema, tested with the byte-identical
`watch-guide-v1.json` fixture on Swift and Kotlin. WatchConnectivity uses the
`gridfix.guide.v1` key; Wear Data Layer uses `/gridfix/guide/v1`, string `snapshot`.

| Field | Meaning |
| --- | --- |
| version | 1 |
| sourceID / revision | Stable publisher identity and durable increasing publication counter |
| at | Publication time, epoch milliseconds |
| active / available | Guide running / source decision currently usable |
| targetName / status | Phone guide target and current owner status text |
| laneName / laneState / crossedLine | Optional confirmed lane decision and crossed limit label |

An inactive packet explicitly clears target/lane. Missing optional values decode
as null. Unknown versions/states, inconsistent activity/lane fields and packets
over 4096 bytes are refused. Names are bounded to 480 UTF-8 bytes and status to
640. Delayed lower revisions cannot undo a stop/new state; conflicting equal
revisions are refused. A different publisher must not be older than the cache.
The packet carries no own-position coordinates or haptic commands.

Publish on changes, about every five seconds while guiding, on watch refresh
and when the guide stops. A packet expires after 20 seconds; more than two seconds
in the future is also unavailable. The UI displays expiry/unavailability instead
of cached steering text, retains explicit source/age and labels no watch alerts.
The full cache can remain for offline inspection but is never a live detector.
Delivery is best effort; background execution and radio delay can expire it.

## Owner adapters

- iOS reads `NavigationSession` after its own permission/fix/heading and debounced
  lane decisions. Usability additionally requires that its evaluation loop ran
  within two monotonic seconds. A transport heartbeat cannot refresh that clock.
  WatchConnectivity retains a complete application context, with immediate
  messages while reachable. Guide-only updates do not rebuild map geometry.
- Wear phone branch incorporates Android review `eacf084`; it observes
  `PocketGuideService.active`. The only service additions are the immutable
  `WatchGuideEvaluation(runId, elapsed, available)` value, updated after each loop
  evaluation and reset on stop. The adapter checks matching run, monotonic age
  and explicit availability before publishing. Notification/decision flow cadence
  and geometry/haptic logic are unchanged. No changes to Claude's checkout.

Physical paired delivery, locked-phone behavior, sustained radio/battery and
clock changes need field testing. Neither platform promises five-second delivery
while suspended. Watch-only background guidance, TAK scenes and offline packs/
terrain remain separate implementation gaps.

## Local validation on 26 October

- All 426 Swift core tests pass, including seven byte-identical cross-platform
  golden packets, bounds, explicit clear, reordered/conflicting revisions,
  unavailable/future/expired presentation. All 189 native integrations pass (two unstaged local TAK opt-in skips),
  including all 17 navigation cases with actual owner decisions, suspended-loop freshness, expired fix,
  named crossing and stop clearing.
- Android passes 419 phone and 28 Wear unit tests, phone/watch debug and Release
  builds, phone R8 and Wear Release lint. Adapter tests reject stale/wrong-run/
  future evaluations and export explicit inactive packets.
- A paired 40 mm Apple Watch simulator received the real native iOS session
  over WatchConnectivity. Real simulated Core Location fixes yielded INSIDE,
  then OUT_LEFT with Creek bank and turn right. Clearing phone fixes yielded
  unavailable; stopping with the native toggle delivered revision 81 with no
  target/lane. A new active INSIDE run was terminated on the phone; at 36 seconds
  the watch showed expired instead of steering. Day/night screenshots inspected.
  A DEBUG-only initial scroll flag exposes the existing guidance section for
  screenshots; packet data came from the real paired phone, not a seeded watch
  decision. No server or TAK connection was involved.
- Release phone, embedded watch and ActivityKit extension build passes.

Local screenshots: `/tmp/gridfix-watch-guide-crossing-day.png`,
`/tmp/gridfix-watch-guide-unavailable-night.png`,
`/tmp/gridfix-watch-guide-stop-night.png`,
`/tmp/gridfix-watch-guide-expired-night.png`. Physical watch and Wear paired
Data Layer checks remain required.


The later [paired Wear validation](wear-paired-validation.md) verifies actual
phone-service active/unavailable/stop/expiry delivery through Data Layer with a
populated local library. Physical and named-crossing Wear checks remain.
