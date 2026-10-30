# Optional Live Activities

Settings → Live Activities is off on a fresh install. The choice stays on this
phone; importing a backup neither enables it nor clears existing consent. iOS
16.2 or later and the system's Live Activities permission are required. Earlier
supported iOS versions retain recording and navigation without this surface.

An enabled activity represents an active track recording or running navigation
session. Recording shows its name, elapsed time, saved point count and saved
distance. Navigation shows the target/route name, checkpoint progress, distance,
current grid and guide status while its fix is usable. Tap the activity to open
the corresponding recording or navigation screen. Night mode uses red ink on a
black background. This information can be visible on the Lock Screen: enable the
option only when that is appropriate for the current task.

New activities start while the app is foregrounded. Existing activities receive
updates from the app's existing location/session callbacks in the background.
Turning off the option ends activities without stopping recording or navigation.
Stopping/discarding a recording, pausing/stopping/completing navigation, losing
required permission, and recovering an interrupted session remove its activity.
A user-dismissed activity is not immediately recreated for the same session;
changing sessions or turning the option off and on permits a new activity.

Navigation freshness uses the same monotonic fix policy as guidance, with a
10-second expiry; recording GPS status expires after 15 seconds. ActivityKit's
stale state and the widget's uptime/expiry checks suppress old navigation
readouts. Numeric updates are coalesced to at most one every five seconds;
status and lifecycle changes are immediate when the OS schedules the app.
The system controls presentation and delivery, so the activity is not an alert
or a substitute for opening the app to confirm current guidance.

Live Activities do not grant background execution. Track recording, route
following and quiet-inside boundary monitoring continue to rely on their own
Core Location permissions and background modes. Boundary mode remains separate.
There is no push server or remote start, and no Lock Screen stop button in this
implementation. See [Apple's ActivityKit guidance](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities).

## Validation and remaining device checks

Manager tests cover default-off/local consent, backup isolation, system denial,
background update/end versus foreground start, pending opt-out reconciliation,
duplicate/orphan cleanup, manual dismissal and stale-fix clock/reboot behavior.
Recording/navigation integration tests exercise activity state from the actual
session objects. On the single iPhone 17 / iOS 27 simulator, all 156 app
integration tests passed, followed by both native ActivityKit workflows:
recording/background/opt-out/discard and route/start/pause/resume/opt-out.
The recording Lock Screen card was visually inspected with real simulated
Core Location delivery while locked, then in red night mode with an expired fix.
The expired card said “Waiting for fresh GPS” and retained explicitly saved totals.
Unsigned Release builds include phone, watch and activity extension. Hosted CI
must still verify its older toolchain; the preceding watch Info-label type-check
failure was split into short string expressions. Navigation Lock Screen layout
and actual hardware checks remain outstanding.

On a physical phone, verify a moving recording and an automatically followed
route with the screen locked, inspect Lock Screen and Dynamic Island text in day
and night modes, revoke precise location, dismiss an activity, and disable the
option while both sessions run. Confirm the sessions remain independent of the
option. Check stale GPS after reception loss, battery use, system Live Activity
disallowance, reboot/force-quit recovery and iOS activity lifetime limits. These
checks remain required; simulator evidence cannot establish physical haptic or
locked-screen reliability.
