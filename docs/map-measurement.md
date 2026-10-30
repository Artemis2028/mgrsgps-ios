# Map ruler and area measurement

Reference: Android `release/1.1.0` (`482b417`), `MapScreen.kt`,
`RouteGeometry.routePolygonMetrics`, and `DatelineProjectionTest.kt`.

Open **Map → ruler icon (Map measurements)**.

## Distance ruler

**Distance ruler** anchors at the crosshair. Tap the map or a waypoint marker
to move the anchor, then pan to measure to the crosshair. The line and distance
update while panning. **Anchor here** resets the origin to the current crosshair;
**Done** removes the temporary ruler. It does not create a route, waypoint,
boundary or navigation session and does not require GPS.

Distance uses the same WGS84 inverse calculation as Android's location distance.
The selected distance and angular units apply. Azimuths follow true, magnetic or
grid north. Grid correction uses the crosshair position, matching Android's
ruler. **BACK** is the reciprocal of the displayed forward azimuth (+180°), as
on Android's ruler. Route cards separately compute the actual reverse geodesic
bearing at each endpoint.

Magnetic north uses the manual override or WMM at the usable current GPS position.
Without a usable fix, native iOS explicitly uses WMM at the crosshair and labels
that source, instead of Android's zero-declination fallback. An unavailable
magnetic reference shows a dash, not an invented azimuth. Grid north outside
standard UTM coverage is explicitly labeled as extrapolated. An expired WMM is labeled.

## Area measurement

**Measure area** opens a temporary closed sketch. Tap corners, drag numbered
points, and hold/drag a segment directly to add a bend. The visible **+** segment
handles also insert a point when dragged. Accessible Add point,
Move here and Remove selected point actions use the same editor as tactical
graphics. **Undo** removes the last corner, matching Android's drawing undo.
The map shows current area, perimeter and corner count once three points exist.

**Results** opens the detailed measurement. **Keep measuring** retains the
sketch. **Done** discards it. **Save as area** opens the usual graphic details;
choose its name/folder/appearance, close details and press **Save** to publish.
The resulting area has the same editing, visibility, persistence and backup
behavior as other area graphics. Neither measuring nor saving an area starts
quiet-inside monitoring. That remains a separate Backstops & handrails mode.

Area/perimeter use one common UTM zone and hemisphere selected from the first
corner. The translated shoelace formula preserves precision for small polygons
at large northings. Longitude displacements wrap at ±180°, matching Android's
dateline correction. Area units follow Android: m² below 10,000; hectares below
1,000,000; km² above that. Perimeter uses the selected distance units.

This is a local plane estimate, not a survey. Crossing edges may cancel portions
of the algebraic area. As on Android, measurement can extrapolate the UTM series beyond its standard
80°S–84°N coverage, within map coverage. The native readout labels that
extrapolation and its unverified local accuracy; it is not a platform limitation.

Temporary measurements are not restored after termination. Saved areas are.
Night controls use opaque black surfaces and red readouts. In compact landscape,
map tools become a horizontal row and drawing actions take the place of the
general bottom action row to leave usable space for the sketch.

## Validation

Core tests reproduce Android's 888.445831 m / 49332.943265 m² dateline polygon,
opposite winding, a repeated closing point and a zone-one starting corner.
They cover small high-latitude polygons, coverage, unit thresholds, forced-zone
dateline projection and ruler reference/reciprocal rules. UI workflows exercise
anchor taps/panning/reset, day/night readouts, corner undo and midpoint dragging,
results, save/relaunch, discard, and landscape action reachability. Real outdoor
readability and use with large imported graphic libraries still need device
verification.
