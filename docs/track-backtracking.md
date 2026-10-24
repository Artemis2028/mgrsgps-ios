# Recorded-track backtracking

Reference: Android `release/1.1.0` (`482b417`), `TrackSimplify.kt`,
`TrackSimplifyBudgetTest.kt` and `GridFixApp.onBacktrackTrack`.

Open a finished track's menu in **Waypoints → Tracks → Create backtrack route**,
or use **Routes & tracks → track details → Create backtrack route**. The app
reads the full saved log, reverses its positions and creates a new route named
`Back <track name>` (20-character name limit), in the track's folder.

The new route starts at the recording's end and reaches its beginning. Native
iOS fits the full route on the map, makes its folder visible, and keeps the
recording/log intact. Creating it does not select generated waypoints, start
automatic route following, request navigation GPS, or turn on haptics. Open its
route card and explicitly Follow route when ready.

## Shape and point budget

Match Android's largest-deviation-first simplification, targeting 20 m local
shape detail with a maximum of 64 vertices. Both endpoints always survive;
the algorithm spends the remaining budget on the worst deviation anywhere in
the track, with the lower original index breaking ties. It never truncates a
long simplified list, which could remove the route's destination.

Distances are to the finite segment rather than its infinite extension, so an
out-and-back turnaround is retained. Longitude differences wrap at ±180°.
The local projection uses Android's 111,320 m/degree scale and latitude-based
longitude scale. If the 64-point budget is exhausted, the 20 m tolerance is not
guaranteed. This is a simplified recorded shape, not a terrain or safe-path
calculation; review it before following, especially around missing recording
intervals and sharp bends.

Decoding and simplification run off the UI thread. Cancellation or removal of
the source track before publication prevents a late route from appearing. A
failed route write does not publish the route or delete/change original track
bytes. Changes to track name/folder during preparation use the current metadata
at publication. A track needs at least two recorded positions.

## Validation

Core tests reproduce Android's full-recording budget, largest late bend,
collinear turnaround, noise tolerance and two-vertex-budget cases. They add a
dateline dogleg, invalid-input checks, reversed endpoints, folder/name behavior
and original-byte preservation. Native integration tests check persistence,
unchanged selected target, cancellation, source deletion and failed writes.
UI workflows exercise both entry points, map display, route cards, relaunch,
original-track retention and absence of automatically started guidance.

Outdoor route review, long-recording performance and physical navigation remain
part of device field validation. The existing finished-data archive budget is
unchanged and remains a separate parity item.
