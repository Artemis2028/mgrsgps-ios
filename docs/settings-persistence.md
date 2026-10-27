# Ordinary settings saves on a worker

Android `release/1.1.0` (`482b417`) uses suspend functions and DataStore edits in
`app/src/main/java/app/gridfix/android/data/SettingsRepository.kt`. The iOS
settings model previously encoded and wrote `settings-v1.json` synchronously for
every property change and discarded errors. Ordinary iOS changes now capture a
small immutable snapshot on Main and encode/stage it on a worker. Rapid changes
coalesce; a staged obsolete snapshot is discarded instead of publishing a stale
tail. Immediate session appearance/navigation preferences and existing values,
integer codes, loading normalization and malformed-file fallback are unchanged.

Only metadata checks, atomic rename, small staging cleanup and observable state
publication remain on Main. A failed write keeps the previous file and the latest
session choices, exposes an error and retains the latest snapshot for retry.
There is no automatic failure loop. Failure notices are visible on the main app
and pinned in the settings sheet so they cannot disappear above a scrolled form.
Done waits for the accepted write attempt, then lets the user return to the field;
the main notice stays until saving succeeds. Dismissal/caller cancellation does
not cancel an accepted save. Termination before a queued save finishes can still
leave the previous settings on disk; the app does not claim uninterruptible I/O.

Source checks preserve a file replaced outside the live store, including during
staging. Reopen is required to adopt an external version. Confirmed backup restore
keeps its staged/revision/identity checks, now also rechecking the disk source.
An ordinary publication while a restore is staged causes a rebase even if the
in-memory settings revision is unchanged. A confirmed restore clears older pending
ordinary snapshots; their late success or failure cannot replace it or report a
false error. Sparse backups and the local-only Live Activities consent keep their
existing behavior. The synchronous `applyBackup` helper is used only by native
fixtures/tests; the production coordinator continues to prepare restores off Main.

## Validation

- `/tmp/mgrsgps-settings-worker-native-final.xcresult`: 331 native cases, four
  unstaged opt-in skips, no failures. New cases hold independently staged files
  to exercise 200 rapid assignments plus final settings (only one obsolete and
  one latest write), failed-write retry without a busy loop, external replacement,
  restore supersession including a late worker failure, and source-only restore
  rebase. Full existing backup, startup, guide, boundary, orientation, consent and
  field-store integration coverage also runs. Reopen assertions now await the
  explicit persistence drain; their exact saved values remain required.
- One initial build failed because the migration added a drain for a fixture
  variable not present in the malformed-file test. That stray line is removed;
  the corrected full run above passes. No native assertions were removed.
- `/tmp/mgrsgps-settings-worker-ui.xcresult`: all nine selected UI workflows
  pass: grid-name entry/relaunch, both Live Activities workflows, three map-tool
  cases, both orientation cases and day/night filesystem-obstruction/retry/reopen.
  The notice remains in the main app after Done, refuses retry while obstructed
  and disappears only after a real publication. Screenshots are inspected.
- Screenshot review found two app-owned toggle labels still white in night mode.
  Explicit palette styling fixes them; the focused day/night workflow passes
  again in `/tmp/mgrsgps-settings-worker-night-final.xcresult`, with the final
  restored-night screenshot inspected. This is a repeat of one of the nine
  workflows, not a tenth distinct workflow. Native picker text remains managed
  by the system.
- `/tmp/mgrsgps-settings-worker-release-final.log`: final phone/watch/widget
  unsigned device Release passes. Eight harness checks pass in
  `/tmp/mgrsgps-settings-worker-harness.log`. Parents finish naturally with 0;
  the route feed is stopped/cleared and the one owned simulator is shut down.
  Hosted103 is on the preceding `bc52ed8`, not this local settings candidate.

The opt-in DEBUG UI obstruction fixture is restricted to `mgrsgps-ui-tests` and
creates a directory at the settings destination. The source guard refuses that
unexpected object; it never injects a finished UI error or successful-save result.
The explicit test repair removes only that isolated directory, then retries the
real worker write. It never removes a valid settings file or runs in production.
Physical storage-pressure, process suspension/termination and actual device I/O
latency remain checks. This does not change map-pack/session/log persistence or
add independent watch guidance. TAK infrastructure and credentials are untouched.
