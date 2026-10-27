# Worker-prepared graphic and track edits

Reference: Android `release/1.1.0` at `482b417`, `GraphicsRepository.kt` scoped
rename, point update, visibility and deletion operations. iOS keeps its native
map/route editors and the separate quiet-inside perimeter monitor.

`FieldDataStore.RestoreSnapshot.prepare(edit:)` applies an immutable edit intent,
validates/encodes the archive and writes a replacement file off the UI thread.
`publishEdit` checks the originating store instance and revision before atomic
rename and main-actor publication. A stale preparation is discarded and the
intent reapplied to current data. Successful publication is never retried; a
visibility swap therefore does not flip a record twice. Track logs and practice
history not targeted by the edit remain in the archive.

Normal map graphic saves, route-editor saves, graphic-panel/route-detail/track-
detail visibility and deletion, library-row graphic/track visibility,
track-folder moves and backtrack graphic publication now use this path.
Graphic creation retries keep an already-present ID. Editing patches
only fields changed from the original draft, preserving concurrent changes to
other fields, and cannot recreate a deleted graphic. Exact string bytes detect
canonically equivalent Unicode edits. Creation time remains unchanged on edits.
A new route editor retains its draft ID across saves/retries.

Graphic save then registers its folder using the worker-prepared waypoint merge.
Those stores commit independently. If folder publication fails, the error states
that the graphic was saved; retry keeps that record and its newer metadata while
finishing folder registration. Current waypoint selection and folder visibility
are retained. Background edits rebase after imports, recordings or other changes.

Confirmed edits show progress and block duplicate commands. Map point editing
is frozen during save while the camera/GPS remain separate. An owned task finishes
its atomic phase even if its view leaves; late completion cannot dismiss a new
presentation. Editors keep their draft and show a failure when persistence fails.
This does not promise continued background execution or recovery of an unsaved
in-memory draft after process death.

## Validation and remaining work

Core tests verify invisible preparation, atomic publication, stale swaps,
concurrent metadata/geometry/new recordings, deletion conflicts, create retry,
owner-bound tokens, failed replacement, folder/batch/log handling, unreadable
archives and Unicode identity. App tests use the production async path for
publication/thread checks, selected-target retention, partial folder failure and
retry, cancellation/ownership, duplicate commands and failure/retry state.

A local model run applies two concurrent edits to a 1,000-route archive with
50,000 track points, preserving both intents and all log bytes. It took 0.753 s
with 376 main-actor pulses and a 0.005 s largest observed gap. Timings are recorded,
not hardware-dependent pass thresholds; map rendering is a separate cost.

Later milestones moved ordinary waypoint, mixed batch/folder, recording and
course-result UI operations to worker-prepared actions; the release inventory
records their scoped evidence. The core synchronous APIs remain for compatibility
and fixtures and share the same edit transform. Eager finished-log startup
validation and crash-orphan maintenance remain separate implementation work.
Dense map rendering/accessibility, physical storage pressure, battery and file
protection still need validation; they are not iOS permission restrictions.


## Saved-source publication, 27 October

Worker snapshots retain the saved index/legacy source they actually read. A
short shared publication gate checks that source before the final atomic index
rename, including across live store instances. Stale edits/restores cannot
replace newer files, and rejected staging removes only its own fresh log names.
The error keeps the current files and asks the user to reopen before editing.

A worker-held metadata digest permits an exact-byte repaired index/archive to
replace its inode and retry. A different source, or deletion of the old index,
is refused. The metadata digest is calculated on the read/preparation worker;
final publication does not hash or decode full logs. This in-process gate does
not claim coordination with arbitrary noncooperating external writers. Saved
format, additive IDs, record order and published logs stay unchanged.
