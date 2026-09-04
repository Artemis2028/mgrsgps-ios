# GridFixCore

The field math from MGRS GPS, in Swift. No UIKit, no MapKit, no third-party
dependencies — just Foundation, so it runs in a Simulator, on a device, in a
command-line tool, and in CI on a Linux runner.

```swift
import GridFixCore

MGRS.string(lat: 24.4539, lon: 54.3773, digits: 8)   // "40RBN34120700"
MGRS.parse("40R BN 3412 0700")                        // cell centre
MGRS.parseCorner("40R BN 3412 0700")                  // SW corner (control points)

Geodesy.navInfo(fromLat: a, fromLon: b, toLat: c, toLon: d)
// -> (distanceMeters, bearingTrue) on WGS84, Vincenty

Grid.chooseInterval(metersPerPoint: mpp, scale: UIScreen.main.scale)  // 1000
Grid.intervalLabel(1000)                                              // "1 km"

Format.latLon(lat: 24.4539, lon: 54.3773, format: .degreesMinutesSeconds)
Format.distance(meters: 1500, unit: .metric)                          // "1.50 km"
```

## What is in here

| File | What it holds |
|---|---|
| `UTM.swift` | Zone selection with the Norway and Svalbard exceptions, band letters, the Snyder forward and inverse series, grid convergence, 100 km square lettering |
| `MGRS.swift` | Forward at 4/6/8/10 digits, parse to cell centre, parse to SW corner, grid-line-number scaling |
| `Geodesy.swift` | Vincenty inverse (distance + initial bearing), great-circle fallback, two-ray resection |
| `GridGeometry.swift` | `GeoPoint`, `GridLine`, `GridLabel`, the grid interval rule and its readout label |
| `MapModels.swift` | `BaseLayerDescriptor`, `ImageQuad`, `OfflinePack`, `MapProjection` |
| `Folders.swift` | The folder naming rules, frozen since 0.9.9 |
| `Phonetic.swift` | NATO alphabet with military digits (Tree, Fower, Fife, Niner) |
| `Formatting.swift` | Every readout string: distance, bearing, lat/lon in three formats, UTM, DTG, altitude, accuracy, speed |

## Why it can be trusted

Two implementations of one standard is exactly the thing that drifts, and a
wrong grid looks exactly like a right one. So this package and the Android app
are both pinned to the same fixture:

```
kmp/gen_golden.py
   ├── golden.json          -> Tests/GridFixCoreTests (this package)
   └── GoldenVectors.kt     -> app/src/test (the Android app)
```

One generator, two forms, identical numbers. 26 UTM points, 78 MGRS strings,
78 parse cases, 17 legs and 130 convergence samples, spread over both
hemispheres, the Norway and Svalbard special zones, and the UAE test ground.
If either platform ever computes a different grid or a different range for the
same point, one of the two suites goes red.

The vectors themselves are checked against published values: the Vincenty line
matches the Geoscience Australia test case to 1e-6 m, one degree of longitude
at the equator to 111319.4908 m, and one degree of latitude at the pole to
111693.86 m.

Every MGRS string in the fixture is snapped to its own cell centre, so each one
has at least half a cell of clearance from every edge and a few metres of
disagreement between two correct projections can never flip a digit.

## Running the tests

```
swift test
```

72 assertions across two suites. `GoldenTests` is the cross-platform contract;
`FieldModelTests` covers the grid interval rule, folder naming, phonetic
spelling and every readout string.

## Rules this code encodes

These are not style choices — they are how a grid is read in the field, and
changing one is a bug even when it looks like an improvement.

- **MGRS truncates, never rounds.** 12345 at 100 m precision is `123`. A grid
  that rounds up names a square you are not standing in.
- **A typed grid resolves to the cell centre.** A 6-digit grid means "somewhere
  in this 100 m square"; re-formatting a corner point can fall into the
  neighbouring cell.
- **Except control points, which are corners.** Calibration ties to grid LINE
  intersections. Using the centre parse there bakes a half-cell error into the
  homography — that is what `parseCorner` exists for.
- **Distances are ellipsoidal.** A great-circle shortcut is 0.3 to 0.5 % off:
  nothing at the 25 m course ring, tens of metres on a long leg, and enough to
  make two phones in one patrol disagree.
- **Bearings come out in 0..<360**, never -180..180 and never 360.
- **Unit raw values match the Android settings store**, so a preference means
  the same thing on both phones.
