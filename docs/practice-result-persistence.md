# Durable practice results

A scored final checkpoint remains in practice-course-v1.json until the shared
field archive acknowledges its result. History merge/validation, ZIP encoding and
replacement-file writes now run on a worker through the existing staged additive
restore path. Clearing the completed active course also prepares its file on a
worker; publication checks the store identity, revision and exact completed run.
The UI publishes its summary/unlocks only after those durable phases succeed.

This preserves Android CourseRepository.finish ordering and its name/start-time
history identity, UTF-16 tie order and 30-result cap. Android keeps active/history
in one DataStore edit; iOS uses two files, retaining the completed active run as
a recovery record between commits. If history succeeds but clear fails, retry
or process relaunch merges the same result without duplication, then clears.
An unreadable field archive remains protected and blocked rather than overwritten.

A confirmed finalization belongs to PracticeSession, including after its sheet
closes. During work the form and home banner show saving. Failure retains the
completed run, blocks abandonment and shows a stable error with Retry. Ordinary
location/timer updates do not repeatedly rebuild a failed archive. Explicit Retry
tries again; a new process attempts recovery of its durable completed run. The
home banner says “Completed run kept · retry saving result” and opens that flow.

The worker files request complete-until-first-authentication protection, and
finalization requests bounded UIApplication background save time. Expiry ends
that lease; durability relies on the completed course record, not indefinite
execution. This does not enable scoring with the screen locked. Course scoring
remains foreground-only, consistent with Android's UI course engine. Physical
storage-pressure/background interruption and locked-device checks remain open.

## Validation

- 449 GridFixCore tests pass in /tmp/gridfix-course-staged-core.log. New staged
  course tests cover no early clear, stale preparation after a replacement run,
  failed clear/retry, foreign stores and unreadable-session preservation.
- /tmp/gridfix-course-final.xcresult passes the complete native suite (213 cases,
  including two opt-in local TAK skips) and both day/night result failure/retry
  UI cases. Native failures block the real history destination, verify the
  retained completed run, prevent timer retries, then repair/retry to one result.
  A second native case fails active clear after history publication and confirms
  process recovery without a duplicate.
- /tmp/gridfix-course-choice-final.xcresult passes all three final UI cases:
  day/night failure, home-banner reopen, repair/retry, exactly-one history entry
  after process relaunch, and active night progress/coordinates. Screenshots in
  /tmp/gridfix-course-choice-screens were inspected. Forms now use red-on-black
  night content/title, explicit pending-completion text and frozen final elapsed
  time. The folder picker uses the existing scrolling choice sheet because the
  native popup could dismiss without setting its binding; the test still waits
  for the real selected folder to enable Start.
- /tmp/gridfix-course-choice-release.log passes final phone/watch/widget simulator
  Release. The UI runs use real Core Location simulator samples; no course index,
  score or summary is injected. DEBUG fixture/repair code touches only the known
  empty temporary test destination and is excluded from Release. Feed runners
  stop and clear location on exit.
- Earlier /tmp/gridfix-course-ui.xcresult passed the four existing practice UI
  workflows (normal completion/history, lock/end/relaunch, random setup, night
  progress) but failed the initial two retry cases because automatic location
  retries committed after repair before Retry was tapped. That is a failed
  bundle, not an overall pass; explicit retry fixes this behavior.

## Remaining implementation work

Course start/reconcile/scoring/End have subsequently moved to
[worker staging](practice-progress-persistence.md). Random checkpoint creation
still writes the waypoint library on main, and practice target-lock persistence
still has a synchronous full-library path. Startup course/field reads, damaged-course
recovery copying and large-course split-list presentation also need their own
performance/interaction audit. These are app work, not iOS limitations.

Intermediate readable-form runs exposed the native folder popup failure, with
Start correctly remaining disabled; they are failed runs, not passes. Final
scrolling-choice tests retain all selection/save assertions. Two earlier XCTest
runs stalled after test completion in an auxiliary simctl diagnose child; only
the identified owned child was stopped so its parent could finalize results.
The final three-case choice run completed normally. Only the dedicated owned
iOS phone was used; no TAK endpoint or watch contract changed. Hosted final-head
CI and physical validation remain open.


Practice target-lock library writes have since moved to workers; see
[target persistence](practice-target-persistence.md). The earlier synchronous
limitation above is historical. Startup reads and damaged-session preservation/
reset copying remain work.
