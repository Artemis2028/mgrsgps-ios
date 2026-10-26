# Practice target persistence

Android reference: `release/1.1.0` at `482b417`, `GridFixApp.kt`
selectNavigationTarget and the course validation effect (around lines 310–376).
Android lets the durable course own selection, retargets an existing guide after
selection, and stops guidance for a blocked/missing checkpoint. It checks the
latest selection generation, guide run and course before retargeting. These
guards predate the later TAK branch (since d5c83ab).

The iOS app now stages practice target JSON and files on workers, including
initial/recovered locks, scoring transitions, missing-point clearing, End and
completed-result unlock. The durable course file owns the lock; target preference
failure cannot make ordinary selection available for an active course.

`beginPracticeSelection` closes the in-memory gate before any suspension. It
sets the course's desired selection and marks it pending, invalidating older
ordinary selection intents and library revisions. A desired target during this
phase is not an acknowledged navigation decision. Ordinary selection is refused,
including a new guide start and the brief pending unlock after End/completion.
The immutable snapshot prepares the full JSON and protected temporary file on a
worker. The publication checks store identity, owner intent and library revision;
rebases preserve intervening edits. Only successful atomic publication clears
pending. The course itself remains the recovery authority after process death;
this preference phase does not create a multi-file transaction.

The app checks the same saved course, load-error state and available checkpoint
IDs before and after each worker await. A removed future checkpoint cancels the
old target, durably pauses the course, and clears its selected target while
retaining the lock. End cancels an outstanding target task; a late result cannot
relock the course or overwrite a subsequent ordinary choice. Errors retain a
stable explicit retry and pause guidance. Timers/fixes cannot start another save
attempt. Damaged-course warnings remain visible even if saving the target gate
succeeds.

An already running guide invalidates its old feedback session (including queued
notification submissions) and holds steering decisions while the target saves,
then retargets and continues after acknowledgment. It does not restart after Stop
or a failed save. The phone, watch guidance snapshot and optional Live Activity
report saving/unavailable during that phase. The route/steering cadence cannot
emit against the previous checkpoint while a new target is pending. The separate
Found buzz follows the acknowledged course score; it is not a promise that the
next-target preference has already saved. A stable missing-checkpoint course
still stops the guide. Quiet-inside boundary monitoring is unchanged.

The existing bounded UIKit save lease is used; this is not indefinite background
execution or a new location permission. Startup reads, damaged-course preserve/
reset copying, older library actions and physical locked-screen validation remain
work. The public synchronous setter remains for compatibility/core setup; the
application's practice flow no longer calls it.


## Validation

- 460 core tests pass in `/tmp/gridfix-course-target-core-final.log`. Six new
  target cases cover the pre-I/O gate, acknowledgment, revision rebase, newer
  owners/pending unlock, deleted targets, write failure/retry and wrong store.
  The ordinary-selection regression now explicitly expects CancellationError
  after a course supersedes its staged intent; rejection remains required.
- Final full native suite: 234 cases, two opt-in local TAK skips, zero failures,
  `/tmp/gridfix-course-target-native-notification.xcresult`. Seven new practice cases
  block actual worker preparation, verify no premature guide start/cues or
  available watch status, then verify automatic retarget, Stop preservation,
  End cancellation, missing-point clearing, explicit retry and damaged warnings.
  Existing practice unlock/reset tests now await acknowledgment instead of
  asserting immediately after an asynchronous retry.
- Four real-location UI cases pass in `/tmp/gridfix-course-target-ui.xcresult`:
  day/night target-file failure, repair, retry, relaunch and End/unlock; ordinary
  course scoring/history; and night random-library failure/retry. Exported
  day/night target failures and the reopened night course were inspected. The
  UI run precedes preservation of an existing damaged-course warning after a
  successful target gate save and invalidation/restart of feedback sessions during
  pending target saves. The final native suite covers both, including no feedback
  restart after Stop. Actual OS notification delivery and physical haptics remain
  device checks.

The initial core run had one stale rejection-type expectation, and initial native
run failed the two existing tests that asserted before target retry/reset
acknowledgment. Those failed bundles are diagnostic history, not passing evidence.
No assertion about durable target state, unlock, preserved bytes, guide lifecycle,
actual window/UI state or recording/navigation permission was removed.

This checkpoint remains local initially, alongside 7e96105, so the full hosted
run 40273435731 can finish on pushed settings revision 9bb27fc. Hosted results
remain a separate gate; a pass on that older revision cannot validate these new
workers. Phone/watch physical and background haptic checks remain open.


Final phone/watch/widget simulator Release passes in
`/tmp/gridfix-course-target-release-final.log`. The preceding Release also passed
before the feedback-session invalidation follow-up. The final feed is stopped
and cleared, and the owned phone simulator is shut down; other devices and the
local TAK server were untouched.
