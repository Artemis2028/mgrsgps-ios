# Finished track storage independent of backups

Android reference: `release/1.1.0` at `482b417`, TrackRepository.kt. Track metadata
lives in DataStore; each point log has its own file. Backup.kt separately limits
external archives. iOS previously used Backup.exportZip for every local field
mutation, imposing the external 512-entry, combined point and byte bounds on its
finished library. This could prevent saving a recording or an unrelated graphic.

Local storage now uses `field-data-v2.json` and immutable, uniquely named files
in `field-track-logs-v2/`. The index contains Android-compatible metadata plus
private log references and SHA-256 checksums. New logs are validated, staged,
synchronized and exclusively installed on workers. Their random filenames cannot
overwrite another log. They are not library records until the index commits.
The UI executor checks repository identity/revision and performs one atomic
index rename; model publication and recording-journal acknowledgment follow that
commit. Metadata edits reuse existing logs without parsing or rewriting them.

A stale/cancelled preparation or failed index commit cleans up only its own
unreferenced files. Normal deletion reclaims obsolete logs on a worker after the
index commits. A restore always gets fresh filenames, so delayed deletion cannot
remove the restored copy. Older captured snapshots retain their immutable bytes,
including memory-mapped logs whose obsolete filenames are unlinked. As with the
existing repositories, one app-owned store serializes publication.

If no v2 index exists, the legacy `field-data-v1.zip` is read without modification.
The next successful mutation migrates the complete library; it leaves the old
archive byte-identical. An interrupted/failed migration cannot replace it with a
partial index. Once a v2 index exists, missing/corrupt logs or index report a load
error and refuse writes. Falling back to an older archive could resurrect deleted
records, so it is deliberately not automatic. The legacy archive is retained as
one recovery copy and is no longer rewritten.

A process crash before index publication can leave unreferenced immutable files;
there is no automatic startup sweep that might race another preparation. They
are not presented as saved records. Physical crash/storage-pressure testing and
a guarded orphan-maintenance workflow remain work. Best-effort cleanup is not a
promise that storage is reclaimed while iOS suspends the process.

## Bounds and interchange

The combined local ZIP limits and the former per-log 250,000-point / 16 MB caps
are removed. Android's local reader at release/1.1.0 also has no such per-log
cap. The 10,000-record validation and 64 MB metadata index bound remain.
Startup validates referenced logs on the field-library worker; each log is
memory-mapped when possible, checksummed and scanned row by row. Count/distance
recomputation no longer builds a complete point array or splits the complete
log into strings. Views needing all coordinates still materialize them, so
very large/dense map performance and lazy geometry remain work. Available
storage, address space and OS execution time still constrain real devices.

External backup/GPX/ATAK contracts and protected-file limits are unchanged. A
local library may exceed a single whole-backup limit; backup export reports an
error rather than dropping tracks. Individual GPX export uses the complete local
log, matching Android TrackRepository.buildGpx, including tracks beyond the
backup point limit. Whole-library exports/imports, protected-file and watch-sync
budgets remain unchanged; a long exported GPX is not a promise that a bounded
importer can reopen it. Android Backup.kt also enforces its archive limits.

## Validation

- 468 core tests pass in `/tmp/gridfix-local-track-core-verified.log`. Eight new
  cases exercise migration, migration rollback/retry, corrupt-v2/no-fallback,
  checksum/missing-file preservation, reused metadata logs, deletion/restoration
  with unique names, 513 finished tracks, and three logs totaling 750,000 points
  and over 32 MB. That large library still accepts a folder edit and reopens;
  external full-backup rejection and bounded selected-track export are checked.
  Exclusive file installation is also checked against an existing destination.
- Full native suite: 234 cases, two opt-in local TAK skips, zero failures in
  `/tmp/gridfix-local-track-native-verified.xcresult`. A separate new recorder
  integration passes in `/tmp/gridfix-local-track-native-migration.xcresult`,
  proving that a new recording migrates old logs before journal acknowledgment.
  Existing write-failure fixtures target the new index; their original state,
  retry, partial-phase and damaged-byte assertions remain. Explicit legacy
  corruption coverage remains. Physical file-protection assertions now include
  both the index and point logs; simulators cannot prove data protection at lock.
- Four real-location UI workflows pass in `/tmp/gridfix-local-track-ui.xcresult`:
  recording/background/save/map, recording recovery, confirmed discard and night
  completed-course result repair/retry/relaunch. Exported track details and night
  error/result screenshots were inspected. This run precedes only moving
  immutable-file installation from publication into preparation; final core and
  native checks cover that timing change.
- Final phone/watch/widget simulator Release passes in
  `/tmp/gridfix-local-track-release.log`. The single owned phone is shut down,
  location feed stopped/cleared, and no server or other device was changed.

An initial core run failed old archive-path fault fixtures after the destination
changed; those now exercise the actual index. The first verified native suite
finished all 234 cases before its auxiliary simctl diagnose stalled. That exact
diagnostic child was stopped, allowing xcodebuild to finalize successfully. One
follow-up started before diagnostic exit; subsequent simulator runs were serialized.
No incomplete test bundle is presented as a passing run.

## Long local logs, 26 October

The recorder now appends without the external backup point/byte cap, while
retaining its bounded live preview, per-point sync and stop-on-write-failure
behavior. Recovery and finished-store validation scan every complete row,
including the old reader's legacy newline forms, with cancellation checks.
Malformed trailing rows still fail instead of accepting a valid prefix.
Local map geometry, focus and backtrack decode the local log independently of
the bounded interchange reader. Watch omissions remain explicit at its existing
2 MiB source budget.

The regression reconstructs a 300,001-point, 17,400,058-byte interrupted log,
finalizes it, saves it, clears the journal, reopens all bytes/points and moves its
folder successfully. Full backup export still rejects that document. A separate
native individual GPX export counts all 250,001 output points with XMLParser.
See the current parity checklist for final run evidence and remaining gates.

Saved-track map preparation now runs on a worker, decodes each visible log once
and applies Android's count/1500 drawing stride plus its final endpoint. Full-log
bounds are retained as at most six extrema; saved bytes and individual GPX export
remain complete. Generation/cancellation guards prevent old results restoring
hidden or deleted data. Loading, retry and deferred Show All are visible; a newer
Go To or manual pan cancels a pending fit. See
[map preparation evidence](map-geometry-preparation.md). Each visible log still
materializes its coordinates on the worker, and dense tactical overlays use a
separate renderer, so arbitrary-size memory/performance is not established.
