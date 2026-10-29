# Read saved track points when requested

Android release/1.1.0 (`482b417`) TrackRepository.kt reads TrackInfo metadata
separately from point logs. The iOS app now requests deferred track contents from
all ordinary field-library entry points: startup, both retry controls, and the
recorder's recovered/finalized-track path. Listing validated tracks no longer
requires opening, hashing or retaining all their point bytes first.

The worker validates the saved index, record structure and regular-file metadata.
For each reference with a matching versioned statistics receipt it publishes an
immutable SavedTrackSource instead of Data. The value captures file identity,
size, modification time and expected SHA-256. A requested read checks identity
before/after I/O, verifies the complete checksum and owns the returned bytes.
Later in-place file changes cannot alter an already-verified snapshot.

Backup.Document keeps local sources separately from eager interchange bytes.
Consumers use its throwing trackData API; a missing nonempty track cannot become
an empty export, backtrack, map preview or restored log. Source paths are not
encoded in manifests, ZIPs, TAK events or watch packets.

## Consumers and publication

- Track detail/menu exports capture a source and revision without reading bytes
  on Main. The export worker reads the selected track; full formats materialize
  all included tracks. Waypoint-only CSV and ATAK route exports stay independent.
- Backup encoding materializes complete logs on its existing worker, preserving
  archive size/count limits and exact names/content. Oversized sources can be
  rejected before their contents are read. Restoring such a document copies
  point bytes into independent destination files.
- Map preparation reads only visible tracks; hidden tracks are skipped before
  I/O. Show-on-map and backtrack actions read their source on workers and retain
  existing generation/revision/cancellation checks. Watch preparation reads only
  eligible bounded tracks, counting unavailable items as omissions.
- Metadata edits retain immutable references. Their worker checks file stamps;
  publication keeps its short index-source check and atomic rename, without
  scanning point logs on Main. Changes after preparation are detected at point
  use; edits never rewrite retained logs or manufacture missing bytes.
- Automatic orphan cleanup needs more authority than a metadata-only load.
  Deferred sources share a lock-protected checksum-verification receipt. Until
  every source has actually been verified and remains unchanged, maintenance
  returns without deleting old unreferenced files. Failed reads revoke that
  authority. A successful map read requests bounded maintenance afterward;
  hidden/unread tracks continue to defer deletion instead of forcing a scan.

## Compatibility and limits

Receiptless, malformed-receipt or older-version logs still take the strict eager
fallback, as do legacy v1 archives. A confirmed library save persists successful
validation receipts, enabling deferred reads on the next launch. Startup does
not rewrite the saved index merely to upgrade its cache. Automatic migration of
large receiptless libraries without requiring a user edit remains follow-up
work; this milestone must not be described as zero point I/O for every old save.

Synchronous compatibility APIs retain their eager defaults; the production app
explicitly requests deferred reads. A metadata row shows the saved summary;
byte corruption can now surface when that track is requested. Missing files or
bad index structure still fail opening. A stale source asks the user to reopen
the app, rather than pretending that opening the same sheet refreshes the store.
There is no automatic destructive repair or new format/permission/server action.

Requested map previews, camera fitting and backtracks now parse deferred files
in verified chunks; see [streaming behavior and evidence](track-streaming.md).
Bounded exports still own their requested bytes. Automatic legacy cache migration,
cold-device pressure/battery profiling, dense-map rendering and wider accessibility
remain open. Orphan cleanup can stay deferred for hidden
tracks never read by any consumer. Physical locked-screen recording and watch
radio/field checks are not proven by simulator background tests.

## Validation

- All551 core cases pass in `/tmp/mgrsgps-lazy-track-authority-core.log`.
  Thirteen new deferred-read cases prove zero point reads during metadata load,
  strict legacy fallback, exact eager/deferred map equivalence, missing/changed
  source errors, checksum checking at first use, independent backup bytes,
  metadata edits/deletion, hidden-track filtering, watch omission counts,
  owned-byte snapshots/size preflight and conservative cleanup authority.
- `/tmp/mgrsgps-lazy-track-policy-final.xcresult`: all356 native cases complete
  with four opt-in skips/no failures, plus five UI workflows. These validate
  the final startup/retry/recorder policy before the later cleanup safeguard.
  Its new recorder test recovers a journal while retaining an older track as a
  deferred source, keeping its exact bytes and avoiding automatic GPS restart.
- The final cleanup-source code passes28 affected native cases and the cold-map
  workflow in `/tmp/mgrsgps-lazy-track-authority-final.xcresult`. Earlier focused
  native59 and full-native355 runs are also green, without double-counting them.
- Seven distinct UI workflows pass across final/source-compatible bundles:
  cold-relaunch selected-track native Files export at night; four day/night/
  largest-text recovery/retry journeys; cold map/import/visibility persistence;
  and live recording with real fake Core Location updates while backgrounded.
  The recording journal grows in the same session before app activation, then
  saves to the library/map. Exact counts and destructive confirmations stay.
- Cold map images show the blue saved track after deferred loading and its
  removal after hiding, with the route retained. Night GPX preview, readable
  recording panel and largest-night recovered library captures inspected.
- Current unsigned phone/watch/widget Release succeeds in
  `/tmp/mgrsgps-lazy-track-authority-release.log`; ten harness checks pass.
  All local parents exit naturally and the single owned simulator/feed is off.

An initial core test hid Base while its fixture used Imported; the fixture now
explicitly seeds Base and the hidden-source assertion remains. The first cold-
export test build required explicit self in a predicate and ran no cases;
the corrected subsequent bundles pass. Both failed logs remain preserved.
Hosted110 runs98c5c17, preceding these local changes, and cannot validate them.

Screenshot review also records an existing day-mode native Map-tab selected
icon/text contrast problem over pale glass (MapScreen forces dark tab chrome).
This is a concrete UI follow-up, not a platform limitation or a lazy-load result.
