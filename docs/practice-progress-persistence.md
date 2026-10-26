# Course start and checkpoint writes

Practice course start, missing-checkpoint reconciliation, accepted scores and
explicit End now encode/stage their course file on workers. Main-actor publication
checks the generation, exact expected run/progress, current checkpoint identity
and coordinates, and current missing IDs. Changes during preparation either
rebase reconciliation or reject the stale score. The normal target lock still
belongs to the durable course and cannot be replaced by a waypoint picker.

A save in progress does not publish its new index or play checkpoint feedback.
Repeated fixes are bounded to one newest usable pending sample. They are checked
again after publication against the then-current target/freshness policy. End
cancels an unfinished score; a late worker cannot revive that run or buzz. A fix
accepted while foreground can finish its confirmed write after backgrounding,
but does not buzz there or enable further background course scoring.

Failed writes retain the current durable progress and an explicit Retry request.
Ordinary timers do not retry failed writes. Retry keeps the original run ID,
accepted score time and generated checkpoint IDs. A failed random start does not
scatter another set on retry; Cancel start leaves already saved checkpoints.
A failed start leaves ordinary navigation available. These pending retry requests
are process-local; after process death, recovery uses the last durable course,
not an unsaved score or unsaved start. This matches the distinction between an
accepted request and a successful persisted checkpoint.

Ending/unlocking can fail after the active course was cleared. The waypoint store
now exposes its pending practice-selection save so Retry actually finishes that
preference write even when the in-memory lock is already off. Damaged-session
reset clears old retry gates after preserving the original. Target-lock failures
remain fail-closed for active courses.

The UI disables duplicate setup/Start actions while saving, preserves Close and
End, and shows saving/retry banners. Course start failure fixtures block only the
known temporary test file after healthy store initialization. Repair is DEBUG-only
and removes only that empty test directory. No course index, score or result is
injected by UI tests.

Android reference: CourseRepository.markFound checks run ID and expected point;
its UI engine validates available IDs, accuracy plus distance <25 m, and calls
feedback after acknowledgement. iOS retains those rules and its existing
name/start-time history merge contract. Quiet-inside boundaries remain separate.

## Validation

Native tests cover blocked worker publication/feedback, duplicate fixes, End,
deleted checkpoints, accepted foreground writes finishing while backgrounded,
failed start/score retries, retained score timestamps, ordinary-guide preservation,
random checkpoint reuse, real unlock retry and damaged-session recovery. Core
staging passes 449 cases. No physical locked-screen scoring is claimed.

- /tmp/gridfix-course-progress-core.log: 449 core cases pass.
- /tmp/gridfix-course-progress-verified.xcresult: final full native suite passes
  223 cases, including two opt-in local TAK skips. The random-start retry case
  confirms one set of generated checkpoint IDs through failure, retry and End.
- /tmp/gridfix-course-progress-ui-final.xcresult: final day/night failed-start
  repair/retry/relaunch and existing folder lock/End/relaunch workflows pass.
  Screenshots in /tmp/gridfix-course-progress-ui-screens were inspected.
- /tmp/gridfix-course-progress-ui.xcresult: the six pre-existing course UI cases
  pass, including real scoring/summary and result-history retries, but that first
  mixed bundle failed both new start-failure fixtures. The fault was installed
  before lazy StateObject initialization, so it correctly appeared as damaged
  data rather than a healthy store failing its next write. Explicit initialization
  fixes fixture ordering; no test injects an app result. That bundle is not an
  overall pass.
- /tmp/gridfix-course-progress-release-final.log: final phone/watch/widget
  simulator Release passes. Host feeds are stopped and location cleared on exit.

One intermediate native attempt was refused before launch by Simulator's busy
installation preflight. The owned phone was rebooted before later checks. Some
runs stalled in auxiliary simctl diagnose after their tests ended; only the
identified owned child was terminated to finalize the parent. Final native
assertions all passed, and the final three UI cases completed normally.
Hosted run 40267500064 on the preceding checkpoint has a failed field shard:
LaneCueWorkflowTests, LiveActivityWorkflowTests and OrientationWorkflowTests.
Those diagnostics remain open CI work; local success is not full hosted green.

## Remaining work

Random waypoint generation/library append and practice target-lock selection still
use synchronous full-library writes. Course startup reads, damaged-session copy,
large-course list/eligibility rendering and physical storage/background/field
validation remain work. The common course-file mutations have moved off-main;
this does not close the full parity or release goal.
