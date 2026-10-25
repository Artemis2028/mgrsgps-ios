# Map lasso selection

Reference: Android `release/1.1.0` map selection and the `eacf084` review fixes in
`map/Lasso.kt`, `MapScreen.kt`, `WaypointRepository.hideAll` and
`GraphicsRepository.hideAll`. The native entry is Map tools → Lasso select.

Drag a freehand loop; lifting closes it implicitly. Alternatively tap corners
and choose Select loop. Select visible provides an alternative without a drag.
The map's pan/zoom/rotation are disabled during lasso; controls remain reachable.
After selection, markers have rings and every selected graphic vertex has a dot.
Again starts over; Close restores normal interaction. Choosing a graphic, lane
or quiet-inside boundary drawing ends lasso. Quiet-inside monitoring and remote
TAK overlays remain separate.

Containment follows Android's even-odd screen-space rule, including concave and
self-overlapping loops. Only currently visible saved waypoints and graphics in
visible folders are eligible. A graphic needs at least one stored vertex inside;
an edge merely crossing the loop is not enough. Tracks, live recording, lanes,
monitored boundaries and remote TAK contacts are not lasso items. Projection uses
the map's current world copy across the date line. Finite bounds reject invalid
projections and quickly exclude distant points. Gesture storage is bounded.

Hide explicitly writes false. It never swaps a selected item back on after an
external visibility change or retry. Delete asks for confirmation before changing
either store; Cancel keeps the selection. Operations stage snapshots on workers
and publish only after durable atomic writes. Each store commits independently,
matching Android. On partial failure, completed IDs leave the selection and the
error identifies remaining work. Retry touches only that remainder. Revision
checks rebase concurrent edits/selection before publication, and an unreadable
original waypoint library is never replaced. Deleting the selected waypoint also
clears its durable selection. Leaving the tab does not interrupt a confirmed
atomic phase.

Core tests cover even-odd/concave/degenerate/invalid geometry, visibility and
folder filtering, local-only scope, vertex-versus-edge selection, staged atomic
failure, foreign/stale tokens, concurrent visibility/selection, idempotent hide
and deletion durability. Native tests replay pan states through the production
recognizer handler against a real MapLibre projection, including cancellation,
reviewed-selection retention and closing. Filesystem integration checks both
failure phases and partial retry without reshowing completed points.

Physical dragging, large Dynamic Type/rotation, outdoor readability and very
large-library performance remain field validation. The phone gesture has not
been added to either watch; watch maps remain read-only cached scenes.

Validation milestone: all 405 core tests pass. The clean final native bundle
`/tmp/gridfix-lasso-final-native-20261025.xcresult` passes all 176 app integration
tests and both day/night workflows. Those use actual corner taps/projection,
assert the 44-point action height, confirm/cancel deletion, verify zero visible
items after Hide/Delete, switch to graphic drawing and relaunch. Exported
selection, empty-map and night confirmation screenshots were inspected. The
native pan replay separately covers the freehand handler. This does not claim
physical finger interaction. The final unsigned Release build includes the
phone, embedded watch and Live Activity extension.

The first UI bundle exposed a SwiftUI container identifier overriding child
identifiers. The next found a deletion popover without a reachable Cancel;
the final version uses an explicit native alert. Those earlier failing bundles
are not claimed as passing. A final day-mode rerun covers the disabled-action
contrast adjustment after screenshot review.

After the disabled-control adjustment, the complete 176 native integrations pass
again (`gridfix-lasso-race-native-20261025.xcresult`), including a deferred
Select visible request that closes/reopens before the UI queue drains. An old
request cannot select into the new presentation. The day workflow and final
Release build pass again; the disabled controls screenshot was inspected.
