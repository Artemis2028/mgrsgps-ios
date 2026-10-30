# Review records already here

Reference: Android `4db6b21`, updated by committed review `eacf084`.
This applies to pasted and file-based GPX, CSV, GeoJSON, KML, KMZ and ATAK
interchange. Full backups retain their separate additive restore workflow.

After Import, a worker compares the parsed content against an immutable snapshot
of the current library. Name indexes avoid scanning every stored item for every
incoming record. Names are trimmed and lowercased. Waypoints match when both
latitude and longitude differ by strictly less than 0.00001 degrees. Graphics
match the name, number of vertices, and every ordered vertex under that same
threshold. Type/folder/style are not part of Android's duplicate test. Tracks
match the name, point count and a distance difference strictly less than one
metre; this is a length comparison, not a coordinate-by-coordinate track test.

If matches exist, Already here offers Skip N, Import all and Cancel. Cancel
keeps the preview open without saving anything. Skip filters matching incoming
records, then prepares the retained content's Android namespace and ordinals.
Import all uses the original prepared document. Existing matching IDs keep their
stored edits; importing unchanged content again does not force extra copies.
Different incoming content can have different IDs even when its name/place
matches, which is why this review is separate from ID-based safe retries.

Checking and filtered preparation are cancellable and do not write records.
Text edits, sheet departure and replacement invalidate late results. Once a
choice is confirmed, the existing owned commit finishes started atomic phases,
reports partial progress and prevents duplicate confirmation. Queued incoming
file URLs stay behind the current file's review rather than replacing it.
Import all and Skip continue to use Android's track → waypoint/folder → graphic
commit order. No choice changes app settings or starts navigation.

Validation: the complete core suite passes 366 tests. Cases cover Android's
name/place/line/track fixture, strict thresholds, reversed/moved vertices,
track length, retained folders, stable filtered IDs, untouched original content
and a 5,000-record indexed comparison. All 159 app integration tests pass, and
the native CSV preview/cancel/import/Skip/relaunch regression passes. Expanded
native Cancel/Import all/mixed Skip/day/night checks pass. The Cancel path
leaves the preview available, Import all/retry preserves existing and imported
records, and Skip retains the new waypoint through relaunch. Day/night prompt
screenshots were inspected. After shortening the prompt copy, both native
review workflows passed again and their final day/night screenshots were
inspected. The final unsigned phone/watch/activity-extension Release build
passes. The test-owned phone simulator is stopped. Physical
provider/Open In, queued external-file delivery and storage-pressure checks
remain required.
