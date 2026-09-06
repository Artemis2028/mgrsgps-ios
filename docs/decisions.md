# Decisions this repo is built on

*Short, and each one has a reason. If you are about to change any of these, the reason is the thing to argue with.*

## Native Swift and SwiftUI, not Compose Multiplatform

Chosen 4 Sep 2026 over CMP, which an earlier plan assumed.

- MapLibre Native has a first-class Swift API; CMP on iOS still has rough edges in text input, scroll feel and accessibility.
- The "one codebase" saving is smaller than it looks. The Android map overlays are osmdroid Canvas code and get rebuilt for MapLibre either way — that is where most of the work is, and it is not shared under either plan.
- The real objection to two implementations is drift, and drift is solvable by a fixture rather than by a shared runtime. See below.

## Drift is held by a fixture, not by shared code

The Android app and this one implement the same standards twice. That is exactly the thing that goes quietly wrong, and a wrong grid looks exactly like a right one. So both are pinned to one generated fixture:

```
kmp/gen_golden.py  (in the Android working tree)
   ├── golden.json        → GridFixCore/Tests/…  (here)
   └── GoldenVectors.kt   → app/src/test/…       (Android)
```

One generator, two emitted forms, identical numbers: 26 UTM points, 78 MGRS strings, 78 parse cases, 17 legs, 130 convergence samples, 180 graphic-geometry cases. If either platform computes a different grid or range for the same point, one of the two suites goes red.

Every MGRS string in the fixture is snapped to its own **cell centre**, so each has at least half a cell of clearance from every edge. The Android app parses through NGA's library while this one uses its own Snyder series, and those two are known to disagree by about a metre. At 4 and 6 digits the clearance is 500 m and 50 m, so exact string comparison is safe; 10 m cells are compared by position with a 3 m bound.

The vectors are checked against published values, not against ourselves: the Geoscience Australia Vincenty line to 1e-6 m, one degree of longitude at the equator to 111319.4908 m, one degree of latitude at the pole to 111693.86 m.

## Conventions that are not style choices

Changing one of these is a bug even when it looks like an improvement.

- **MGRS truncates, never rounds.** 12345 at 100 m precision is `123`. A grid that rounds up names a square you are not standing in.
- **A typed grid resolves to the cell centre.** A 6-digit grid means "somewhere in this 100 m square"; re-formatting a corner can fall into the neighbouring cell.
- **Except control points, which are corners.** Photo-map calibration ties to grid LINE intersections. Using the centre parse there bakes a half-cell error into the homography. That is what `parseCorner` exists for.
- **Distances are ellipsoidal (Vincenty).** A great-circle shortcut is 0.3–0.5 % off: nothing at the 25 m course ring, tens of metres on a long leg, and enough to make two phones in one patrol disagree.
- **A grid line belongs to its zone** and stops dead at the zone meridian. Letting one run on draws a line naming a grid square that does not exist — the most common bug in MGRS overlays.
- **Bearings come out in 0..<360**, never −180…180 and never 360.
- **Unit raw values match the Android settings store**, so a restored preference means the same thing.
- Night mode is red on black. No accounts, no analytics, nothing leaves the phone.

## Deliberate differences from Android

- **No satellite count.** Core Location exposes `horizontalAccuracy` and nothing about GNSS status. The fix grade and the trusted-precision digits come from accuracy alone and the satellite line is absent rather than faked.
- **Reduced accuracy is a hard stop.** Coarse-location permission yields kilometre-scale positions. A grid built on that is a lie, so the screen says so rather than degrading quietly.
- **Grid labels sit on the line**, not anchored to the screen edge. Android has to switch its labels off when the map rotates; `symbol-placement: line` is how a paper sheet does it and survives rotation for free.
- **`ImageQuad` returns nil instead of trapping** on a bad corner count — on Android that is a `require`, but here the same condition arrives from a bad import and the UI has to report it.

## The magnetic model

Android gets the World Magnetic Model free from `android.hardware.GeomagneticField`. **iOS has no equivalent in any framework.**

There is a free half worth taking: `CLHeading` gives `trueHeading - magneticHeading`, which *is* the declination — exact, never stale, and only ever true for here and now with the compass running. It cannot give the G-M angle for a map sheet, a bearing to a waypoint two valleys over, a route card built before you reach the ground, or a strip map.

So `DeclinationService` resolves in this order: **operator override → live heading → carried WMM → say it is unavailable.** Never a zero that reads as "no declination here".

`WMM.swift` implements the degree-12 model. Its Legendre recursion was checked against SciPy for every degree and order to 12 across colatitudes 0.5°–179.5° (8e-15 in value, 9e-13 in derivative), and its field summation is proved with dipoles whose answers are known in closed form. That dipole test earned its place: the first draft had the sign of the X component inverted, which is invisible in the dip angle and produces a declination 180° wrong everywhere.

**The coefficients are deliberately not committed** and must never be typed from memory. See `wmm-plan.md`.

## Process

- **The `.xcodeproj` is generated** from `project.yml` by XcodeGen and git-ignored. A hand-edited pbxproj is how iOS repos acquire merge conflicts nobody can read.
- **The workflow is parsed before it ships.** It once went out with a `python -c` block at column 0 inside a `run:` scalar, which terminates a YAML block scalar and made the whole file invalid. Anything with its own indentation rules stays out of YAML.
- **Every pipeline in CI needs `set -o pipefail`.** `swift test | tee` reported success while the compiler was failing, because a pipeline's exit status is the last command's. The Android pipeline shipped the same bug once. A green light that cannot go red is worse than no light.
- **`ci-status` carries every run's outcome and logs** to a branch, so a failure is diagnosable with a plain `git fetch` and no API token.
- **No secrets belong here.** A Simulator build is unsigned and the map style is keyless; the workflow's only permission is `contents: write` for the status branch.
- **This repo never pushes to `Artemis2028/gridfix`.**

## Still open

- The demo basemap is MapLibre's keyless world style. It proves the grid draws and is not the shipping basemap — self-hosted OSM vector tiles plus Copernicus-derived terrain replace it, which is also what makes worldwide offline download possible.
- Waypoints, folders, backup v1 read/write and GPX waypoint interchange landed as a first slice (see `parity-with-android.md`). Still open: a reference Android backup zip committed as a restore fixture, settings/graphics/tracks UI, and full additive restore of those sections.
- Terrain LOS and viewshed, KML/KMZ/ATAK CoT, track recording and course history remain Android-only and portable.
- Target tip for parity work: Android **0.9.32** (`v0.9.32-b68`).
