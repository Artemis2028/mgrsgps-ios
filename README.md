# MGRS GPS — iOS

Current work compares against Android **release/1.1.0** (`482b417`). See
[the remaining parity inventory](docs/ios-parity-release-1.1.0.md). Earlier work targets Android **1.0.4**. See [the current parity roadmap](docs/ios-parity-1.0.4.md)
for implemented features, validation, and remaining work.

Native Swift and SwiftUI. The sibling of the Android app in
`Artemis2028/gridfix`, sharing its field math through fixtures rather than
an Android application runtime.

The native Apple Watch companion is in [Watch](Watch/README.md): Glance-style
large MGRS and waypoint pages, an interactive map with synced visible field
overlays, foreground watch location, fix quality, phone target/settings sync,
local 4/6/8/10-digit formatting and red night mode. See the
[shared watch feature contract](docs/watch-companion-parity.md) for platform differences.
Wear OS is a separate companion in the Android project. Both watch apps are
additional requested work; they do not replace the main iOS parity milestone.

## Getting it running

Build with Xcode 26 or newer for the native glass APIs. The app still deploys
to iOS 16 with material fallbacks; UI automation runs on iOS 17 or newer.

```bash
brew install xcodegen
xcodegen generate
open MGRSGPS.xcodeproj
```

The `.xcodeproj` is generated and git-ignored. Everything that would live in
it lives in `project.yml`, which is reviewable; a hand-edited pbxproj is not.

```bash
cd GridFixCore && swift test     # field math, WMM, coordinates, interchange, visibility
```

## Layout

```
GridFixCore/          the field math as a Swift package - MGRS, UTM, Vincenty,
                      the grid overlay geometry, WMM, folders, phonetic, and
                      every readout string
App/Sources/          the app: LocationService, DeclinationService, PositionView,
                      Theme, and Map/ - the thin MapLibre wiring
project.yml           the Xcode project, as YAML
scripts/              simulator boot + screenshot, used by CI and by hand
.github/workflows/    macOS runner: swift test -> build -> screenshots
```

## Interface and verification

Day mode uses native tab navigation and glass buttons on iOS 26+, with system
material fallbacks on earlier supported iOS versions. Waypoint cards remain
readable content surfaces. Night mode keeps opaque red-on-black field chrome.
Glance, Lensatic, and Dial remain available; this pass does not redesign the
compass artwork.

The four tabs are Position / Navigate / Map / Waypoints (tags 0/1/2/3).
`-startTab map` opens Map at tag **2**. Add/edit supports MGRS or WGS84 decimal
coordinates, and visible waypoints/folders appear on the map. Tap a marker to
navigate; use Locate or Show all visible data for explicit camera moves.

The map ruler menu measures anchor-to-crosshair distance and azimuth or a drawn
area/perimeter. Hold and drag a line to create a bend; drag numbered points to
adjust it. Area results can become a saved graphic. Measurements and tactical
graphics remain separate from quiet-inside monitoring. See
[map measurements](docs/map-measurement.md).

The Waypoints tab includes graphics and finished tracks, distance-bucket ordering,
mixed selection/visibility/deletion, and folder management. Track viewing can
temporarily show a hidden record without changing its visibility flag. See
[field library workflows](docs/field-library.md).

After `xcodegen generate`, run the scheme's UI tests with:

```bash
xcodebuild test -project MGRSGPS.xcodeproj -scheme MGRSGPS \
  -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO
```

Choose an installed simulator name. The UI tests use a separate Debug data
store and cover coordinate entry/editing/persistence, marker navigation, folder
visibility, map-centre creation, route cards/waypoint ownership, GPX tracks/routes,
offline map imports/layer selection, download estimates,
and restored data after relaunch. Screenshots are attached to the test results.

## The loop

Push to `main`. CI runs the field math, generates the project, builds for the
Simulator, boots a phone, drops it on 40R BN in Abu Dhabi, and posts
screenshots as artifacts - the position readout and the map with the MGRS grid
drawn on it.

MapLibre renders the same raster catalog as Android: Streets, Topographic,
Satellite, USGS Topo/Imagery, and Hillshade, subject to build-key availability.
USGS area downloads, raster MBTiles imports, offline-only mode, grid/shading
switches, elevation downloads, and contours are implemented. Global licensed
layers need an Esri build key in Release; Debug has Android's development
fallbacks. See [offline maps and configuration](docs/offline-maps.md).

The test step gates everything after it. A red field-math suite must not be
able to produce a build that looks shippable; the Android pipeline learned
that one the expensive way.

## What is deliberately different from Android

- **No satellite count.** Core Location exposes `horizontalAccuracy` and
  nothing about GNSS status. The fix grade and the trusted-precision digits
  come from accuracy alone and the satellite line is absent rather than faked.
- **Reduced accuracy is a hard stop.** If the user grants coarse location only,
  iOS hands back kilometre-scale positions. A grid built on that is a lie, so
  the screen says so instead of degrading quietly. This is the twin of
  Android's approximate-location gate.
- **Declination has no framework source.** Android gets the World Magnetic
  Model free from `android.hardware.GeomagneticField`; iOS has no equivalent
  and the model has to be carried in the app. See `docs/wmm-plan.md`.

## Conventions that are not up for debate

MGRS truncates and never rounds. A typed grid resolves to the cell centre;
calibration control points resolve to the SW corner. Distances are ellipsoidal.
Bearings come out in 0..<360. Night mode is red on black. No accounts, no
analytics, or field-data uploads. Online maps request provider tiles; Offline
only disables map network requests.

## Parity with Android

Field math is pinned to the shared golden fixture. Product surfaces are catching
up toward `gridfix` **1.0.4** — see `docs/ios-parity-1.0.4.md` for the current
checklist. `docs/parity-with-android.md` records the historical 0.9.32 baseline.
Waypoints, folders, route creation/cards, saved tracks/overlays, complete backup
v1, live track recording/recovery, and GPX waypoint/route/track import/export are
in. Recording uses dedicated background location and lock-compatible log files;
physical locked-screen verification remains before release. Map layers, USGS
area downloads, raster MBTiles and contours are also in. See
[track recording](docs/track-recording.md) and [offline maps](docs/offline-maps.md).
Editable [backstops and handrails](docs/backstops-handrails.md) define a closed
perimeter with bends: quiet inside, one alert on a confirmed exit, re-arm on
return. Dedicated background location and system notifications support locked
screen use within iOS limits. Physical-device validation remains before release.
Terrain field tools, practice courses, and KML/ATAK remain.


Automatic route following and haptic navigation now follow the release/1.1.0
guide policy and course checkpoint thresholds; see [navigation](docs/navigation-guide.md)
for foreground patterns, background milestones and the separation from boundaries.

Map graphics now include the complete 30-type Android control-measure set,
native drawing/editing with draggable segment handles, and waypoint-snapped
route drawing tied to route cards and automatic navigation. See
[graphics and route drawing](docs/tactical-graphics.md). Quiet-inside boundary
monitoring remains a separate mode.

Terrain tools now include map-centre elevation/slope estimates, point-to-point
line of sight, route elevation profiles, and day/night viewsheds using the same
cached/downloaded DEM data as contours. Missing data stays unknown. See
[terrain visibility](docs/terrain-visibility.md) for behavior and validation.
