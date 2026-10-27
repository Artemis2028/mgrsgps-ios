# watchOS tactical control measures

Reference: Android `release/1.1.0` (`482b417`),
`app/src/main/java/app/gridfix/android/map/ControlMeasuresOverlay.kt`. The iOS
phone already ports its 30 field graphic presentations in
`App/Sources/Map/TacticalGraphicCanvas.swift`. watchOS now compiles that same
source instead of drawing only plain lines/polygons and short type badges.
This retains Android's simplified field-symbol conventions; it is not a claim
of implementing every symbol in MIL-STD-2525.

The shared drawing covers axis outlines, direction arrows, FLOT arcs, obstacle
teeth, wire marks, parallel lanes, minefields/strongpoints, boundary echelons,
S/G/C line badges, route vertices/leg numbers, typed areas, range rings, sectors,
TRPs, checkpoints, decision points and text. At wider zoom the watch omits
detailed names but retains meaningful tactical prefixes/badges, text items and
route leg numbers. Simplified routes now carry exact original vertex ordinals and label each displayed
segment with its original leg range, such as1–125. Legacy simplified scenes
without this metadata remain unnumbered. The normal phone's numbering stays
unchanged. See [original route ranges and validation](watch-route-leg-ranges.md).

## Native-map projection and layering

`WatchTacticalGraphicLayer` is a transparent, noninteractive SwiftUI Canvas
inside MapReader. MapProxy supplies actual view coordinates and the visible
MKMapRect supplies world-pixel scale. `WatchGraphicProjection` moves the first
vertex to the world copy nearest the viewport, then keeps each following leg
local. It retains all supplied bends, including date-line crossings, and
rejects invalid projection arithmetic. Continuous camera updates redraw the
artwork during pan/zoom; they do not move the user or start navigation.

The CoreGraphics drawing uses a pushed UIKit context for the shared text/path
code. Native waypoint annotations remain available for accessibility. A fresh
watch location dot is repainted above tactical text/fills so an overlapping
graphic cannot hide it. Its source/freshness/permission policy is unchanged.
The native Legal caption's small text area is reserved; the entire canvas
passes gestures through, so no large touch-target hole is needed. The first
44pt attribution cutout was too large and visibly interrupted a nearby wire;
the final caption-sized exclusion fixes that and is shown in the final image.

Visible-folder filtering and complete context replacement are unchanged.
Quiet-inside fences, tracks, L/R/BS navigation lanes and TAK remain separate
layers. Existing bounds, whole-area omissions and line simplification still
apply; no watch crossing detector, background navigation, alert or haptic
source is introduced.

## Evidence

- Seven final native cases pass: all 30 drawings are distinct, doctrinal
  presentations differ from plain lines, long routes retain their final bends,
  off-screen obstacle decoration avoids walking millions of marks, simplified
  route number ink can be suppressed, and three projection cases check
  forward/reverse date-line bends, actual Mercator scale and invalid arithmetic.
  `/tmp/mgrsgps-watch-tactical-final.xcresult`; final parent exits 0 naturally.
  The preceding run's new number-ink assertion used a mirrored pixel-read
  transform; correcting the test's read coordinates gives the final passing
  result without changing the drawing or weakening the assertion.
- Paired simulator Debug and unsigned device Release builds (including the
  watch target) pass. Final Release: `/tmp/mgrsgps-watch-tactical-release-final.log`.
- Actual paired 40mm Watch SE context revision 101 contains axis, wire, screen
  line, strongpoint, route and minefield plus four native waypoint endpoint dots.
  `/tmp/mgrsgps-watch-tactical-delivered.json`. The shared paths align with
  those independently placed native markers.
- `/tmp/mgrsgps-watch-tactical-day.png` and
  `/tmp/mgrsgps-watch-tactical-night-pan.png` show those six drawings in day/night
  after a programmed camera pan/zoom. Camera logs show center
  24.454550,54.377100 moving to 24.455250,54.377800, with span shrinking
  0.005528 to 0.004146. This is programmatic camera-action evidence, not a
  physical-touch claim.
- `/tmp/mgrsgps-watch-tactical-dateline-day.png` and the final
  `/tmp/mgrsgps-watch-tactical-caption-dateline.png` show the three-vertex wire
  crossing +179.999 to -179.999/-179.997 as a local bent line, including after
  pan/zoom in night mode. The latter has the final small Legal-caption exclusion.
- `/tmp/mgrsgps-watch-tactical-fresh-confirmed.png` and
  `/tmp/mgrsgps-watch-tactical-night-fresh-confirmed.png` show WATCH FIX and the
  own-location dot above the screen-line badge in day/night. Fake samples move
  approximately 2m between reports, through actual simulator CoreLocation.
  Earlier sub-metre samples did not pass the existing 1m distance filter and
  yielded an expired fix; they are not claimed as fresh-location evidence.
- The original isolated phone workspace is restored into its current data
  container after reinstall. Actual context revision 130 restores the prior
  SYNTHETIC INF scene; 10-digit/night local overrides remain. Receipt:
  `/tmp/mgrsgps-watch-tactical-restored-map.json`. The owned pair and all fake
  feeds are stopped. No user device, Android checkout or TAK infrastructure is
  changed.

The final shared route-number guard is covered by native drawing tests; the
paired scene uses unsimplified routes. No paired large-route number-range
claim is made. Physical touch/wrist readability, all watch sizes/locales and
large text (including native Legal layout), dense overlays, real stationary
GPS behavior, sustained rendering/battery and storage pressure remain checks.
Phone offline-pack/terrain transfer and independent watch guidance remain
implementation gaps, not platform prohibitions.
