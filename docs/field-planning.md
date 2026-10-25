# Waypoint projection, sun/moon and declination planning

Reference: Android `release/1.1.0` at `482b417`, `WaypointDialog.kt`,
`FieldTools.kt`, `coords/SunMoon.kt` and osmdroid `GeoPoint.destinationPoint`.

## Project a waypoint

The waypoint editor has Coordinate and Project position modes. Project accepts
a base from the entered/original coordinate, a usable current GPS fix, or any
saved waypoint (including hidden points). Base coordinates are captured when
Project is selected. Changing bases, azimuth or distance updates the preview;
Save uses the full calculated coordinate and the editor's ordinary metadata.
Returning to Coordinate preserves the entered/original position and precision.
Invalid projection input disables Save and explains the problem.

Distance is always metres, greater than zero through 200,000 m. Bearing uses
the selected degrees/NATO mils and true/magnetic/grid reference. Non-negative
full turns wrap around north, matching Android's projection behavior. The
bearing correction is evaluated at the base; magnetic values use the manual
setting or bundled WMM, not a remote use of the phone's heading. Missing
references prevent projection and expired models are explicit. The destination
uses Android/osmdroid's 6,378,137 m sphere, not the inverse Vincenty algorithm
used for route metrics. Grid previews format coordinates; they are not an
accuracy claim.

## Sun & moon

The map field-tools menu opens planning for its captured crosshair location.
Prev/Today/Next and a native date picker select the local Gregorian date. The
six sun rows show BMNT (nautical dawn, -12 degrees), civil dawn (-6), sunrise,
sunset, civil dusk and EENT. Local and Zulu columns are explicit; Local means
the device's zone captured when opened, not an inferred zone at the map point.
Moon phase, illumination and the first moonrise/set are shown. Missing crossings
remain ----, including polar day/night.

This is the same approximate offline model as Android. Moon times are about
five-minute estimates. Its 24-hour scan from local midnight is retained, so
clock-transition dates can include/miss an hour of event coverage; this is a
shared algorithm policy, not an iOS restriction. Critical times still require
field/reference checks.

`Resources/android-sunmoon.json` was generated with Kotlin 2.2.10 from the
unmodified Android source, covering Abu Dhabi, Kuwait, both New York DST
transition dates, polar summer/winter and both sides of the dateline. Tests
compare all six solar event times, local/Zulu formatting, phase/illumination and
moonrise/set arrays. To regenerate with a Kotlin CLI:

```sh
kotlinc /path/to/reference/coords/SunMoon.kt scripts/ExportAndroidSunMoon.kt -include-runtime -d /tmp/gridfix-sunmoon.jar
java -jar /tmp/gridfix-sunmoon.jar > GridFixCore/Tests/GridFixCoreTests/Resources/android-sunmoon.json
```

## Declination diagram

The map menu also opens the true/grid/magnetic north diagram. It exaggerates
small angles for readability, as Android does; printed values carry the actual
angles. Magnetic declination and grid convergence are east/west signed; G-M is
the absolute difference. A manual value remains primary while the bundled model
comparison is visible. Model expiry, missing magnetic reference and points
outside UTM coverage are explicit; unavailable arms and values are not replaced
with zero. The map-centre model is independent of the phone's live heading.

Practice course is also reachable from this menu, using the same setup/progress
screen as the existing course entry points. Planning tools do not start a guide,
recording or quiet-inside boundary session.

Validation covers known spherical projection destinations, dateline and north
reference behavior, invalid inputs/distance limits, Android astronomy fixtures,
manual/zero/missing/expired/polar declination, native date navigation, projected
waypoint save/edit/relaunch, original-coordinate preservation and day/night
screenshots. Physical field/compass/model comparisons remain release checks.

## Position local/Zulu solar rows

Android `4db6b21` adds four Position events: BMNT, sunrise (SR), sunset (SS) and
EENT, each showing `HHMML HHMMZ`. iOS now provides them beneath Lensatic/Dial and
in the scrollable Glance details, including compact landscape details. L uses
the phone's current time zone and its local date, not a guessed zone at the GPS
coordinate. The zone identifier is visible. Missing polar crossings show ----.
The separate planning tool retains its local/Zulu sun and moon events.

The readout caches by Android's hundredth-degree location bucket and ten-minute
time window, and refreshes when the phone zone changes. It uses the existing
solar model, independent of heading and movement source. Retained fixes still
carry the screen's existing stale-position warning. App tests compare the four
formatted rows against the existing Android-verified planner, including polar
absence and a different phone zone. Native real-CoreLocation checks pass on Lensatic, Dial and Glance, including
night Glance. All four rows were asserted and day/night screenshots were
inspected. The complete 159-test app integration suite passes. Physical
landscape, large-text and outdoor checks remain required.
