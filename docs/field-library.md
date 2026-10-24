# Waypoints, graphics, tracks and folders

Reference: Android `release/1.1.0` (`482b417`), `WaypointsScreen.kt`,
`WaypointRepository.kt` and the library callbacks in `GridFixApp.kt`.

The **Waypoints** tab lists waypoints, graphics/routes and finished tracks in
separate sections. **All** includes every record, including records hidden on
the map. Individual folders filter all three sections together. Folder labels
remain visible in All; dimmed cards and an eye-slash distinguish hidden records.
The existing Routes & tracks entry also retains route editing/navigation,
track details and practice-history access.

Search narrows every section. Waypoints match name, folder, unit designation or
the full ten-digit MGRS grid, with or without spaces (at least three compact grid
characters). Graphics and tracks match their names. Folder filtering still applies.
The clear control resets the query; submitting Search dismisses the keyboard.

Favourites lead every ordering. **Distance**, **Name** and **Newest** match
Android's `WaypointListing.kt`: distance uses **25 m buckets** then case-insensitive
name; without a fix it falls back to name. Newest uses descending creation time,
then name. Equal keys retain repository order. Ordering applies across folders
when All is selected. Unicode simple casing/order is checked against an actual
JVM `String.CASE_INSENSITIVE_ORDER` fixture rather than locale collation.

Use a waypoint's action menu to add/remove its favourite star. This flag is
independent of map visibility, selection, course/route ownership and metadata.
Old iOS waypoint files without the field decode as false; new local files and
Android-compatible v1 backups preserve it. A failed flag write does not publish
an unsaved change. Military-symbol search remains a separate picker.

## Mixed selection

Tap the check-circle beside the counts, or **Waypoint actions → Select items**.
Every card becomes one selection target, keeping its normal navigation/edit
actions from firing. Select all replaces the selection with the currently
listed records; selecting another folder does not silently select new items.
Select none and Done clear the selection. Removed records are pruned from it.
Waypoint, graphic and track IDs occupy independent namespaces.

**Selected item actions → Swap map visibility** flips every selected record's
own visibility flag. A mixture of shown and hidden records therefore exchanges
states; it does not force them all to one value. Folder visibility is separate.
**Delete selected** confirms the counts by record type and includes finished
track point logs. Cancel keeps the selection. These operations do not include
an active recording or quiet-inside definitions.

Each repository commits one complete atomic snapshot before publishing changes.
As on Android, the waypoint and field-data stores commit independently. If the
second store fails, the UI reports the completed count and keeps only unfinished
IDs selected. Retry cannot accidentally flip already committed visibility a
second time. A failure before the first commit leaves every selected record
unchanged. There is no claim of one cross-file transaction surviving a crash.

## Folders

**Folder** adds an overlay even when it is empty. Names are trimmed, match
existing names case-insensitively, and explain the legacy reserved names that
map to Base. The eye controls map visibility without hiding library cards.
The selected folder's **Folder options**, or a folder-chip context menu, exposes
rename and removal. Base is permanent.

Rename moves waypoints, graphics and finished tracks together. Renaming onto
an existing folder merges them; either visible folder makes the destination
visible, matching Android's merge policy. Waypoint IDs, route ownership,
interchange metadata and track bytes stay intact. Removal offers **Keep contents
in Base** and **Delete folder and contents**. A folder with multiple graphics
also has a confirmed Clear graphics action, including in Base; it leaves
waypoints and tracks intact. Absolute folder moves/deletions are safe to retry
if the UI reports an interrupted second-store update.

Track menus support moving to another existing folder, visibility, GPX export,
details and confirmed deletion. Showing a hidden track temporarily displays it
without changing its saved record visibility; its folder is made visible, as on
Android. Stop viewing removes that temporary override. Show on map fits the
track rather than fabricating a new route or starting navigation. Graphic and
waypoint menus also offer map focus; route cards remain available directly.
Tracks can also create [reverse backtrack routes](track-backtracking.md), with
the original point log retained and no automatic guidance startup.

## Validation and remaining work

Core tests cover distance buckets/order, hidden mixed states, independent ID
namespaces, folder visibility merges, Base protection, empty-folder persistence,
track-log preservation/deletion, failed writes and partial-batch retry. Native UI
workflows cover selection/filter changes, deletion/relaunch, visibility swaps,
rename/remove/clear, track moves/viewing, empty folders and red night forms.
Search/favourite tests additionally cover old local-file migration, Android backup
round trips, stable Unicode case ties, all sort modes, compact-grid queries and
failed favourite writes. The new UI checks cover cross-section queries, selection
of only visible results, favourite relaunch/removal and night search. Coordinate/route/GPX
workflows remain regression coverage.

Physical field legibility and very large-library performance still need device
validation. Finished field data currently retains the existing archive storage
budget; this milestone does not remove that separate limitation.
[Practice courses](practice-courses.md) are implemented separately; additional
interchange formats remain on the parity checklist.
