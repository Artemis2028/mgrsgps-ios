# Waypoints, graphics, tracks and folders

Reference: Android `release/1.1.0` (`482b417`), `WaypointsScreen.kt`,
`WaypointRepository.kt` and the library callbacks in `GridFixApp.kt`.

The **Waypoints** tab lists waypoints, graphics/routes and finished tracks in
separate sections. **All** includes every record, including records hidden on
the map. Individual folders filter all three sections together. Folder labels
remain visible in All; dimmed cards and an eye-slash distinguish hidden records.
The existing Routes & tracks entry also retains route editing/navigation,
track details and practice-history access.

With a usable position, waypoints sort by distance in **25 m buckets**, then
Android's name ordering. Small GPS changes within a bucket do not rearrange
the list continuously. Without a usable fix, repository insertion order stays
intact. Ordering applies across folders when All is selected. Android 1.1.0 has
no waypoint search, favorites or user-selectable sort picker; those were
incorrectly listed as missing parity in an earlier inventory. Military-symbol
search is a separate, implemented picker.

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
The existing coordinate/route/GPX UI workflows are run as regression coverage.

Physical field legibility and very large-library performance still need device
validation. Finished field data currently retains the existing archive storage
budget; this milestone does not remove that separate limitation or implement
practice courses or additional file formats.
