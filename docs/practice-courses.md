# Practice courses

Reference: Android `release/1.1.0`, `482b417`, particularly `CourseRepository.kt`,
`CourseNavigationPolicy.kt`, `CourseHistory.kt`, `CourseDialog.kt` and
`GridFixApp.kt` course setup/scoring effects. Android consumes fixes with
`collectAsStateWithLifecycle`; this port scores while the app is active.

Open **Navigate → Practice course**, or **Waypoints → Routes & tracks → Practice course**.

- Random setup defaults to five points within 1 km. Counts 3/4/5/6/8 and radii
  500 m/1 km/2 km match Android. Candidate distances are uniform from 120 m to
  the selected radius, bearings uniform around the circle, with >120 m between
  checkpoints and at most 400 attempts. OSM GeoPoint's 6378137 m spherical
  destination formula was verified against the actual Android dependency.
  At least two points must be placed before any folder is created. As on Android,
  a placement that produces fewer than requested but at least two points is usable.
- Folder courses visit all folder points in their saved insertion order, including
  hidden points; this is not the distance-sorted library presentation. Visibility
  remains unchanged. A folder needs two distinct checkpoint IDs.
- Scoring requires a current authorised precise fix, ≤25 m reported accuracy,
  ≤10 seconds monotonic age, and **distance + accuracy <25 m**. A fix without a
  valid accuracy estimate cannot score. The course advances automatically and
  records split/total milliseconds. Displayed times truncate to whole seconds,
  matching Android; the underlying splits add exactly to the stored total.
- Navigate is locked to the current checkpoint through the shared selection API,
  so library/map selection cannot bypass it. Route following cannot replace an
  active course. An existing standalone guide retargets through the normal selected
  waypoint observer; haptic guidance stays optional, separate from scoring.
- Deleting any remaining checkpoint pauses the course and stops its guide; an
  already visited point can be deleted without blocking later checkpoints.
  Restoring the **same IDs** resumes the same run/order/splits; a new point with
  the same name/coordinates is not a substitute. Elapsed time continues while
  paused or while the app is closed. Guide acquisition does not restart silently.
- End course requires confirmation and leaves all checkpoints/folders intact.
  Unfinished runs are not written to history. A stale end/score callback cannot
  affect a replacement run or skip/double-score a checkpoint.

## Persistence and recovery

The active run is atomically persisted to `practice-course-v1.json`, separate
from completed field data and excluded from Android's v1 ZIP backup contract.
Completed results use the existing field history/backup store: deduplicate by
start time/name, retain the newest 30, and use Android UTF-16 name ordering for
timestamp ties. The UI offers completion totals/splits and the persisted log.

The final checkpoint remains durable until history is committed. If clearing the
active run fails afterward, relaunch/retry republishes the same result idempotently.
Failed writes do not acknowledge scores or publish a replacement run. Completed
runs awaiting save cannot be discarded through End course. The selection gate
stays closed if its preference write fails and retries rather than allowing an
unrelated route. Unreadable active data is preserved; explicit reset first keeps
a copy. Checkpoints and history are unaffected by that reset.

If waypoint creation succeeds but the active-run write fails, the generated
checkpoints remain saved and the UI reports the partial outcome; start that
folder when storage is available. Random placement failure creates no empty folder.
Device-clock rollback rejects score commits that would produce negative splits;
the user sees an explanation instead of corrupt history/backup data.

Scoring is currently foreground-only; continuous locked-screen course scoring
is not implemented. This is not a claim that iOS forbids it. Existing background
track recording and optional navigation remain separate services. Quiet-inside
boundary state/alerts are untouched by course selection or scoring.

## Validation

- 229 core tests pass, including 10 practice/gate/history cases based on Android
  pause/restore, identity, strict arrival, persistence failure and bounded scatter.
- 63 app integration tests pass, including 7 practice cases: actual stores,
  target lock/route guard, freshness/foreground scoring, persisted completion,
  missing-ID restoration, live guide shutdown, interrupted route-to-course recovery and interrupted finalisation.
- Four practice UI workflows pass: folder setup/end/relaunch, random setup,
  real simulator Core Location completion/history, and readable night progress.
  No application mock GPS is used. `practice-test-route.py` alternates the real
  simulator location; CI isolates it from the recording/navigation route feeds.
- Recording/background and coordinate/map/folder regression checks are retained.
  The recording feed must move continuously to satisfy its distinct 5 m sampler.
- Screenshots: `screenshots/practice-active.png`, `practice-complete.png`,
  `practice-history.png`, `practice-night.png` and the random setup captures.

Outdoor accuracy, checkpoint haptic feel, permission/wrist-lock behaviour and
large-folder field performance still need physical-device validation.


Practice-session startup and damaged-session preservation/reset now prepare on
workers, retaining the saved run and navigation lock until durable acknowledgement.
See [startup and recovery contract](course-startup-recovery.md) for current
validation and the remaining physical/performance gates.

### Folder setup rendering, 26 October

Folder eligibility now uses one point-count pass and preserves saved folder
order, including hidden checkpoints. It is computed once per form render only
in folder mode; random setup does not scan the saved library. This removes the
per-folder filtered-array allocations during location updates. Course scoring,
checkpoint order and persistence are unchanged.

The existing folder lock/end/cold-relaunch, random setup and night form workflows
pass on iOS 26.2 in `/tmp/gridfix-practice-eligibility-ui.xcresult`; the night
progress/coordinate screenshot was inspected. Final phone/watch/widget Release
passes in `/tmp/gridfix-practice-eligibility-release.log`. This does not establish
very-large course-history performance or physical/background scoring validation.


Folder eligibility follows Android's cached folder/waypoint inputs. GPS and
elapsed-time redraws no longer rescan the whole library. Hidden points count,
a folder needs at least two points, and course checkpoint order remains the
saved waypoint order rather than the library's favourite/distance sort. The
large-library UI regression starts a50-point folder from5,000 saved points and
verifies its first checkpoint and unchanged library counts after ending it;
see the release1.1.0 inventory for scoped evidence and remaining gates.


Completed results keep totals in the summary and expose every saved split in
a native scrolling list. First/Last buttons jump within the complete log; they
do not cap or sample it. Accessibility-size checkpoint/time rows stack. Native
10,000-split day and largest-text night workflows verify both ends and relaunch,
and the real-location two-checkpoint completion/history regression passes.
Physical long-course scoring and active-progress performance remain separate.

Active runs also open their recorded splits in the complete native list. The
target, elapsed time, Continue and End controls stay together in the progress
form instead of following thousands of split rows. The split screen observes
the current run; no history is sampled or converted into a finished result.
Android's ordered checkpoints, live scoring and navigation lock remain intact.

Missing-checkpoint validation and pause text now build a membership set once,
avoiding repeated linear searches across a large paused course. The saved list
must still contain only remaining checkpoints, exactly once and in course order.
The 10,000-checkpoint regression saves/reopens a paused course, refuses scoring,
restores remaining IDs without requiring an already-scored checkpoint, and
resumes at the correct target. Malformed duplicate, reversed, completed and
unknown missing IDs retain the original file and prevent writes. Pause wording
and Android's all-remaining-checkpoints pause policy are unchanged.

Active checkpoint grids use the written MGRS zone/square/easting/northing
groups, retaining the chosen precision. Day and global largest-text night
checks keep all groups visible across relaunch.
