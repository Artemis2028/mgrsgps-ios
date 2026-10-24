# Backstops and handrails: intended behaviour

User clarification, 24 October 2026: draw straight boundary lines, introduce
kinks along the route, remain quiet anywhere inside those lines, and buzz when
a boundary is crossed. The user identified Android's `release/1.1.0` branch as
an attempted implementation, not the specification. The iOS implementation now follows that description.

## Android attempt inspected

Source: `Artemis2028/gridfix`, `release/1.1.0`, commit `482b417`.
No pull request for that branch was returned by GitHub at inspection time.

`GuidePolicy.kt` adds `GuideConfig.corridorM` with UI options Off, ±50, ±100,
and ±200 metres. `PocketGuideService.kt` anchors a single leg at the first usable
location when guidance starts, with the selected target as the other endpoint.
Cross-track distance is measured against that straight leg line. In hold-azimuth
mode, crossing the configured width changes the desired steering reference to
an intercept heading toward the line. Its outside state has 20% hysteresis.
Within 100 metres of the target it switches to homing and stops applying the
corridor.

This remains a heading guide: heading error can produce cues even inside the
corridor, heading availability is required, and outside-corridor status does not
itself emit a crossing event. The default on-course heartbeat is 30 seconds,
though it can be turned off. There is no boundary drawing/vertex editing, bent
boundary model, or explicit end backstop in the inspected implementation.

Relevant sources:

- [Guide policy](https://github.com/Artemis2028/gridfix/blob/482b417/app/src/main/java/app/gridfix/android/location/GuidePolicy.kt)
- [Pocket guide service](https://github.com/Artemis2028/gridfix/blob/482b417/app/src/main/java/app/gridfix/android/location/PocketGuideService.kt)
- [Guide settings](https://github.com/Artemis2028/gridfix/blob/482b417/app/src/main/java/app/gridfix/android/ui/screens/SettingsScreen.kt)

## Drawing and editing on iOS

Open **Map → shield (Backstops and handrails) → Draw boundary**. Tap points in
order around the area you want to stay inside. Each pair is joined by a straight
line, and the final point joins the first to form the closing backstop. A light
fill shows the permitted interior once the perimeter is valid.

Long-press and drag a numbered point to move it. Drag a small **+** handle to
add a new point along a side, including the closing backstop. Tapping **+** inserts
a point there too. For an accessible alternative, select a point, pan the
crosshair and choose **Move here** or **Add point**; Add point inserts after the
selection. The trash button removes the selected point. Pinch and pan remain available while drawing; double-tap
zoom is disabled so rapid drawing taps cannot unexpectedly zoom.

The GPS marker is hidden while editing so it cannot intercept vertex drags;
Locate remains available. The crosshair is anchored to the map camera centre.

Give the boundary a name and Save. Cancel leaves the saved version unchanged.
A saved boundary can be shown, edited, monitored or deleted. Stop monitoring
before editing/deleting; one boundary can be monitored at a time. Lines cannot
cross, self-touch, or double back. Perimeters support 3–256 vertices, at least
25 square metres, within 100 km of the first point, between 80°S and 80°N.
These are local field boundaries, including areas crossing the dateline.

## Crossing behaviour

Position alone drives this mode; heading and the compass face have no effect.
There are no steering cues, reassurance pulses, arrival buzzes or heartbeats.

The uncertainty circle of a fresh precise fix must lie clearly on one side of
the perimeter: accuracy at most 25 m, fix age at most 10 seconds, and distance
from the boundary greater than the reported accuracy or 3 m, whichever is larger.
Two distinct fixes at least two seconds apart on that side confirm a transition.
This deliberately delays alerts past the drawn line when GPS uncertainty overlaps
it. A brief excursion or a crossing between fixes may not be observable.

- Confirmed inside: quiet and armed, anywhere inside, including bends.
- Confirmed inside → confirmed outside: one exit alert.
- Remaining outside: quiet, with an outside/re-arm status. No repeated buzzing.
- Confirmed return inside: quietly re-arm for the next exit.
- Starting outside: show outside and wait for entry; do not invent an exit.
- Uncertain, stale or inaccurate fixes: show an unknown/edge state and do not
  infer a crossing. A gap resets pending confirmation, retaining the last
  confirmed side. After GPS returns, fresh fixes can confirm the new side.

The detector uses the same straight Web Mercator edges shown on the map, with
local ground scaling for boundary distance. Concave perimeters, bends, every
closing edge, dateline wrapping, invalid geometry, jitter, reordered fixes and
re-entry are covered by core tests.

## Screen locked and background operation

Start **Monitor** with the app open. The dedicated location manager uses Precise
When In Use authorization, best-for-navigation updates, no distance filter,
background location updates and the system background-location indicator, with
automatic location pauses disabled. It is independent of both the foreground
position manager and the track recorder. Recording and boundary monitoring can
run together. Stopping one does not stop the other's manager.

While the app is active, an exit requests a warning haptic without audio. When
backgrounded or locked, an exit requests a local, time-sensitive notification
with the system notification sound. The build includes the time-sensitive
notification entitlement. iOS controls sound/haptics, Focus, lock-screen
presentation and whether time-sensitive alerts are allowed. Notification
permission is requested when monitoring starts. Denying it still permits the
foreground haptic, and the monitoring panel explicitly reports the limitation.
There is no public guarantee of a vibration-only locked-screen alert; this app
does not claim one or request critical-alert privileges.

An all-tab banner shows the active boundary and GPS/monitoring status. The panel
shows exit count and notification availability. Location/precision permission
loss stops monitoring and preserves boundaries. Temporary GPS loss stays visible
without inventing a safe position. Force quit, reboot or OS termination can end
monitoring: after relaunch, show an interruption notice and require an explicit
restart. No automatic GPS session is started at launch.

Boundaries and the active-session marker are written atomically to
Documents/boundaries-v1.json with Complete Until First User Authentication file
protection. Corrupt files are kept and not overwritten. Failed edits leave saved
records intact. Boundary definitions are currently separate from version-1 field
backup/GPX exports; those formats have no Android boundary contract.

## Verification and platform references

Local tests include pure geometry/detection tests, injected-driver integration
checks for background transitions, permission loss, failed persistence and
interrupted sessions, plus real simulator map drawing/dragging/persistence and
Core Location crossings while backgrounded. CI feeds a moving inside/outside
route from the host; it does not synthesize location callbacks inside the app.
A separate route is used for the existing track-recording workflows.

A physical iPhone walk test with the screen locked is still required before
release: confirm foreground haptics, local notification delivery, Focus/Silent/
notification settings, GPS accuracy at the edge, concurrent recording, battery
behaviour, and interruption/relaunch. Simulator background delivery does not
verify physical vibration, locked-screen Data Protection, or iOS scheduling.

- [Apple: background location updates](https://developer.apple.com/documentation/corelocation/cllocationmanager/allowsbackgroundlocationupdates)
- [Apple: choosing location authorization](https://developer.apple.com/documentation/corelocation/requesting-authorization-to-use-location-services)
- [Apple: requesting notification permission](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications)
- [Apple: local notification delivery](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app)
