# Foreground wrist lane alerts

29 October 2026. Both wrist apps can explicitly start a cached navigation lane
using their own precise, fresh GPS. Receiving a phone guide packet never arms
this session. The separate quiet-inside perimeter monitor remains separate.

Choose lane on Navigate, then Start a named lane. Entry requires two distinct
acceptable fixes. The existing phone lane geometry, crossing confirmation and
outside reminder cadence apply: named left/right limits and a bent backstop;
inside/return are silent, and a not-yet-entered lane does not buzz. Wear includes
the production pure Kotlin lane sources rather than a second geometry algorithm.
watchOS uses the existing Swift phone lane engine.

Fixes older than ten seconds, worse than25m, invalid, future-dated or unavailable
cannot confirm a crossing. Loss of a usable fix clears pending confirmation and
cancels playback. A changed/removed lane stops the session. Suspension stops it;
returning to the app requires explicit Start again. Consent is not persisted.
This milestone is foreground only. Background guidance remains implementation
work; it is not declared impossible on either platform.

Wear uses the phone waveform with VibrationEffect. watchOS schedules native click
and notification effects at the waveform's pulse boundaries; it does not claim
arbitrary vibration duration/amplitude. Distinction, comfort and timing on a
physical watch remain required checks. No workout or unrelated runtime session
is used to keep the app alive.

Validation so far:

- Full Swift core suite:561 cases, zero failures in
  /tmp/mgrsgps-wrist-full-core.log. Four new session cases cover local consent,
  fresh entry, left/right/bent-backstop, silent return, duplicate/stale/missing
  fixes, invalid replacement and explicit rearming after scene/lifecycle changes.
- Four matching Wear session tests pass; debug/release APK builds and release
  lint pass. Existing Android phone lane tests also pass after the additive
  invalidateFix helper. Logs: /tmp/mgrsgps-wear-wrist-build-jdk17.log and
  /tmp/mgrsgps-wear-wrist-release-lane.log.
- Unsigned phone/watch/widget device Release and watch simulator build pass:
  /tmp/mgrsgps-wrist-lane-release.log and
  /tmp/mgrsgps-wrist-lane-watch-simulator.log.
- Runtime crossing/cancellation verification on the new wrist owners is still
  open. Earlier real paired delivery tests prove scene/phone-guide transport,
  not this independent watch session or physical haptics.

Background follow-up: the installed watchOS SDK marks
CLLocationManager.allowsBackgroundLocationUpdates available since watchOS4,
CLBackgroundActivitySession since watchOS10 and heading updates since watchOS2.
Apple documents watchOS background location support in
[Handling location updates in the background](https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background).
The current foreground owner deliberately stops on suspension; a real background
owner, explicit session/stop controls and runtime/device validation remain to do.

Runtime follow-up caught and repaired a watchOS render loop before committing:
writing the observed session from TimelineView.onChange recreated its .now
schedule. A sample showed main-thread SwiftUI layout spinning at93.6% CPU with
1.4GB footprint. The timer now uses a cancellable one-second task outside that
schedule; the rebuilt process sampled idle at0% CPU/~205MB RSS and the native
lane Start action responds. Diagnostic callbacks report only age/accuracy and
permission/foreground booleans under a DEBUG-only launch argument, no position.
The paired simulator must be connected for this runtime's simulated location
callbacks; watch-only set commands left an old fix and correctly showed Waiting.

Final40mm watchOS runtime: a labeled synthetic cache fixture (previous preferences
backed up) and real Core Location simulator callbacks, with the paired companion
simulator connected, drive Inside, named Creek/left, Road/right, return and bent
Power line/backstop states. No phone guidance decision or watch session state
was injected. Inspected captures: /tmp/mgrsgps-wrist-watch-final-inside.png,
-final-left.png, -final-right.png, -final-return-recovered.png and
-final-backstop-fresh.png. A feed ending during the first backstop attempt
correctly replaced guidance with Waiting at14s; the fresh repeated attempt
shows the backstop. This establishes UI/owner integration, not physical vibration.
Active wrist decisions now precede unselected phone targets so the named limit
and Stop control fit the40mm viewport. Final device Release passes in
/tmp/mgrsgps-wrist-final-release.log. Wear runtime remains open.

