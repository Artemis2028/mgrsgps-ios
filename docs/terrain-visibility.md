# Terrain visibility and elevation profiles

Reference: Android `release/1.1.0`, commit `482b417`. The native port follows
`TerrainSight.kt`, `TerrainGeometry.kt`, `Terrain.kt`, `Elevation.kt`,
`ViewshedOverlay.kt` and the LOS dialog, including Android's numeric test vectors.

Open **Map → binoculars (Terrain visibility tools)**. Choose observer and target
from the current position snapshot, map centre snapshot, saved waypoints, or a
typed MGRS/decimal coordinate. Heights are metres above ground, defaulting to
2 m at both ends. Inputs must be finite and between 0 and 1,000 m. The snapshots
stay fixed while the tool is open; moving GPS or the map does not silently change
an already computed answer. Changing a coordinate or height clears its result.

**Check line of sight** reports visible, masked or unknown, the first known
obstruction's distance/grid, minimum sampled clearance and its distance, and the
observer height that would clear the sampled terrain. Missing endpoint elevation
cannot define the sight line and produces an unavailable message. Missing
interior samples prevent a visibility or clearance promise. A known obstruction
can still prove masking despite a gap; required height and minimum clearance
remain unknown in that case.

The chart shows terrain and a dashed sight line in the same curvature-corrected
frame, with a blocking-point mark. Unknown terrain is a gap, never an invented
flat or sea-level segment. Saved routes have elevation profiles both in this
panel and through **Route card → Elevation profile**, with leg divisions,
distance, climb/descent and missing sample counts. Climb/descent use Android's
1.5 m anchor threshold and are qualified when samples are missing. With no known
elevation, the profile reports unavailable and omits the chart and climb/descent
totals, rather than suggesting a flat route.

## Viewsheds

**Shade map from observer** computes a 1, 2 or 4 km viewshed (2 km default),
fits it on the map and closes the panel. The result stays anchored during pan,
zoom and rotation; discrete classes and uncertainty hatching use nearest-neighbor
rendering. Tap the legend or use Clear map shade to remove it.

| Class | Meaning | Day | Night |
| --- | --- | --- | --- |
| Visible | A 0.5 m target is visible through sampled terrain | Green | Faint red |
| Marginal | Only a 3 m target is visible | Amber | Mid red |
| Masked | Even a 3 m target is masked | Red | Bright red |
| Unknown | Missing terrain prevents a conclusion | Gray hatching | Red hatching |

The source grid is 192 × 192 with 768 outward rays, using steps of 0.7 grid
cells. Unknown terrain propagates along each ray; a later known crest may still
prove masking. Cells touched by multiple rays retain the more conservative
class, so an unknown cell cannot be overwritten with green. The observer's own
cell is visible. Partial coverage beyond the DEM's 85° latitude limit stays
unknown instead of rejecting an otherwise valid shade.

Computations show progress and can be cancelled. Leaving the panel or putting
the app in the background cancels foreground analysis. Request tokens prevent
cancelled or superseded work from publishing late results. This does not stop
recording, navigation GPS, or quiet-inside boundary monitoring. A computed shade
is a temporary map analysis, not a saved tactical graphic or alert boundary.

## Data, sampling and offline use

Map-centre elevation and a local slope estimate appear in the map readout after
a short camera-settle delay. Slope uses a 30 m central difference and is labeled
a DEM estimate. Heights come from Mapzen/AWS Terrarium tiles at zoom 13, decoded
as `R × 256 + G + B / 256 − 32768` metres. Elevation is sampled at the nearest
source pixel, with invalid/no-data values left unknown. No parent-tile enlargement
is used for analysis.

LOS uses roughly 20 m sample spacing with an adaptive target of 500 intervals;
route profiles use roughly 25 m with a target of 600, retaining every leg end.
Positions follow the shortest great-circle arc, including the antimeridian and
a deterministic northward arc for antipodal endpoints.

The observer-to-target line uses the chord joining endpoint ground elevations:
Earth curvature **adds** `d × (D − d) / (2 × Re)` to interior terrain. Viewshed
rays instead use the observer's tangent frame, **subtracting** `d² / (2 × Re)`
from distant ground. Both use `Re = Earth radius × 4/3`, matching Android's
refraction assumption and 0.5 m clearance rule.

Analysis shares the existing saved elevation areas and 300 MiB DEM cache with
contours. A separate decoded-tile LRU holds 12 tiles. Recent failures are throttled
for 60 seconds using a monotonic clock, reset after an elevation download or a
network-mode change. Concurrent consumers share in-flight tile loads. Network
requests use 8-second inactivity and 16-second total timeouts. **Offline only**
prevents network lookup: cached/downloaded terrain still works, and missing
terrain stays unknown. Download elevation from Map layers before going offline.
Night colors affect presentation, never the encoded elevation values.

## Validation and practical limits

Core tests reproduce Android's 20 km/horizon/crest vectors, endpoint correction,
required observer height, gap propagation and conservative ray merges. They also
exercise dateline/antipodal sampling, route leg ends, partial polar coverage and
cancellation. Native tests verify PNG north/south orientation and fractional
Terrarium values, disk reuse without network, offline-to-online recovery,
no-data/cancel behavior and viewshed palettes/hatching. UI tests use real encoded
PNGs in the isolated normal cache to check a ridge obstruction, profiles,
missing data, and day/night shades; production data is not replaced by fixtures.

These are terrain estimates at about 10–30 m source resolution. Trees,
buildings, weather, local refraction and smaller obstacles are not modeled.
A sampled visible result is not a field guarantee. Physical terrain comparison,
outdoor legibility and battery behavior still require device verification.
