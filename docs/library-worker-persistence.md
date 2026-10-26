# Staged library mutations

The native Waypoints library now prepares favourites, waypoint visibility,
folder visibility/create/rename/remove and mixed visibility/deletion batches
on workers. Snapshot encoding, full JSON/ZIP generation and temporary-file
writes leave the UI executor; only revision verification, atomic rename and
publication return to it. This extends the editor/import staging model to
ordinary library controls. Progress disables competing controls. A failed write
leaves that repository's published memory unchanged and reports an error.

Android reference: WaypointRepository.kt setFavorite, setFolderVisible,
renameFolder/deleteFolder, and GraphicsRepository/TrackRepository folder
operations at the inspected 56acca2 checkout. Case-matched folder names,
visible-source merge, permanent Base, selection retention/removal, and
independent item/folder visibility retain the existing Android policy.
The Swift core tests also compare each staged operation with the preceding
synchronous implementation against identical stored records.

## Ordering and retry

Immutable preparation records the source store identity and revision. A stale
preparation is discarded and rebuilt from the latest library; scoped changes
retain concurrent target selection and unrelated record changes. A missing
favourite target is reported rather than recreated. Unreadable source files
refuse preparation and remain untouched. Confirmed atomic phases finish when
the owner leaves; a completion only dismisses its still-visible presentation.

Mixed batches retain Android's independent repository commits. Waypoint IDs
leave the pending selection only after their phase is durable. If the graphics/
track archive phase fails, only those remaining IDs are retried, so already
completed waypoint visibility swaps cannot flip twice. Folder rename/removal
still updates graphics/tracks first, then waypoint/folder settings. A second-
phase failure explicitly reports what moved and keeps the folder draft for
retry; no global cross-file transaction is claimed.

The folder form now owns an asynchronous mutation: progress, retained error/
name, disabled Save/Cancel while writing and dismissal only after success.
Track opening decodes its complete saved log on a worker and stages any folder
unhide, then focuses the map only for a visible owner and a still-saved track.
Backtrack folder registration/unhide uses one staged operation before route
publication and rechecks that the source track still exists.

## Validation

437 core tests pass. New cases cover unchanged disk/memory before publication,
legacy merge semantics, source/store/revision guards, concurrent selection,
deleted targets, blocked publication/retry and unreadable-source preservation.
The native 193-case suite passes with two unstaged local TAK opt-in skips.
New native checks verify Main-thread publication under a 5,000-point save and
real blocked-archive partial retry without repeating a waypoint swap.

The first UI matrix passes favourites/search, night controls, mixed visibility/
delete, hidden-track viewing, folder cancellation/rename and empty-folder
relaunch. Its final clear-graphics assertion read the old listing before the
background refresh completed; it now waits for the same exact resulting counts.
The completed folder deletion and counts remain asserted.

Day/night fault workflows deliberately replace only the isolated UI-test
waypoint destination with an empty directory after creating valid synthetic
stores. A real graphics/track rename commits, the waypoint publication fails,
the form keeps Patrol and reports the partial result, and an explicit test-only
repair permits retry. Relaunch verifies one waypoint/graphic/track in Patrol.
These hooks require DEBUG and -uiTesting; they cannot alter production storage.

Final native/UI evidence: `/tmp/gridfix-library-worker-final.xcresult` passes
193 native cases (two opt-in TAK skips) and five UI workflows: day/night
partial folder failure/retry/relaunch, mixed-folder rename/remove/clear,
hidden-track viewing/moving, and waypoint/map/folder visibility. Day/night
error and persisted library screenshots were inspected.

After the final backtrack staging change,
`/tmp/gridfix-library-backtrack-verified.xcresult` passes all five backtrack
integrations and both existing native backtrack UI workflows. The additional
integration deletes the source track during folder publication and verifies
that no late route is created. The final phone/watch/widget simulator Release
build and all six CI partition/location-feed script tests pass. The new UI
class is automatically assigned exactly once to the library shard.

## Remaining work

Navigation target/session saves now use [runtime worker staging](navigation-runtime-persistence.md). Practice
setup/selection/scoring still have synchronous paths; result history/final clear now use [worker staging](practice-result-persistence.md). Recording final archive
publication was subsequently staged; see [recording](track-recording.md). Older FieldLibraryView actions and startup archive reads
need their own audit. Dense-map/large-library accessibility, physical storage
pressure, locked-device behavior and external file-provider checks remain open.
These are implementation/verification work, not iOS platform prohibitions.

Route-generated waypoint replacement was subsequently staged; see
[route generation](route-waypoint-staging.md).
