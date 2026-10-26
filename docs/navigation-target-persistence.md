# Durable navigation targets

Map-card Navigate, waypoint-list Navigate, route-card vertex navigation and the
navigation picker/clear action now prepare the waypoint snapshot on a worker.
The UI changes target or navigates only after atomic publication. Failed saves
retain the previous target and show a readable error on the originating screen.
Course ownership is respected: another selection cannot replace or clear the
locked practice target. Staging before the lock or any other library edit must
rebase before publication. A deleted target cannot be selected. A newer
selection intent cancels an older staged selection, even when no library edit
has committed yet. This follows Android's `selectNavigationTarget` generation
check and repository existence guard (`GridFixApp.kt` / `WaypointRepository.kt`
present since `d5c83ab`, inspected in the canonical tree at `56acca2`; that
last commit itself only changes the takOff stub API). Only selectedId is published for selection; unchanged
waypoint/folder arrays do not trigger needless full-library refreshes.

Guidance startup awaits durable selection before enabling GPS/haptic playback.
It revalidates cancellation, permission, foreground state, course lock, route
geometry/ownership and point-target changes after worker preparation. Cancelling
startup cannot switch the target after the worker returns.

Automatic checkpoint transitions and manual previous/next now use throwing
selection. A failed target save pauses the route before publishing the new index
or announcing a checkpoint. Retry resumes the unscored leg. Their preparation
and session writes now use [worker staging](navigation-runtime-persistence.md). The waypoint and session
files are separate commits: if selection succeeds but session persistence fails,
the route stops at its old saved index; explicit resume selects that leg again.
Relaunch never automatically starts location or haptics.

Selection snapshots request complete-until-first-authentication protection, so
after the device has been unlocked they are eligible for background writes.
Simulator does not report this file-protection attribute; neither simulator Home
backgrounding nor a file option proves physical screen-lock delivery. Physical
GPS, lock, audio/haptics, storage-pressure and battery validation remain open.

## Validation

Core staging/failure/retry/rebase/locked-course/removed-target tests pass (446
core cases). Native cases cover cancellation immediately before publication,
concurrent favourite edits, main-actor publication, failed startup selection,
failed automatic checkpoint selection and retry. Final evidence is recorded
below. No TAK endpoint, wire contract or watch transport changes.

- Core: `/tmp/gridfix-target-intent-core.log` (446 cases).
- Final native/visible UI: `/tmp/gridfix-target-intent-final.xcresult` (204 native cases including two opt-in local TAK skips; two target UI workflows).
- Actual Core Location route workflow before the final newer-intent guard:
  `/tmp/gridfix-target-final-native-live.xcresult` (203 native cases, two target UI
  cases, and pause/Home background completion/relaunch). The host feed only
  delivers simulator locations and reads the isolated test session to pace them;
  it never injects route progress. It is stopped and location cleared on exit.
- Normal coordinate/map/target/folder workflow:
  `/tmp/gridfix-target-verified.xcresult` (that normal workflow passed; the bundle
  overall failed earlier fixture/protection assertions, so it is not an overall
  passing result).
- Final phone/watch/widget Release: `/tmp/gridfix-target-intent-release.log`.
- Day/night save and clear screenshots inspected in
  `/tmp/gridfix-target-visible-screens/`; Stop navigation is beside the target
  above long guidance text. Both target UI cases pass in that bundle.
- All six CI partition/location-feed script tests and actionlint pass. The new
  target UI class is assigned once to map: 43 total UI classes, including the
  five dedicated location-feed scenarios.

Initial validation revealed an unselected test fixture and a map route covering
its endpoint marker; the DEBUG-only isolated fixture now selects an initial
waypoint and supplies a distinct marker away from route geometry. No production
navigation result is injected. One intermediate retry was refused before launch
by Simulator's busy-installation preflight; the owned phone was rebooted and
later checks reached the app. Those incomplete/failed attempts are not counted
as passing results. Simulator's absent protection attribute is not treated as
physical-device evidence.
