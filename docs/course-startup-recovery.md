# Practice-course startup and damaged-session recovery

Normal app startup reads and validates the saved practice session on the shared
startup worker, alongside waypoints and map state. The main-actor handoff checks
the session file's identity, size and modification metadata, including the
missing-file case. A replaced, created or removed session triggers a fresh
preparation before services are published. Existing direct core-store callers
retain their synchronous setup API.

A recovered run keeps its run ID, checkpoint order, accepted times and splits.
Practice waits for field-library readiness before reconciling the selected
target. Startup does not restart navigation GPS, award another checkpoint or
add an unfinished result to history. A damaged session remains preserved and
keeps the existing navigation lock.

Confirmed reset now prepares the preserved copy and empty replacement on a
worker. The original stays in place while preparation runs. Publication checks
the store identity/revision and source metadata, publishes the preserved copy
first, then atomically replaces the active session. Navigation unlocks only
after that acknowledgement and the existing durable target-gate save. A late
reset cannot erase a replacement session. Failed preparation/publication keeps
the damaged state and supports explicit retry. If the source changed externally,
the app asks for a relaunch rather than resetting different saved data.

The operation is owned by the session after confirmation, so closing its sheet
does not abandon a partially acknowledged reset. Duplicate reset/start actions
are held while it runs. The UI shows preservation progress and an explicit
"Keep saved session" choice in the native confirmation, including popover
presentations that omit the system's automatic Cancel button.

## Validation

- Full core suite: 484 pass, including a 5,000-checkpoint saved run with accepted
  splits, source replacement/removal/creation, staged preservation, stale and
  foreign recovery, and cancellation.
- Full native suite: 255 executed, four unstaged opt-in checks skipped, zero
  failures. New app integrations cover deferred course startup, field-readiness
  ordering, navigation locking through a held worker, duplicate reset rejection,
  failure and retry. Existing practice target/scoring/finalization cases remain.
- Initial focused native suite passed all 40 cases; the first two UI checks
  exposed the missing automatic Cancel control in a native popover. That failed
  bundle is retained at `/tmp/gridfix-course-startup-recovery.xcresult`; after
  tests completed, only its stalled supplementary simulator-diagnostics child
  was terminated to finalize it. The explicit keep action addresses that UI gap.

- Final five UI workflows pass: preserve/reset/cancel/cold relaunch in day and
  night, existing folder-course lock/End/checkpoint retention through cold worker
  startup, and both day/night target-write failure/repair/retry/relaunch flows.
  Evidence: `/tmp/gridfix-course-startup-recovery-final.xcresult`. Damaged, reset
  and reopened day/night screenshots were inspected.
- Final phone/watch/widget Release passes:
  `/tmp/gridfix-course-startup-final-release.log`.

Remaining
settings/other runtime-session startup reads, course-list rendering at large
sizes, storage pressure and physical field/background validation are separate
work. Foreground-only course scoring is unchanged; locked-screen scoring is
unimplemented rather than claimed to be prohibited by iOS.
