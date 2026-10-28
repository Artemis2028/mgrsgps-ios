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
