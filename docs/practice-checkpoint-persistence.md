# Random course checkpoint persistence

Android reference: `release/1.1.0` at `482b417`,
`GridFixApp.kt` onStartRandom (around line 1449), and `WaypointRepository`.
Android scatters separated points, saves CP 1…n in a course folder, then starts
the course and selects the first checkpoint. End retains these ordinary saved
waypoints. iOS keeps that order and the existing 120 m separation/count/radius
rules.

Random generation and waypoint snapshot encoding/staging now run on workers.
The main executor owns brief revision-checked atomic publication and UI/session
state. One immutable PracticePointsEdit keeps generated coordinates, UUIDs,
names and creation time across library revision rebases and explicit retries.
Preparation preserves concurrent edits and selection, enforces the combined
10,000-waypoint limit, and refuses a conflicting existing generated ID rather
than overwriting its saved point. Folder matching uses the current snapshot.

The app first acknowledges the library commit, then captures course start time
and stages the course file. There is no suspension between library acknowledgement
and advancing the retained request to the course phase. A later course-save retry
therefore never appends again or resurrects a generated checkpoint deleted in the
meantime; existing missing-checkpoint policy pauses that course. Library failure
retains the proposal for explicit Retry. Timer/fix callbacks do not retry it.
Cancel start discards the unsaved proposal or leaves already saved points alone.
The wording is simply “Cancel start”, covering either failure phase.

While either worker is running, the existing Saving course state disables another
start. Closing its sheet does not cancel an accepted operation. A bounded UIKit
background task gives an in-flight save a chance to finish, without granting
indefinite background execution. No new location permission or scoring behavior
is introduced. Ordinary guidance remains available when a start fails before a
durable course exists.

If the process dies before checkpoint publication, the proposal was never saved.
If it dies after publication but before the course commit, the saved folder/points
remain for a normal From folder start. The in-memory retry proposal is not a
persistent multi-file transaction or a promised crash-resume operation.

## Validation

- 454 core tests pass in `/tmp/gridfix-random-points-core-final.log`, including
  five new tests for rebase/selection preservation, failed publication, stable
  retry/idempotency/conflict protection, wrong store/invalid/damaged input and
  the combined waypoint cap.
- All 22 practice integrations pass in `/tmp/gridfix-random-points-native.xcresult`.
  Four new tests block the actual preparation on a worker and verify no early
  publication, library rebase, stable retry, cancellation without a new folder,
  and no resurrection after a post-commit course-save failure. Existing scoring,
  target lock, result recovery and End checks remain.

- Final native day/night UI cases pass in
  `/tmp/gridfix-random-points-ui-final.xcresult`: actual empty-directory write
  failure, visible retry, closing/reopening, repaired save, process relaunch,
  End, and searching each of the five retained checkpoints. Exported day/night
  failure and reopened-course screenshots were inspected.
- The earlier `/tmp/gridfix-random-points-ui.xcresult` passes the existing normal
  random-start workflow but fails both new cases at their final library checks.
  The initial test used a nonexistent search label and assumed a system tab bar
  in night mode. It now uses actual library search and the night field tabs;
  all five point checks remain. That mixed bundle is not an overall pass.

- Final phone/watch/widget simulator Release passes in
  `/tmp/gridfix-random-points-release.log`. The feed is stopped/cleared and the
  owned test phone is shut down. No other simulators or server were used.

This checkpoint is initially committed locally while hosted run 40273435731
validates the preceding pushed settings revision 9bb27fc. Holding the push avoids
cancelling that full run; its result will be recorded separately before the next
combined push. A pass on the preceding revision would not validate this change.

Practice target-lock selection still encodes/writes the full library synchronously;
startup reads and damaged-course preservation also remain work. This milestone
only migrates random generation/checkpoint-library writes. Full hosted CI and
physical-device checks remain separate gates.
