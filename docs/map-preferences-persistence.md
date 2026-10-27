# Map settings persistence

Compared with Android `release/1.1.0` `data/MapPrefs.kt`, which stores base map,
grid, terrain overlays and camera in coroutine DataStore edits. iOS retains its
existing preference schema, catalog, imported-map identifiers and 700 ms camera
debounce. Offline-only remains an additional explicit iOS network policy.

Map preference changes now update the displayed choice and tile pipeline together,
then coalesce complete snapshots through one writer. JSON encoding and staging
run off Main; only source metadata checks and atomic publication remain on Main.
A late camera update mutates the latest choices, so it cannot restore an old
layer/grid/offline selection. Intermediate staged snapshots are discarded when
newer edits arrive. An external replacement is preserved rather than overwritten.

Failed saves retain the latest session intent and show a separate warning with
retry in Map layers and the main app. Download/import status cannot erase this
warning. Done drains pending camera and write attempts before dismissing; failure
does not trap the user. Runtime offline-only and the displayed toggle agree even
when persistence fails. Enabling offline-only still pauses downloads immediately.
Retry against an external replacement refuses again; reopen reloads that source.

Finite camera coordinates are normalized before saving: latitude is clamped to
Web Mercator bounds, longitude wraps across repeated worlds in either direction,
and zoom clamps to 0–22. Nonfinite updates are ignored. This prevents new invalid
camera values from invalidating the whole preference snapshot on relaunch.

Validation:

- `/tmp/mgrsgps-map-preferences-final.xcresult`: all344 native cases pass,
  with four opt-in skips. Six new map persistence cases cover source replacement
  before/during staging, superseding a held worker, actual atomic publication
  failure, offline-policy consistency and retry, and debounced bounded camera
  persistence without losing overlay choices.
- The same bundle passes the failure/retry/relaunch UI workflow in both day and
  night. Screenshots inspected: readable warning, controls and red night palette.
- The first UI bundle failed only the new Retry lookup; its full native hierarchy
  confirms the warning container identifier replaced its child identifiers. After
  moving that identifier onto the text, the workflow passes. All three existing
  map-tool UI workflows in the first bundle pass, including keeping recording
  Stop reachable, tool visibility/reset, Go To and active edit controls.
- Final distinct main/sheet identifiers and 44-point retry targets pass the
  focused repeat in `/tmp/mgrsgps-map-preferences-notice-final.xcresult`; final day/night
  screenshots inspected. This repeats the same workflow, not an extra distinct case.
- Phone/watch/widget unsigned device Release passes in
  `/tmp/mgrsgps-map-preferences-release-final.log`; eight Python harness checks
  pass in `/tmp/mgrsgps-map-preferences-harness.log`.

The explicit DEBUG UI fixture is isolated to `mgrsgps-ui-tests`, substitutes a
directory at the preference destination, and exercises the real atomic writer.
Its repair removes only that fixture directory and retries; it is absent from
Release. It does not inject a prefinished save/error result.

Process termination before the debounce/write finishes can still lose the latest
session change. Physical storage pressure, suspension timing and device I/O
latency remain checks. There is no change to saved offline packages, download
resumption, background entitlements, route guidance or quiet-inside monitoring.

All local test/build parents finished naturally. Fake feeds are stopped/cleared
and the one owned phone simulator is shut down. Hosted104 remains live on the
previous pushed42def16; this candidate is held locally to avoid cancelling it.
Hosted verification and full parity remain open.
