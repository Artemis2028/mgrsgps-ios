# Resection and intersection

Reference: Android `release/1.1.0` at `482b417`, `FieldTools.kt` and
`Coordinates.rayIntersection`.

The map's ruler / field-tools menu opens Resection or Intersection. Resection
uses two azimuths sighted **to** known points and applies their back-azimuths
automatically. Intersection uses the target azimuths **from** two observers.
Both provide the map crosshair and saved waypoints as known-point choices;
Intersection additionally offers the phone's fresh current position if available.
Point coordinates are captured when the form opens, so a moving phone or a
library refresh cannot silently change the worksheet.

Inputs use the selected true, magnetic or grid reference and degrees or NATO
mils. Reference conversion is evaluated at each known point. Remote declination
uses the bundled WMM or manual setting, not the phone's heading. Missing
reference values prevent a result; magnetic model expiry and manual overrides
are visible. Degrees accept 0-360 and mils 0-6400, including a full turn.

The solver follows Android's first-point UTM-zone ray intersection, with
per-point convergence, forward-ray tests and a 100 km limit along each ray.
Invalid/non-finite coordinates, points outside 80S-84N UTM coverage, coincident
points, near-parallel/diverging rays and out-of-range intersections have no fix.
The angle of cut is shown; below 30 degrees or above 150 degrees gives the
Android poor-geometry warning without inventing a confidence radius.

A valid answer shows an eight-digit MGRS grid and both ranges in the selected
distance units. Show on map moves the camera without saving or starting a
guide. Save waypoint allows a name and durably adds a target symbol to Base
(hostile for an intersection target; no affiliation for resection). A failed
save leaves the worksheet available to retry. Neither action changes selected
navigation, active route following, quiet-inside monitoring or track recording.

Core checks exercise Android's known two-observer fix, automatic back-azimuths,
mils, per-endpoint magnetic/grid conversion and invalid/unsafe geometry. Native
UI workflows cover showing, saving/relaunching, validation and night warnings.
These calculations still require physical compass/reference and field checks;
eight-digit formatting is not a promise of ten-metre position accuracy.
