# Runtime navigation persistence

Navigation now prepares session JSON and temporary files on a worker for startup,
checkpoint advance, manual Previous/Next, haptic preference changes, Pause, Stop
and confirmed Clear session. Target preparation also runs on workers. Only
revision/intent validation, atomic rename and observable state publication run
on the UI executor. Startup file reading and route/library validation still
need separate performance work.

## Ordering and cancellation

A checkpoint keeps its old in-memory/saved route index until the target and the
session have both committed. Its checkpoint notification is emitted afterward.
While a save is pending, steering playback is cancelled and no new guidance is
evaluated. The newest usable location is retained in one bounded slot. Future,
stale, inaccurate and older samples cannot replace a usable queued fix; replay
still uses the ordinary freshness/accuracy/timestamp rules. Clock jumps reset
queue ordering in the same way as normal receipt ordering.

Pause and Stop stop location/playback immediately. Their inactive snapshot is
saved asynchronously. Stop clears the route in memory immediately as well.
Generation checks prevent an older worker from reviving a paused/stopped session
or overwriting a newer request. Cancellation reaches detached preparation too.
A newer selection intent is checked again before session publication, even if
that selection has not yet committed. Route geometry, ownership, selected target,
practice lock and location access are revalidated before checkpoint publication.

The target and session remain separate atomic files. If target publication
succeeds but session publication fails or is cancelled, progress remains at its
old index and the route stops/pauses. No checkpoint is announced. Explicit Resume
selects the unscored leg again; relaunch never starts GPS/haptics automatically.
This is not a transaction across both files, and the paused target readout can
reflect the already saved selection until Resume. A combined transactional store
would be a separate storage change.

Both files request complete-until-first-authentication protection. Runtime writes
request bounded UIApplication background save time; expiry cancels the operation
and pauses without starting another grace request. The lease is ended on expiry
and ordinary completion. This helps finish a save during location execution; it
does not grant continuous background runtime or change location permission.
Physical locked-screen, storage-pressure, battery and alert/haptic checks remain
required.

## UI and watches

The phone shows saving progress and disables duplicate Previous/Next and haptic
changes until publication. Pause and Stop remain available. Watch guidance keeps
the session identity but reports unavailable with a saving status; it does not
export an old lane/steering decision as current. Optional Live Activities also
show a saving status. Their opt-in remains independent of GPS/navigation.

## Validation

The native suite includes blocked worker saves while Pause/Stop, route changes,
new target commits and newer pending target intents occur. It verifies no late
route index or checkpoint cue, durable cleared/paused relaunch, unchanged haptic
preferences on failed saves, main-thread responsiveness, bounded queued samples
and duplicate timestamp rejection. Final artifacts are listed below. Source guards match Android GridFixApp.selectNavigationTarget,
present since d5c83ab and inspected at tree 56acca2; 56acca2 itself only changes
the takOff stub API.

Final validation:

- `/tmp/gridfix-runtime-verified.xcresult`: 212 native cases, including two
  opt-in local TAK skips, no failures; both day/night target UI workflows pass.
  The final queue filter, clock-jump case and partial-commit Resume recovery
  are included in this run.
- `/tmp/gridfix-runtime-ui.xcresult`: all five UI cases pass: real Core Location
  automatic route pause/Home background completion/relaunch, optional recording
  and navigation Live Activity lifecycle, and day/night target failure/clear.
  This run precedes only the final queued-invalid-fix filter; the final native
  suite above verifies that filter and the unchanged normal route policy.
- `/tmp/gridfix-runtime-release-final.log`: phone/watch/widget simulator Release
  passes after the final production changes. GridFixCore is unchanged from its
  446-case passing target-persistence checkpoint.
- Screenshots in `/tmp/gridfix-runtime-ui-screens/` were inspected: route complete,
  settings and readable day/night target failures. The Home capture shows the
  location indicator; it does not prove Dynamic Island or Lock Screen rendering.
  Navigation Lock Screen inspection remains open.

An intermediate run was refused before app launch by Simulator's busy-install
preflight. The dedicated owned phone was rebooted before subsequent runs; no
other simulators were used. The successful five-case UI run finished all tests
but stalled in an auxiliary simctl diagnose child; only that identified child
was terminated, allowing xcodebuild to finalize successfully. Its feed runner
then stopped and cleared location. No test assertion or app process was skipped.
