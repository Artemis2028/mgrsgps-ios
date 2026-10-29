# File-backed backup output — 29 October 2026

Ordinary backups now prepare an owned ZIP file on a worker and pass its file
payload to the existing native Files presenter. The archive writer measures and
validates every member before emitting any ZIP bytes, then verifies a second
visit before finishing the central directory. It retains the legacy STORE
container and complete raw track bytes. Source changes, missing/corrupt data,
sink failures and cancellation cannot publish a provisional archive.

Backup protocol limits stay in place: 512 members, 4 MiB manifest, 16 MiB per
track, 32 MiB total uncompressed data including the manifest, and 250,000 track
points across all tracks. Individually valid members cannot bypass aggregate
limits. Metadata, sparse setting presence, zero/false/null values, empty logs,
Unicode/newline variants, lane and quiet-boundary data retain their existing
contracts. The Android BackupArchive limits were inspected read-only; no wire
or phone source change is required.

The writer avoids a complete archive/all deferred track bytes and decoded point
arrays. It retains the existing manifest JSON encoder and at most one bounded
track member (16 MiB), emitting 64 KiB chunks. Manifest serialization itself is
still eager and has its existing 4 MiB encoded limit. Protected backups retain
the current one-shot authenticated envelope (33 MiB sealed cap); that step
materializes bounded plaintext/ciphertext. Its provisional plaintext file is
discarded before successful protected presentation. This is not a claim of
fully incremental JSON encoding or authenticated encryption. Physical peak
memory and provider/cold-device behavior remain gates.

BackupTransfer's new file path shares the existing phase/generation/cancellation
owner. Late canceled preparation cannot replace a new operation; restore commit
ordering remains. Data-returning helpers remain available for compatibility;
Waypoints uses the file path for ordinary and protected backup exports.

Validation complete:

- All 609 core cases pass, including six streaming/budget cases. Two individually
  valid 16 MiB members plus the manifest exceed the aggregate byte budget and
  correctly fail before output; multi-track aggregate point limits also pass.
  Existing KMZ archive tests pass against the shared multi-member writer.
- All 374 native cases complete with four opt-in skips and no failures, including
  file ownership, protocol roundtrip, no provisional plaintext directory,
  cancellation/generation and missing-source cleanup checks.
- Both unchanged native Files export/delete/restore/relaunch workflows pass:
  ordinary night backup 136.061s; protected backup with wrong-password rejection
  and correct restore 171.350s. Xcode finalizes exit 0 / TEST SUCCEEDED.
- Unsigned phone/watch/widget device Release passes. Representative ordinary,
  protected night and restored inactive boundary captures inspected. Every local
  parent is reaped, fake location cleared and the owned simulator shut down.
- Desktop Java 17 ZipInputStream independently consumes the actual Files-saved
  ordinary ZIP: one declared gridfix-backup.json manifest and one canonical track
  member, complete STORE content/CRC. This is container evidence, not new
  Android-app, paired-transport or enrolled-server verification.

Evidence: /tmp/mgrsgps-backup-stream-core-final.log,
/tmp/mgrsgps-backup-stream-budget-final.log,
/tmp/mgrsgps-backup-stream-native-ui.xcresult,
/tmp/mgrsgps-backup-stream-native-ui.log,
/tmp/mgrsgps-backup-stream-release.log,
/tmp/mgrsgps-backup-stream-java-check.log and
/tmp/mgrsgps-backup-stream-images/manifest.json. Terminal ownership is recorded
in /tmp/mgrsgps-backup-active-work.json. Held locally while hosted114 validates
pushed 5f73683. Physical peak memory/provider/cold-device checks, remaining watch
heading/route/offline/terrain work and the other recorded parity gates remain.
No TAK/server/credential/infrastructure action or real position.
