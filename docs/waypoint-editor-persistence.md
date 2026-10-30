# Durable waypoint editor saves

The ordinary map/library editor now waits for a successful save before it closes.
Previously its callback called nonthrowing `WaypointStore.add/update`, which
published memory changes and silently ignored a failed JSON write. The sheet
then dismissed even though relaunch could lose the point.

`WaypointEditAction` captures an immutable store revision, prepares/encodes a
replacement file on a worker, then publishes the atomic rename and memory state
on the main actor. A stale revision rebases from the latest store. New points
keep one presentation-owned ID and creation time across preparation/retry;
a repeated completed create returns its existing point instead of duplicating.
Editing a point removed while the sheet was open fails rather than resurrecting
it. Fields the editor did not change retain concurrent edits, visibility,
favourites, route ownership and interchange metadata. Exact UTF-8 name changes
are retained, including canonical Unicode equivalents.

Android `WaypointRepository.add` selects a new point when no selected target
exists. Editor creation now matches that, retaining an existing selection and
respecting the practice-course target lock. This selection is included in the
same durable snapshot, not written as a second operation.

Saving disables duplicate saves and interactive dismissal until the confirmed
operation finishes. A persistent banner directly below the navigation bar shows
progress/errors even when the form is scrolled. Failure leaves the draft in the
editor; retry uses the same ID. A save finishing after its presentation leaves
does not dismiss or select into a newer presentation. Both parent callbacks now
receive an already-saved waypoint and perform only their UI updates.

An unreadable existing waypoint file sets `loadError`, displays a library
warning, and is retained. Staged edits/restores and direct file writers refuse
to overwrite it. There is no automatic empty replacement. The explicit [recovery screen](waypoint-recovery.md)
can retry loading, preserve/share the original, or archive it before a confirmed
empty-library replacement. Some legacy non-editor mutation
APIs still update synchronously or ignore write errors, although the corrupt-file
write guard applies to them. Their remaining performance/error work is tracked
separately; this milestone does not claim all library/session I/O is asynchronous.

Validation:

- Six core tests exercise staging without publication, atomic write failure and
  stable retry, existing selection/folder-eye retention, concurrent field changes,
  deleted-point refusal, exact Unicode, wrong-store tokens, unreadable-file
  retention and first-target/practice-lock behavior.
- Native tests use the real filesystem/publication path, assert main-thread
  publication, failure/retry durability, and a 5,000-point save overlapping a
  selection change. Both the new point and latest selection survive reopening.
- A clean native bundle passes all 173 integrations plus two day/night failure
  workflows. The UI workflows block the real destination, verify the visible
  error and retained draft, repair only their explicitly temporary test storage,
  retry, verify one point and relaunch. Exported screenshots were inspected.
- Existing native coordinate-edit/relaunch and map/navigation/folder-visibility
  workflows also pass. That earlier combined bundle failed the first version of
  the new error-visibility test; it is not described as an overall passing run.
- The final core suite passes 399 tests; targeted native save tests and day/night
  failure workflows pass again after the first-target/copy adjustment.

Physical storage-pressure/provider checks, remaining legacy non-editor writes,
and dense-map/library performance remain.
