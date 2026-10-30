# MGRS GPS pause handoff — 27 October 2026

Rafael requested a usage-saving pause. Keep the full Android release/1.1.0
parity objective intact. No merge, publication or release is authorized.
The one-minute Claude watcher is PAUSED; resume it when work resumes.

## Saved source and delivery

Worktree: `/Users/apollo/Documents/ChatGPT/Liquid Glass/mgrsgps-ios`.
Branch: `codex/ios-coordinate-map-glass`.
Same draft PR: https://github.com/Artemis2028/mgrsgps-ios/pull/1.
Last pushed SHA: `a002f17c2abd1833d5b5e614d6f3e02bf9ae808c`.
Newer source is held locally; do not equate PR CI with these local commits.

Recent local milestones:
- `16fad42`: readable Position/Navigate accessibility headers, bounded 44-point
  controls, two final day/night portrait/landscape UI journeys passing.
- `31bb327`: Android-matched Settings backup/restore entry point, complete
  shared snapshots, ordinary/protected native Files round trips, wrong-password
  retry, relaunch persistence and unreadable-library preservation. Forty-six
  scoped native cases and final largest-night control/cancel check pass.
- Current pause commit: native Files helper candidate and explicit large-GPX
  Icons-to-List coverage; course-header reveal and CI capacity candidates below.

The broader phone already has route drawing/editing, military symbols/tactical
graphics, map/offline layers, terrain LOS/profile/viewshed, recording, automatic
route following, haptic guidance and separate quiet-inside boundaries. These
are implemented milestones, not a claim of full parity or physical validation.
See `ios-parity-release-1.1.0.md` for the full feature/evidence inventory.

## CI109 is terminal, not green

Run https://github.com/Artemis2028/mgrsgps-ios/actions/runs/40527505812 on a002f17:
- Map 122270958719: success, 41 UI cases.
- Field 122270958991: 350 native cases pass/four opt-in skips; 36 main UI cases
  include one large-GPX native activation failure/five TAK skips. Subsequent
  dedicated background/route/practice steps were skipped.
- Library 122270959199: 62 UI cases, three failures: protected-backup Map-tab
  activation, KMZ native file activation, and largest-night course Create-header
  discovery. It reached the 90-minute deadline during finalization; artifact
  upload then failed reading changing xcresult Staging files. There is no
  verified library artifact. Full log: `/tmp/mgrsgps-ci109-library-job.log`.

Field ZIP SHA-256 verified:
`2159317e76d676f8382056b3d4dcfb5233725b20f2725e561b47a389b82df88c`.
Map ZIP SHA-256 verified:
`2eef50c3c3f1df5910b31b610192c20372a62b38f0f5d43d023acce209d7ad5d`.
Both extracted under `/tmp/mgrsgps-ci109-{field,map}`. Native field activities,
event plists/movie and map route/night viewshed captures inspected.

## Current candidates and exact evidence

Files: match exact document basenames/extensions rather than search suggestions;
rebind Files' foreground search collection before waiting for its result; target
the actual thumbnail in the exact row. Hosted event plists disprove the earlier
coordinate-offset hypothesis: all old taps landed on the filename correctly.
No product importer or declared UTType was changed based on that hypothesis.

Local iOS26.5 original complete large-GPX case passes in
`/tmp/mgrsgps-ci109-ios265-thumbnail.xcresult`; explicit native Icons-to-List
case passes in `/tmp/mgrsgps-ci109-ios265-icons.xcresult`. Both preserve exact
5,000-waypoint/1,000-graphic/zero-track preview checks; screenshots inspected.
The baseline 26.5 run fails search discovery in
`/tmp/mgrsgps-ci109-ios265-before.xcresult`; this differs from hosted activation,
so local success does not prove the hosted failure resolved.

Course candidate: after End, reveal Create course by scrolling toward the top
before asserting it. Hosted tree shows Start already visible at the bottom of
the replacement Form while Create is virtualized above. This edit is NOT yet
runtime-validated. Keep the exact Create/Start, split counts and persistence checks.

CI candidate: move the measured 11.3-minute Waypoint class from library to map,
explicitly assign new InstrumentAccessibility to field, retain three workers and
all test classes. Raise job timeout to 120 minutes for finalization headroom.
Ten Python harness checks pass; hosted validation remains open.

## Existing local test still finishing at pause

Do NOT start a duplicate. Existing parent PID 94390 / exec session 43873 runs
the shared Files consumers using one iPhone16e/iOS26.5 simulator:
`29C01E74-FBE2-47DD-AA47-A47535687237`.
Both ordinary/protected backup workflows have passed so far. The full bundle
has not been declared green. Its sources were compiled before the later
course/CI edits; those edits are outside this run's scope.

Log/result: `/tmp/mgrsgps-ci109-files-regression.log` and `.xcresult`.
Private runner: `/tmp/mgrsgps-ios265-picker-runner.py`; it cleans its fake-location
and companion helper processes naturally in finally. Cleanup observer session
78061 (`/tmp/mgrsgps-pause-cleanup.py`) waits for that exact parent to finish,
exports the result summary and shuts down only this owned simulator if no other
test uses it. Check `/tmp/mgrsgps-pause-cleanup-status.json` and
`/tmp/mgrsgps-ci109-files-regression-summary.json` when resuming. Reap live
handles before starting further work. All other owned test devices remain off.

## Resume order and remaining gates

1. Read the cleanup/status/result files and latest log; poll existing handles if
   still live. Record any failure before another run. Inspect representative
   regression screenshots. Fix the protected-backup Map-tab acknowledgment
   failure and investigate KMZ if the candidate still fails. Do not relax counts.
2. Validate the course-header reveal on iOS26.5 and 26.2 as needed; the new
   Settings/accessibility source also needs the next full hosted run.
3. Update this same draft PR with held commits after local validation, dispatch
   one full hosted run, retain/review artifacts and keep the inventory current.
   CI107 on02d67f6 is the preceding fully green baseline, not proof of new source.
4. Continue saved finished-log eager-read/startup performance, dense rendering,
   wider global Dynamic Type/VoiceOver and remaining Android source audits.
5. Watches: large full-screen grid, 4/6/8/10 digits, target bearing/distance,
   interactive location maps and cached symbols/graphics/lanes are implemented.
   Independent watch crossing/haptics/background navigation and offline/terrain
   transfer remain implementation work. Wear paired Data Layer delivery and
   physical GPS/radio/battery/touch/readability remain unverified.
6. Physical phone GPS/compass/camera/locked-screen cues, Focus/permissions,
   provider/storage/terrain reliability and distribution/privacy/StoreKit/signing
   remain open. Continuous Android-style locked-screen steering haptics are not
   promised by iOS; unimplemented work is not a platform limitation.

## Claude / TAK

Coordination: `/Users/apollo/AI Proj/tak-local/FOR-IOS.md`; preserve existing text
and append dated Codex notes only. Latest Claude note remains 03:37:06 +0300,
Android certificate-display commit b31f36c. No new credentials/setup needed.
Real enrolled iOS/Android teammate exchange and enrollment/renewal remain open.
Server stays OFF until a coordinated authorized GO. Never touch containers/DB;
fake positions only, prepared localhost8089/8446 only, no secrets in diagnostics.
No TAK infrastructure, endpoint, credential or wire change was made in this turn.
