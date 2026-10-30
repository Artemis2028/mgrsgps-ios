# Automatic route following and haptic navigation

Reference: GridFix Android `release/1.1.0`, commit `482b417`, inspected
24 October 2026. `GuidePolicy.kt`, `PocketGuideService.kt`, and
`NavigationFixPolicy.kt` define haptic guidance. Android's automatic advancement
is currently its course engine in `GridFixApp.kt`, not a standalone route-follower
screen. iOS applies its checkpoint rule to ordered saved route vertices.

## Use

Open Waypoints → Routes & tracks → a route → **Follow route automatically**.
Route-owned waypoints are generated with stable IDs, beginning at vertex one.
Navigate shows point number/count, Pause/Resume, Previous/Next point and the
haptic guide switch. Route following and the guide require an explicit visible
start with Precise When In Use location permission. Route progression can continue
with steering haptics disabled. Choose **Stop navigation** to end the session;
Pause retains the current route point. Resume starts from that point.

Each fresh location can advance at most one route vertex. The full accuracy
circle must fit strictly inside 25 m (`distance + accuracy < 25`), matching
Android course scoring. Navigation fixes must be at most 10 seconds old with
accuracy at most 25 m. Missing/stale/coarse fixes cannot score. The haptic
arrival cue is separately triggered inside the 50 m ring, once per target,
rearming beyond 150 m or on target change. A route advance gives a short tick;
the final point gives the completion pattern and stops background updates.

The route snapshot and current point are saved before publishing advancement.
Failed writes stop navigation and retain the unscored point for retry. Pause,
resume and manual Previous/Next are persistent. A changed/deleted route or
missing/edited generated waypoint pauses navigation; restart the route to use
its current geometry. Choosing a different waypoint pauses a route rather than
forcing the old target back onto the screen. An active single-waypoint guide
retargets to the chosen waypoint and cancels old feedback. Metadata-only edits
do not reset the held leg. Restoring progress never restarts GPS automatically.

## Android guide policy

Defaults and Settings/backup field names match Android:

| Setting | Default | UI choices |
| --- | --- | --- |
| `guideAllowance` | ±10° | 5, 10, 15, 20, 30° |
| `guideHoldOffSec` | 5 s | at once, 3, 5, 10 s |
| `guideHeartbeatSec` | 30 s | silent, 30, 60 s |
| `guideMode` | hold azimuth | hold azimuth / home on point |
| `guideCorridorM` | off | off, ±50, ±100, ±200 m |

Restored valid custom values remain selectable. Changes apply live. Settings
also appear in Android-compatible complete backups; old files get the Android
defaults. A held leg is anchored at its first usable fix. Within 100 m of the
target it homes on the point. Outside the straight leg's optional drift corridor
it requests an intercept toward the leg. Heading allowance uses up to 3° of
hysteresis; drift-corridor reentry uses 80% of the exit width. Correction must
persist for the configured hold-off. Returning clearly on course gives one short
tick, followed only by the configured optional heartbeat.

The phone's top edge points ahead. Two short taps mean right; one long pulse
means left; three taps mean unavailable; two long pulses mean arrival/completion.
Android's durations and repeat cadences are reproduced by the foreground Core
Haptics player. Lack of supported haptic hardware is reported rather than
presenting indistinguishable fallback vibrations as precise direction patterns.
Silence never proves a valid bearing.

The guide owns a separate fixed-portrait heading manager. Samples must be no
older than two seconds, with a finite magnetic heading and estimated angular
accuracy at most 25°. True heading uses the user's declination override or the
bundled WMM. A device without a compass may use a fresh GPS course while moving
above 0.5 m/s, with a usable course-accuracy estimate. Devices that have a compass
do not substitute travel direction for a missing/stale reading. Simulator has
no magnetometer and must not pretend its heading is north. Sample ages are
translated to uptime on receipt; wall-clock changes reset sample ordering while
retaining ordered route progress.

## Background and boundary separation

GPS uses an independent background driver and system location indicator. Route
arrival/advance/completion notifications can be requested while backgrounded or
locked. iOS notification permission, sound/haptic settings and Focus control
actual delivery. The guide's custom steering patterns are foreground-only;
background correction and heartbeat notifications are deliberately suppressed.
No silent-audio loop or extra background mode is used to keep a haptic engine
running. Screen-lock GPS, heading delivery and physical vibration still need a
physical-device walk test before release.

Boundary monitoring is a separate position/perimeter detector and separate
notification channel/IDs. It never reads guide tolerance, drift corridor,
heartbeat or heading. Explicitly enabling the guide while a boundary is active
can produce **navigation** cues inside that boundary; the UI states this. The
boundary detector itself stays quiet inside and reports only confirmed exits.
Stopping navigation does not stop recording or boundary monitoring.

Only route progress/session state is stored in `navigation-session-v1.json`,
with atomic writes and Complete Until First User Authentication protection.
Interrupted navigation resumes only on explicit user action. Corrupt state is
kept; Clear saved navigation session preserves the damaged file separately and
leaves routes/waypoints intact. Live route progress is separate from version-1
field backups; guide preferences are included in those backups.

## Validation

Core tests use Android's documented guide test vectors for hold-off, hysteresis,
intercept direction, near-point homing, missing headings, signed north wrapping,
arrival rearming and pulse cadence. App tests exercise ordered fresh-fix scoring,
pause/resume, interrupted launch, heading expiry, permissions, route edits,
failed writes, clock changes and independence from the quiet boundary detector.
A host-side moving simulator feed tests actual background advancement and route
completion through the native UI. Physical direction-pattern fidelity and
locked-screen behavior remain device validation work.

- [Android guide policy](https://github.com/Artemis2028/gridfix/blob/482b417/app/src/main/java/app/gridfix/android/location/GuidePolicy.kt)
- [Android automatic checkpoint engine](https://github.com/Artemis2028/gridfix/blob/482b417/app/src/main/java/app/gridfix/android/ui/GridFixApp.kt)
- [Apple: haptic engine preparation and background interruptions](https://developer.apple.com/documentation/corehaptics/preparing-your-app-to-play-haptics)
- [Apple: heading and course are different inputs](https://developer.apple.com/documentation/corelocation/getting-heading-and-course-information)
