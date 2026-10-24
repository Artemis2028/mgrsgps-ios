# Backstops and handrails: intended behaviour

User clarification, 24 October 2026: draw straight boundary lines, introduce
kinks along the route, remain quiet anywhere inside those lines, and buzz when
a boundary is crossed. The user identified Android's `release/1.1.0` branch as
an attempted implementation, not the specification. This feature is not yet
implemented on iOS.

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

## Contract for the iOS implementation

- Draw connected straight boundary segments on the map and add/move vertices
  to make bends. Keep the permitted area clear while editing and navigating.
- Test the user's position against those boundaries, including bends and end
  backstops. A single infinite straight-leg drift band does not meet this request.
- Remain silent while inside, regardless of the phone's heading or detours
  around obstacles. Do not add reassurance/heartbeat or steering notifications
  to this boundary mode.
- Buzz on a confirmed crossing out of the permitted area. Crossing detection
  must distinguish a transition from merely remaining outside, and handle GPS
  uncertainty without repeatedly toggling at the edge.
- Preserve separate heading-guidance behaviour for users who explicitly enable
  that mode; its cues must not silently become part of boundary monitoring.

Detailed editing, rearming/reentry and iOS background notification behaviour
still need implementation and verification. Do not infer locked-screen haptic
capabilities from Android's foreground service or from iOS track recording.
