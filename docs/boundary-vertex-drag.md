# Boundary and graphic point dragging

Hosted103 (`bc52ed8`) inserted the fifth boundary point, then left that selected
point at its old coordinate after the next hold/drag. The full tree, synthesized
input and recording agree that the input started at the correct point. The exact
internal SDK failure is not established. The editor now owns the UIKit hold/drag
rather than relying on reusable MapLibre annotation-view drag state.

A gesture captures its source annotation, origin, callback and current draft
identity/geometry. The original grip offset keeps the point under the finger.
Map pan/zoom/rotation pause while the gesture owns the point, including through
ordinary SwiftUI refreshes, and return afterward. Source replacement, view reuse,
view removal or cancellation restores the original point and clears its preview;
a cancelled transaction cannot later commit. Release publishes once to the same
still-current boundary or graphic. A pending camera fit is cancelled at drag start.
Midpoint activation retains its accessible insertion action and its annotation
title now describes adding a point, matching MapLibre's actual accessibility label.

Lines follow the finger through a transient geometry copy. Boundary previews use
an outline while moving; full polygon/fill validation remains on accepted geometry,
avoiding repeated intersection validation on each preview sample. Tactical graphics
use the existing renderer with a transient draft. Location/settings/style refreshes
reapply the same preview, and the actual editable/saved geometry changes on release.
This preserves cancellation and prevents an unfinished drag from becoming saved or
shared geometry. Other points and metadata stay intact.

Compared Android `release/1.1.0` (`482b417`) `ui/screens/MapScreen.kt`: its point
drag consumes movement, projects through the map and redraws the edited line.
iOS keeps the user-requested hold-to-move interaction and explicit removal control;
Android's hold-to-delete behavior is not copied over that request. Native geometry,
snapping, save/reopen and the separate quiet-inside monitor remain in place.

## Validation

- `/tmp/mgrsgps-vertex-preview-final.xcresult`: 338 native cases, four opt-in
  skips and no failures, then all ten boundary/graphic UI workflows pass. Seven
  new native cases cover one final commit, cancellation, captured source/callback,
  reuse/accessible activation, source invalidation, non-accumulating midpoint
  preview and point preservation/invalid-index refusal.
- The original failing workflow now requires three consecutive inserted-point
  drags without a preparatory tap, retaining exact coordinate-change and five-
  point assertions. Day/night cases also pan afterward, require the centre grid
  to change and require the selected boundary coordinate to stay unchanged.
  Night edit/save/relaunch, direct side bending, background exits/interrupted
  restart, route point dragging/reopen, waypoint snapping, fixed graphics and
  tactical-boundary separation all pass in that final bundle.
- `/tmp/mgrsgps-vertex-preview-route-runtime.mp4` records the actual route UI.
  Inspected frames `/tmp/mgrsgps-vertex-preview-route-midpoint.png` and
  `/tmp/mgrsgps-vertex-preview-route-point.png` show lines attached to the moving
  midpoint/point with the uncommitted form state. Final route and night controls
  screenshots from the bundle are inspected. Native test values are distinct
  from physical touch/latency evidence.
- Earlier `/tmp/mgrsgps-vertex-drag-first.xcresult` passes 335 native cases and
  the strengthened formerly failing workflow; `/tmp/mgrsgps-vertex-drag-ui.xcresult`
  passes the ten UI cases before live-preview/source-context refinements. The
  final bundle above supersedes those source versions; their repeated cases are
  not counted again as extra distinct workflows.
- Eight harness checks pass in `/tmp/mgrsgps-vertex-preview-harness.log`.
  Final phone/watch/widget unsigned device Release passes in
  `/tmp/mgrsgps-vertex-preview-release.log`. Final test/Release/capture parents
  finish naturally with 0. The fake route is stopped, location cleared and the
  only owned simulator shut down.

The private capture helper initially missed the boundary method; only the completed
foreground route capture above is claimed as video evidence. No active test was
stopped. Local iOS26.2/23C52 with Xcode27.1 remains distinct from hosted23C54 with
Xcode26.6. Hosted103 remains failed; the next full hosted run must verify this new
source. Physical finger cancellation, edge-of-map dragging, older devices,
rotation/suspension, dense geometry performance and VoiceOver navigation remain
checks. This does not add independent watch alerts or change TAK infrastructure.
