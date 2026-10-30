# Unreadable waypoint file recovery

A waypoint load failure keeps the existing file protected. The library warning
opens Waypoint recovery; Waypoint actions → Waypoint file recovery also opens
the preserved-file history when the library is healthy.

- Retry loading prepares a decoded snapshot on a worker and publishes it only
  if the source file and store revision still match. It does not rewrite the file.
- Preserve original for sharing makes an exact private on-device copy without
  replacing the library. Save or share original uses the native share sheet.
- Archive original and start fresh requires a separate confirmation. It first
  preserves the original, then atomically publishes an empty waypoint library.
  Cancel changes nothing. The empty library can accept a reviewed backup restore
  or import; a preserved unreadable file is not itself a valid backup.

Copies live in the app's WaypointRecovery folder under random identifiers. The
worker streams 64 KiB chunks, checks cancellation and source metadata, and compares
SHA-256 digests against a second source read. Regular files only: symlinks and
directories are refused. Complete copies remain if replacement later fails;
incomplete copies are removed. Publication checks store identity/revision and
source/archive metadata before replacing the live file. Failure leaves the load
error and original intact. There is no automatic reset or history deletion.

The history lists copy time and size, remains available after relaunch, and can
share copies again. Preservation can fail under storage pressure; replacement
then stops. Physical power-loss/storage-pressure testing remains required. This
work does not change remaining legacy synchronous non-editor mutation APIs.

## Validation

- Six new core cases cover streamed exact binary/Unicode preservation, repaired
  file reload without rewriting, changed source/store refusal, wrong-store tokens,
  directory/symlink refusal, cancellation and real filesystem publication failure
  with archive retention/retry. All **422 core tests pass**.
- The native integration suite executes **188 tests, two unstaged opt-in local
  TAK skips, zero failures**. No server was started for this milestone.
- Three final native UI workflows pass: healthy-library history, night recovery
  and day recovery with Files export. They verify retry error, preservation without
  reset, confirmation cancellation, successful empty-library creation, a new
  durable waypoint and history after relaunch. Day/night screenshots were inspected.
- The actual synthetic original saved by the native Files picker is byte-for-byte
  equal to the 44-byte seeded unreadable Unicode file.
- Release phone, embedded watch and ActivityKit extension build succeeds.

Final UI evidence: `/tmp/gridfix-waypoint-recovery-final-ui-20261026.xcresult`.
Earlier runs exposed a Save to Files cell selector and an overly strict test
scroll margin; those failed bundles are not reported as passing. The final test
retains the recovery, cancellation, durability and export assertions.