Pressing the native crown and returning to the same process shows Paused · start
wrist alerts again; it does not rearm. Capture:
/tmp/mgrsgps-wrist-watch-final-resumed.png. All owned fake feeds ended naturally
and their handles were reaped. The synthetic map/night preferences were restored
after shutting down the owned watch and paired phone. No other simulator ran.

## Wear foreground runtime — 29 October 2026

The actual Wear API34 emulator (384×384 pixels,320 dpi,192 dp round) now runs
independent wrist alerts with native LocationManager callbacks. Only that watch
was booted; no paired phone or TAK server participated. Its original companion
preferences were backed up and restored byte-for-byte. Synthetic lane geometry
was staged in the ordinary cache; no lane decision, guidance state or haptic
result was injected. Earlier paired transport evidence remains separate.

Runtime exposed a product UI defect: long Choose/Stop/Cancel labels used round
CompactButtons and were clipped; active guidance was buried below target data.
They now use wide chips, the lane picker uses wide multiline rows, and an active
wrist session moves to the top with its lane name, decision and Stop visible.
Starting/revisiting Navigate scrolls to this active section. Ordinary waypoint
metrics, read-only phone guidance and the separate quiet-inside mode remain.

Verified states and Android vibrator-service evidence:

| State | Visible result | App vibration request |
| --- | --- | --- |
| Fresh inside | Inside lane | None |
| Past left Creek | Past Creek · turn right | 0,70,90,70 ms: two short pulses |
| Return inside | Inside lane | No new request; latest app-vibration timestamp unchanged during quiet hold |
| Past right Road | Past Road · turn left | 0,300 ms: one long pulse |
| Return inside | Inside lane | Latest app-vibration timestamp unchanged during quiet hold |
| Past bent Power line | Past Power line · turn back | 0,300,200,300,200,300 ms: three long pulses |
| Aged valid fix | Waiting for watch GPS | Requests stop; latest app-vibration timestamp stays unchanged |
| Fresh recovery outside | Past Power line · turn back | Recovered decision/cue |
| Home, then return | Paused · start wrist alerts again | Same app PID; requests stay stopped, explicit rearm required |
| Explicit Start while outside | Not in lane yet | Silent; no auto-entry into a previously armed session |
| Explicit Stop | Wrist alerts off | Disarmed |

The emulator continues generating fresh GPS locations at its last coordinate
when geo-fix commands stop; stopping the host feed did NOT prove age expiry.
For that check, Android's OS test GPS provider delivered one valid5m fix and no
further locations. The recorded location elapsed time was18m30.369s versus
1154.23s uptime (>43s old), and the real owner displayed Waiting. The temporary
provider override was removed; the shell mock-location app-op was restored to
its original default-deny mode. Its access-history timestamp naturally remains,
so an initial cleanup assertion comparing the entire diagnostic text was too
strict; the actual mode is restored. Fresh ordinary emulator GPS then recovered
the backstop state. No production permission policy was bypassed.

Evidence paths: /tmp/mgrsgps-wrist-wear-{inside,left,return-left,right,return-right,
backstop,stale,recovered-backstop,resumed,day-active,stopped}.{png,xml}; matching
-vibrator.txt captures contain the native service's original/played effects.
Quiet-hold captures and stale-location.txt preserve the timestamp checks.
All key inside/crossing/backstop/day/resume captures were visually inspected.
Day and night show a complete active status and wide Stop on the small round
screen. An initial native UI script missed controls during scroll/animation;
fresh hierarchy reads and actual taps subsequently complete the same journey.

All46 Wear unit cases pass; Debug/Release APKs and Release lint pass in
/tmp/mgrsgps-wrist-wear-controls-build.log. GPS feed and emulator parents exited
naturally after cleanup; adb inventory shows no devices. No extra iOS simulator
was booted. This closes the foreground Wear runtime gate, not independent
background/heading/route following or physical vibration/radio/battery checks.
The vibrator service proves requests/effect timing, not physical wrist feel.
