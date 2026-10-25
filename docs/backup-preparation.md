# Backup preparation and ordered restore

Android reference: `release/1.1.0` at `482b417`, `data/Backup.kt`. Android prepares archives on `Dispatchers.IO`, validates before touching repositories and finishes its ordered persistence in `NonCancellable`.

The iOS library now reads provider backups and prepares exported ZIP bytes off the main actor. Export captures one value snapshot of waypoints, folders, finished field data, navigation lanes and settings before the worker starts. Preparation shows progress and Cancel; a second backup request cannot replace work already in progress. Leaving the library cancels preparation. Other library work and GPS delivery can continue.

Reads retain coordinated/security-scoped access through parsing, including mapped ZIP pages. Existing ZIP64, CRC, member/manifest/container and decompression limits remain unchanged. Cancellation reaches the detached worker. If a provider finishes late despite cancellation, both worker cancellation checks and the transfer generation prevent its result from being applied or opening an export. A canceled old operation cannot clear or overwrite a new operation's state.

Restore merges into the current stores after reading, including edits made while the provider was busy. The entire document is validated first. Commits follow Android's order: tracks, waypoints/folders, graphics/routes, optional navigation lanes, course history, then settings. The lane phase follows the post-release Android extension. Each section remains durable and additive; a failure reports completed sections, leaves later sections untouched and supports an unchanged-file retry. Existing IDs, waypoint selection and existing folder visibility are retained. Duplicate field/lane restores do not rewrite unchanged files.

Merge, validation, serialization and file writes now run on workers using immutable store snapshots. Files are staged in Apple's [replacement directory on the destination volume](https://developer.apple.com/documentation/foundation/filemanager/replaceitemat(_:withitemat:backupitemname:options:)). The main actor checks the store instance and revision, atomically renames the completed file, then publishes its in-memory state. A selection change, folder edit, new recording or other record mutation invalidates a successful preparation; it is discarded and rebuilt from current data. Settings use the same protocol. Track decoding also releases the store lock after capturing its immutable bytes, so a background reader does not hold that lock throughout decoding.

Cancel applies before restore publication starts. In-process cancellation does not interrupt a commit already underway; ordered phases finish and report progress even if the owning view leaves, matching Android's noncancellable commit policy. An actual process interruption can leave earlier durable sections, and retrying the backup completes the remaining sections. Main-actor work is reduced to snapshot capture, revision checks, atomic rename/cleanup and publication. Remaining costs include repeated field-archive encoding across phases, other synchronous editing operations and dense-map rendering/accessibility; provider/storage-pressure and physical-device checks remain. This is implementation work, not an iOS restriction. Active sessions, offline packs and quiet-inside boundaries remain outside the Android v1 backup contract.

Backups and interchange now share `LibraryRestoreCommit` for worker-prepared
field and waypoint phases. Their cancellation policies remain distinct: backup
restore completes its ordered commit; interchange checks cancellation between
finished atomic phases, matching `ImportCoordinator.persist`. See
[text interchange](text-interchange.md).

## Verification

- Real ZIP64 provider reads and standard backup encoding assert execution off the main thread and reopen with matching content/settings.
- A suspended provider leaves the main actor free to edit/select a waypoint; completion merges both that edit and the backup into reopened stores.
- Cancellation tests cover a late provider, rejected concurrent requests, an old canceled restore overlapping a new export, failure reporting and retry.
- Real filesystem failures verify ordered partial progress, preservation of unreadable field data and additive retry. An unchanged field restore skips a blocked write target while a real edit still fails atomically.
- A native Files workflow exports a backup in night mode, deletes a mixed folder, imports the saved ZIP and verifies restored waypoints/graphics/tracks, relaunch persistence and untouched Base records. Screenshots were inspected for readability.
- Prepared-store tests verify that disk and memory stay unchanged until publication, stale revisions reject publication, edits/selection/folders/new recordings survive rebasing, failed replacement keeps the destination and records, and another store instance cannot consume the token. Existing partial-failure tests exercise the production asynchronous coordinator.
- A model benchmark restores an accepted backup with 5,000 waypoints, 1,000 routes and 50,000 track points while a main-actor timer edits/selects a local point. A local Debug iOS 26.5 run took 0.848 seconds with 432 timer pulses and a largest observed gap of 0.004 seconds. Timings are recorded rather than used as a hardware-dependent gate. This does not measure rendering thousands of actual SwiftUI library cards.

The staged-restore milestone passes 296 core tests and 107 app integration tests locally, plus the native night-mode Files round trip. Existing partial-failure tests now call the production asynchronous coordinator. Full hosted CI and physical file-provider/storage checks remain separate gates.

Non-backup library and single-track exports now use their own cancellable
[worker preparation](export-preparation.md) and share the library’s native Files
presenter exclusively with backup output.

Optional [password protection](protected-backups.md) wraps this same archive
and restore order. Key derivation/encryption/decryption run on workers; protected
files are authenticated and fully parsed before any commit begins. Ordinary ZIP
export remains available.
