# MGRS GPS — iOS

Native Swift and SwiftUI. The sibling of the Android app in
`Artemis2028/gridfix`, sharing its field math through a fixture rather than
through a runtime, and **never** pushing to that repo.

## Getting it running

```bash
brew install xcodegen
xcodegen generate
open MGRSGPS.xcodeproj
```

The `.xcodeproj` is generated and git-ignored. Everything that would live in
it lives in `project.yml`, which is reviewable; a hand-edited pbxproj is not.

```bash
cd GridFixCore && swift test     # the field math, 72 assertions
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

## Field chrome and CI shots

The bottom nav is custom blackout chrome (`FieldTabBar`) — pure black, amber
selected, dim unselected — not the system `TabView` bar. Four tabs match Android
(Position / Navigate / Map / Waypoints; tags 0/1/2/3); CI `-startTab map` opens
Map at tag **2**.

`scripts/pick-simulator.sh` prefers exact **iPhone 16**, then **15**, then **14**
(so `iPhone 16e` cannot beat a real `iPhone 16`), then series/plain fallbacks so
image churn does not brick the pipeline. Override with `SIMULATOR_DEVICE_NAME`.

## The loop

Push to `main`. CI runs the field math, generates the project, builds for the
Simulator, boots a phone, drops it on 40R BN in Abu Dhabi, and posts
screenshots as artifacts - the position readout and the map with the MGRS grid
drawn on it.

The basemap is MapLibre's keyless demo style: enough to prove the grid draws,
and **not** the shipping basemap. Roadmap B replaces it with self-hosted
OpenStreetMap vector tiles and our own terrain, which is what makes worldwide
offline download possible. That is the "I can see it" step — no Mac required to
watch it work, same as the Android pipeline.

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
analytics, nothing leaves the phone.

## Parity with Android

Field math is pinned to the shared golden fixture. Product surfaces are catching
up toward `gridfix` **0.9.32** — see `docs/parity-with-android.md` for the
matched / unmatched checklist. Waypoints, folders, backup v1 and GPX import/export
are in; terrain, tracks UI and KML/ATAK are not.

