# Foreground watch-owned steering — 29 October 2026

Navigate now offers explicit Start/Stop steering for the cached selected target.
Consent is process-local and off by default. Start requires the foreground watch,
a target, fresh precise own GPS and calibrated own compass no older than2s; missing sensor,
target or active lane status explains disabled Start. It does not borrow phone
location/heading/guidance, infer heading from movement or start a background owner.

WatchSteeringSession uses true target bearing and native true watch heading with
the existing GuideCueState/GuideCadence rules:10-degree allowance,5-second off-course
confirmation, correction hysteresis and no periodic on-course heartbeat. During
confirmation the UI says Confirming turn, not On bearing. The current-target
bearing is followed; there is no locked initial azimuth/corridor in this first
watch owner. Shared50m arrival requires the complete GPS uncertainty circle inside;
arrival is once per approach and re-arms beyond150m, including across a sensor gap.

A250ms owned task drives age/cadence. Missing/stale/poor/future GPS or compass
clears pending turn state and playback, remains quiet and displays waiting status;
fresh recovery reconfirms a turn. Target edit/clear, permission loss, Stop or
foreground suspension disarms and requires explicit Start. Starting lane mode
stops steering; Start steering is disabled while a lane is active/preparing.
Phone guidance remains a separate read-only section. Target/settings sync with
unchanged target does not start steering or alter its consent.

Queued playback has generation, foreground, target and sensor-freshness checks at
every effect. Native watch click/notification effects approximate right(two clicks),
left(one notification), arrival(two notifications) and back-on-bearing(one click).
No background steering notification/session, workout or persistent auto-arm.
Native effect feel, watch-top orientation, positive calibrated compass callbacks
and actual physical haptic distinction remain hardware gates.

Validation:

- All622 core cases pass, including seven session cases and two display-versus-steering
  freshness boundary/reconfirmation cases: explicit consent/
  malformed target, turn hold/hysteresis/cadence, north wrap, invalid/stale sensors
  and fresh re-confirmation, target edit/clear/Stop, one-shot arrival/rearm and
  nonfinite/poor/future fixes/uptime rollback.
- Final unsigned phone/watch/widget device Release and watch simulator build pass.
- Native40mm watch controls inspected in day and night. Unsupported compass keeps
  Start disabled; the final night capture explicitly says Watch compass unavailable.
  DEBUG launch scrolling reaches the real control; this is layout/state evidence,
  not an automated user tap or positive sensor/haptic runtime pass. Only fake target
  and OS GPS are supplied; no heading/cue/session state is injected.
- All local parents/feeds reaped, watch off, fake GPS cleared and original watch
  preferences restored byte-for-byte after native installation/container changes.

Evidence: /tmp/mgrsgps-watch-steering-core.log,
/tmp/mgrsgps-watch-steering-release-final-availability.log,
/tmp/mgrsgps-watch-steering-simulator-final.log,
/tmp/mgrsgps-watch-steering-native.png and
/tmp/mgrsgps-watch-steering-native-night-final.png.
Owned handles: /tmp/mgrsgps-watch-steering-active.json.

This owner steers to the selected target or explicitly armed local route run.
Foreground route progression now has its own owner; see watch-own-route.md.
The Wear foreground counterpart is now implemented/virtual-sensor validated (Wear b184864).
Background steering and offline/terrain transfer remain
separate work. Native Home/lock/permission/positive-compass playback and physical
orientation/battery/feel verification stay open. No enrolled TAK/server proof.


## Android contract coordination

Claude's29 October10:33:30 reply was verified read-only against Android
GuidePolicy.kt and NavigationFixPolicy.kt. Both now use the2s steering-heading
gate and10s GPS gate. The5s own-heading numeric display is separate and cannot
authorize steering cues or allow queued playback after2s. The watch quiet homing
mode intentionally has no periodic reassurance heartbeat; phone default is30s
(options0/30/60). Phone also defaults to holding the leg azimuth until homing
inside100m, with optional corridor intercept. This first watch mode homes on the
current target throughout and does not implement that default lensatic/corridor
mode. Those are explicit mode differences/open parity work, not shared-default
claims. No Android source/protocol changes required.

Two freshness cases verify2s inclusive/2.001s expired while display remains fresh,
and that an expired-for-steering sample clears pending turn confirmation even
when still eligible for numeric display. Final logs:
/tmp/mgrsgps-watch-steering-two-second-core.log and
/tmp/mgrsgps-watch-steering-two-second-release.log. Both parents exit0/reaped.
