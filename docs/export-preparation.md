# Field export preparation

Reference: Android `release/1.1.0` at `482b417`, `ui/GridFixApp.kt` export
callback and `ui/screens/WaypointsScreen.kt` single-track sharing.

The library's GPX, CSV, GeoJSON, KML, KMZ and ATAK exports, plus GPX from both
single-track entry points, now prepare on a worker. Requests capture immutable
waypoints, field metadata and raw track bytes together. Workers decode those
bytes and build the output without reading live stores. Edits, folder changes or
track deletion after the request cannot mix newer metadata with an older log.
The requested snapshot remains the export; no saved records are changed.

Format rules are unchanged: CSV carries waypoints; GPX carries waypoints, routes
and tracks; ATAK carries waypoints/routes; KML/KMZ/GeoJSON also carry supported
geographic graphics and track linework. Hidden saved records are included, as on
Android. Formats that do not carry tracks do not decode their logs. Required
malformed track bytes fail preparation rather than being silently skipped. The
existing local missing-log behavior and format loss/geometry policies remain.
Single-track filenames use Android's ASCII letter/digit/space/underscore/hyphen
sanitization, with `track` for an empty result.

Preparation displays its format and Cancel. Competing export choices and modal
library actions are disabled while output is being prepared; tab navigation and
GPS continue. Leaving the owner cancels preparation. Cancellation reaches the
worker, with checks before/after encoding and between track decodes. Builders may
finish a synchronous operation before observing cancellation, but its retired
result cannot open Files or clear a newer request. A failed preparation releases
the busy state before a retry callback runs. The native Files presenter receives
already-built bytes and the correct type/name; it no longer converts a large
track XML string during its file-wrapper request. Cancelling preparation does not
promise cancellation of a save already handed to the system/provider.

One native Files presenter remains on each owning view. Backup and field export
preparation cannot compete for the library presenter. Reading/restoring a backup
retains its separate concurrent-edit/rebase behavior; see
[backup preparation](backup-preparation.md).

## Verification

App tests reopen each format and assert its record/geometry policy and hidden
records; verify file types/names and track-only data; hold an encoder while actual
stores edit/delete records and then verify the captured export; exercise corrupt
required logs, unused logs, cancellation, a late writer, busy request rejection
and callback-driven failure/retry. A large GPX test encodes and reparses 5,000
waypoints, 1,000 routes and 50,000 track points while recording main-actor pulses.
One local encoding took 1.406 seconds with 719 main-actor pulses and a largest
observed gap of 0.004 seconds. Timings are observations, not hardware-dependent
pass gates.

Native Files workflows export/reopen a 5,000-waypoint/1,000-route GPX, then verify
both single-track entry points export exactly one track in night mode. Existing
GeoJSON, KML, KMZ and ATAK package Files workflows exercise the shared worker and
presenter. Actual result bundles and screenshots provide the runtime evidence.
Physical provider behavior, storage pressure, memory/battery profiling, other
synchronous library edits and dense map rendering/accessibility remain work.
This is implementation/validation work, not an iOS permission limitation.
