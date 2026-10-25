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

Waypoint JSON edits, generated waypoint updates, mixed cross-store batches
(including row deletion through mixed selection) and folder changes,
recording finalization and course-result persistence still have
synchronous paths to address. Their semantics remain intact. Dense map geometry/
rendering/accessibility, physical storage pressure, battery and file protection
also need validation. These are implementation/validation gaps, not iOS permission
restrictions. The core synchronous APIs remain for compatibility and fixtures;
they share the same edit transform with staged publication.
