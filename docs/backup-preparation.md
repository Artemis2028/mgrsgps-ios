# Backup preparation and ordered restore

Android reference: `release/1.1.0` at `482b417`, `data/Backup.kt`. Android prepares archives on `Dispatchers.IO`, validates before touching repositories and finishes its ordered persistence in `NonCancellable`.

The iOS library now reads provider backups and prepares exported ZIP bytes off the main actor. Export captures one value snapshot of waypoints, folders, finished field data and settings before the worker starts. Preparation shows progress and Cancel; a second backup request cannot replace work already in progress. Leaving the library cancels preparation. Other library work and GPS delivery can continue.

Reads retain coordinated/security-scoped access through parsing, including mapped ZIP pages. Existing ZIP64, CRC, member/manifest/container and decompression limits remain unchanged. Cancellation reaches the detached worker. If a provider finishes late despite cancellation, both worker cancellation checks and the transfer generation prevent its result from being applied or opening an export. A canceled old operation cannot clear or overwrite a new operation's state.

Restore merges into the current stores after reading, including edits made while the provider was busy. The entire document is validated first. Commits now follow Android's order: tracks, waypoints/folders, graphics/routes, course history, then settings. Earlier iOS code committed the combined field-data store before waypoints, which could restore graphics/history too early after a waypoint failure. Each section remains durable and additive; a failure reports completed sections, leaves later sections untouched and supports an unchanged-file retry. Existing IDs, waypoint selection and existing folder visibility are retained. Duplicate field restores no longer rewrite an unchanged archive.

Persistence currently remains synchronous on the main actor. Cancel applies to preparation, not a commit already underway. This milestone does **not** complete large-library restore responsiveness: repeated archive serialization, atomic writes, library listing cost, provider stalls and storage-pressure behavior still need performance work and physical-device checks. This is implementation work, not an iOS restriction. Active sessions, offline packs and quiet-inside boundaries remain outside the Android v1 backup contract.

## Verification

- Real ZIP64 provider reads and standard backup encoding assert execution off the main thread and reopen with matching content/settings.
- A suspended provider leaves the main actor free to edit/select a waypoint; completion merges both that edit and the backup into reopened stores.
- Cancellation tests cover a late provider, rejected concurrent requests, an old canceled restore overlapping a new export, failure reporting and retry.
- Real filesystem failures verify ordered partial progress, preservation of unreadable field data and additive retry. An unchanged field restore skips a blocked write target while a real edit still fails atomically.
- A native Files workflow exports a backup in night mode, deletes a mixed folder, imports the saved ZIP and verifies restored waypoints/graphics/tracks, relaunch persistence and untouched Base records. Screenshots were inspected for readability.

Full hosted CI and physical file-provider/storage checks remain separate gates.
