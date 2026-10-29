# Foreground watch-owned routes — 29 October 2026

The Apple watch can explicitly choose a complete cached route and follow each
vertex using its own fresh precise GPS. Only full, unsimplified route features
with 2–160 points qualify. Truncated, simplified, malformed or omitted geometry
cannot become a navigation route. Map packet budgets and phone wire format are
unchanged; the route may continue from cache with the phone disconnected.

Start, Pause, Resume and Stop are local controls. Execution consent is not saved.
Start and Resume require foreground fresh precise watch GPS; only a new sample
after the action may advance. Every original CLLocation timestamp is consumed
at most once, including repeated callbacks whose uptime conversion differs
slightly. One sample advances at most one checkpoint, in order, with the whole
accuracy circle strictly inside 25m. Poor/stale/future fixes or monotonic rollback
cannot advance. Completion stays complete without restarting or falling back to
the old phone target. Automatic names use WP1 or RT1WP1; custom route names retain
their name followed by the waypoint number.

Scene/source replacement, edits, hide/delete or omission disarm the route. Scene
suspension and permission loss pause it and disarm steering. Returning requires
explicit Resume and separately Start steering. Starting wrist lane mode stops
route mode. A checkpoint submits one synchronous foreground native click, and
completion one notification. Their physical feel remains unverified.

Route steering is an explicit additional choice and still requires fresh native
watch compass input. Once armed for the current route run it transfers to the
next checkpoint, cancelling old playback and reconfirming turns. Unrelated target
changes retain the existing disarm rules. Quiet homing differs from Android's
phone default held-azimuth/heartbeat mode; see watch-own-steering.md. No background
route or steering owner is claimed.

Validation on the final source:

- All 629 core cases pass, including seven route cases covering completeness,
  ordered progression, coincident vertices and repeated source identity,
  post-Resume freshness, invalid sensors/time, scene replacement and the strict
  accuracy-circle boundary. Unsigned phone/watch/widget Release and watch
  simulator builds pass.
- Native 40mm watch receives moving fake OS GPS through three points with the
  phone off. The actual route owner logs index1, index2, then index3/complete once.
  A DEBUG launch argument selects the route via production Start after the first
  genuine simulated GPS callback. No progress, heading or cue is injected. This
  is native owner/layout evidence, not an automated user-tap claim.
- Final native navigation captures show RT1WP2/RT1WP3, distance/bearing and completion. A subsequent cold launch shows Choose route with steering off, confirming no auto-arm. Positive
  native compass/route-steering integration, native Pause/Resume/Stop taps,
  Home/lock/permission transitions and physical wrist delivery remain open.

Evidence: /tmp/mgrsgps-watch-route-source-identity-core.log,
/tmp/mgrsgps-watch-route-source-identity-release.log,
/tmp/mgrsgps-watch-route-source-identity-simulator.log and
/tmp/mgrsgps-watch-route-identity-native-console.log. Layout captures and terminal
cleanup are recorded in /tmp/mgrsgps-watch-route-active.json.

Foreground Wear route/steering now also have native virtual-sensor validation.
Broader offline/terrain transfer and physical GPS/battery/radio checks remain work. TAK remains off; real enrolled iOS/Android
exchange and renewal still require the coordinated test.

All finite GPS feeds and console parents finished/reaped, fake GPS was cleared,
the owned watch was shut down, and original preferences were restored byte-for-byte
in the final installed data container after its UUID changed. No phone/server
connection, credential, container or database operation was performed.

Claude's29October11:09 Android source review confirms that the25m whole-accuracy-
circle checkpoint rule matches the phone practice-course policy. The Android
phone does not automatically advance a saved route's vertices: it guides to a
selected target until a user or course changes it. This Apple watch route owner
is an additional capability, not a claim of matching an Android saved-route
execution feature. Wear foreground route execution is now implemented and native virtual-GPS validated (Wear92f56ea), retaining its own128-point complete-line budget. Broader physical and background route checks remain open.


## Nonconsecutive GPS replay regression

A core regression reproduced premature completion of a three-point coincident
route: source timestamp A advances WP1, newer B advances WP2, then replayed A
with a slightly newer converted uptime completes the route. Pause/Resume did
not prevent it because only the immediately previous source timestamp was
rejected. These are synthetic inputs to the actual route policy; no physical
GPS reproduction is claimed.

The route now retains a strictly increasing source-timestamp watermark for the
whole run, including Pause/Resume. A replay or older callback cannot advance,
regardless of conversion jitter. A fresh newer sample still completes, and a new
explicit Start resets the watermark. Eight route tests, including that failing
before/passing after scenario, and all 637 core cases pass with zero failures.
The final unsigned phone/watch/widget device Release build also passes.
Wear already compares the original native elapsedRealtimeNanos strictly against
its accepted sample watermark; no Wear code change is needed for this case.

Evidence: `/tmp/mgrsgps-watch-route-replay-before.log` (expected regression),
`/tmp/mgrsgps-watch-route-replay-core.log` (637 passed), and
`/tmp/mgrsgps-watch-route-replay-active.json` (parent/build status). Native
Pause/Resume/Stop gestures, physical timestamp faults and the other runtime gates
above remain open; this core regression does not close them.


## Native route-control gestures, 29 October

The watch simulator build on `49b6ce4` passes. A newly created disposable 40 mm
watchOS 27 simulator ran it with a deliberately cached synthetic RT1 (three full
vertices near 24 N / 54 E). No phone, Data Layer delivery, route consent, progress,
heading or successful result was injected. The only input after cache setup was
fake OS GPS and native Device Hub touch gestures through CUA.

Choose route → Start RT1 opened active RT1WP1 / WP1 of 3. Native Pause changed
the control to Resume. Fresh fake positions at WP1 left the summary Paused and
the target unchanged. Explicit native Resume changed the control back to Pause;
a subsequent GPS callback advanced to RT1WP2 / WP2 of 3, about 99 m away. Native
Stop route returned to Choose route with no selected waypoint. Watch compass
unavailable was shown honestly; this is not positive route-steering evidence.

The first finite feed oscillated below the production 1 m distance filter, so it
did not sustain fresh callbacks and is not counted as the complete control test.
Corrected feeds moved about 3 m between OS updates. The picker also appeared to
retain an enabled Start presentation after the fix expired, while the action
still refused it; timer-driven freshness presentation needs a focused follow-up.
No failed gesture is presented as a pass.

Current simulator build parent 69647 and setup 18630 exited 0 and were reaped.
Finite feeds 57944/31293 and final bounded feed 78174 all exited 0 and were reaped
before cleanup. The final feed ended via its owned stop marker after native Stop.
Fake GPS was cleared and disposable device 0B9015C9 was shut down/deleted. Existing
simulators and client state were untouched. No TAK/server/container/database action.

Inspected evidence: `/tmp/mgrsgps-watch-route-native-resumed-wp2.png`,
`/tmp/mgrsgps-watch-route-native-stopped.png`, CUA screenshots in this chat and
`/tmp/mgrsgps-watch-route-controls-active.json`. This closes these four foreground
control-gesture checks on this simulator; Home/lock/permission transitions,
positive compass integration and physical wrist delivery remain open.
