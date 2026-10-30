# Phone guidance expiry on the watches

Both companions display read-only phone decisions separately from their own
watch GPS metrics. Those decisions do not run watch crossing detection or
haptics. Their wire packet and 20-second source lifetime are unchanged.

Previously the displayed freshness used wall-clock time alone. Moving the
watch clock backward could make an old cached decision appear fresh again.
Each receiver now retains a local receipt wall time, monotonic uptime and
expiry deadline. The deadline is the packet's remaining source lifetime,
capped at 20 seconds from receipt. Duplicate delivery or another revision with
the same/older timestamp cannot extend the existing deadline. A genuinely newer
timestamp can start a new budget. An older/conflicting revision remains refused.

The display requires both the original source-age check and an unexpired
monotonic deadline, with wall-clock passage agreeing with monotonic passage
within two seconds. A clock step hides guidance while that test fails; restoring
the clock cannot extend the original deadline. Lower uptime after reboot fails
closed. Local receipt metadata survives app relaunch instead of being reset
when a Data Item or application context is reread.

Only the local cache schema changes: no phone packet, preference, map, target
or TAK protocol changes. Legacy caches keep ordering metadata but are expired
until a newer phone packet arrives, because they have no receipt proof. Corrupt
or oversized cache data is refused. Displayed expiry clears steering/limit
text while preserving the separate watch position and cached local map.

## Automated evidence, 27 October 2026

- 504 Swift core cases pass, including forward/backward clock steps, replay,
  same-timestamp revisions, source ordering, cache reload, lower uptime,
  legacy caches, malformed data and new fresh packets.
- 39 Wear unit cases pass with corresponding receipt/cache vectors and the
  existing shared seven-decision fixture. Wear Debug/Release builds and Release
  lint pass; the Android phone Debug build passes.
- Apple phone/watch/widget Release and paired Debug build pass. Prior native
  session/bridge tests remain separate evidence; no new real-server round is
  involved. Physical clock/wrist/radio/battery behavior remains unverified.

## Runtime evidence

Only one owned pair runs at a time. No watch packet or cache is injected;
clock steps use explicit unit-test clocks, with real Mac/device clocks unchanged.

The paired Apple Watch receives a real iOS navigation-session INSIDE decision
through WatchConnectivity, with the remaining receipt budget persisted in its
new cache. After phone termination it shows expiry on relaunch. A WatchConnectivity
request can wake the phone and produce a genuinely new off decision; that is a
replacement, not replay or proof that the old cache renewed. After restoring
the prior phone test workspace and shutting down its simulator, a duplicate
context on watch relaunch keeps revision 154's exact existing deadline while
guidance remains expired. Watch grid/night overrides remain unchanged.
Screenshots: `/tmp/mgrsgps-guide-clock-apple-active.png`,
`/tmp/mgrsgps-guide-clock-apple-expired-relaunch.png`, and
`/tmp/mgrsgps-guide-clock-apple-disconnected-cache.png`.

The real Android phone service and paired Data Layer deliver available steering
for the original PAIRED LOCAL CAFÉ target. Runtime inspection found the UI was
initially comparing a new receipt with the previous one-second redraw uptime,
briefly displaying expired. Guidance now samples current elapsedRealtime at
render instead; the timer only triggers redraw. Four consecutive UI snapshots
across new source revisions retain live decisions with no false expiry.
The first candidate screenshot is retained as failure evidence, not a pass.

Force-stopping the phone was insufficient for an isolated cache test: a watch
request triggered a new inactive source packet. The final check shuts down the
phone emulator entirely. Active revision 231 and its exact deadline survive watch
app relaunch unchanged; expiry replaces steering while watch GPS remains fresh.
The original complete local map, selected target/settings and local digit/night
overrides compare equal apart from normal publisher revision/timestamp fields.
Final screenshots: `/tmp/mgrsgps-guide-clock-wear-active-final.png` and
`/tmp/mgrsgps-guide-clock-wear-offline-expired.png`; cache/UI evidence uses the
matching `/tmp/mgrsgps-guide-clock-wear-*.xml` and JSON files.

The original Android target/local-map/digit/night state remains preserved and
the phone native toggle is verified off at cleanup. The Wear emulator host
process aborts with exit 134 after the final expiry capture, before final inactive
replacement receipt can be checked; no claim is made for that cleanup delivery.
This is a host-emulator failure, not proof of an app crash. Both Android devices
and all Apple devices and owned fake feeds are off afterward. Physical
clock/wrist/radio/battery testing remains open; this does not add independent
watch haptics or background guidance.
