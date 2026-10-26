# Waypoint preparation before app services

Normal launches decode and normalize the complete saved waypoint snapshot on a
shared worker before constructing navigation, recording, TAK or watch services.
The loading screen supports day and red/black night modes. This avoids presenting
an empty writable waypoint library or starting services with a missing saved
target while the file is still being read.

The main-actor handoff checks the source file's metadata against the prepared
snapshot. A replaced, removed or newly created file triggers another read, with
three automatic attempts before a visible retry. Missing files remain missing
until an explicit mutation. Damaged files retain their bytes and use the existing
read-only recovery workflow. Existing synchronous WaypointStore callers retain
their API and behavior.

Concurrent callers share preparation. Cancelling a waiting view cannot publish
its result or discard preparation needed by a later caller. The service graph is
constructed once after a successful handoff. Files and recording/navigation URLs
received during loading are queued in order for RootView; opening the recording
panel never starts location logging by itself.

UI fixture seeding remains synchronous. A Debug-only cold-launch gate exercises
the production worker path. The host helper `scripts/startup-link-test.py` sends
a real OS recording URL at the test's readiness signal; it is also included in
the hosted UI workflow and cleaned up with that workflow's location feed.

## Validation, 26 October 2026

- Full core suite: 479 pass, including five waypoint preparation cases covering
  a 5,000-point snapshot, selected target, source replacement/removal/creation,
  corruption and cancellation.
- Native suite: 247 executed, four unstaged opt-in local checks skipped, zero
  failures. Five app-bootstrap integrations cover queued URLs, shared workers,
  cancellation, corrupt sources, changed-source retry and retry after failure.
- Cold startup retains the selected target, routes and tracks and delivers the
  OS recording link in day/night. Boundary vertex editing, offline map settings,
  hidden-lane backup/PDF and decimal coordinate entry/edit/relaunch also pass:
  `/tmp/gridfix-waypoint-startup-and-ci-replay.xcresult`.
- Protected backup at night, actual background-location recording/save/map,
  interrupted recording recovery and both day/night waypoint recovery workflows
  pass: `/tmp/gridfix-waypoint-startup-recovery-regression.xcresult`.

- Final recording contrast checks pass with inspected active day and idle day/night
  screenshots: `/tmp/gridfix-recording-contrast-final.xcresult`. The title, saved
  points, distance and actions use explicit contrasting row surfaces; night help
  text stays red on black. Phone/watch/widget Release also passes:
  `/tmp/gridfix-recording-contrast-release.log`.

The finished field library still loads separately on its shared worker. Settings,
map and course startup reads, lazy per-log loading and physical storage-pressure
validation remain work; this change does not make every startup source lazy.
