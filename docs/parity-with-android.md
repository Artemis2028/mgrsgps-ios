# Parity with Android (target 0.9.32)

Target tip: `Artemis2028/gridfix` tag **v0.9.32-b68** (`40d5900`).
This file is the checklist of what this iOS tree matches, and what is still
Android-only. It is not a promise of feature parity.

## Matched (behaviour / fixture)

| Area | Notes |
| --- | --- |
| Golden fixture | `golden.json` ≡ `GoldenVectors.kt` (26 UTM / 78 MGRS fwd+parse / 17 legs / 130 convergence / 180 graphic-geometry). Tolerances identical. |
| Geodesy (Vincenty) | Same formula and fallbacks; bearings normalised 0..<360 on iOS at the `navInfo` seam. |
| UTM / MGRS / grid cells | Snyder series on iOS vs NGA on Android — metre-level drift held by cell-centre vectors (see `decisions.md`). |
| `Grid.lineValues` | Port of Android `gridLineValues` (0.9.20). `MgrsGrid.gridPass` uses it. |
| Grid interval chooser | Same 48 dp / metres-per-pixel rule. |
| Map portable models | `BaseLayerDescriptor`, `ImageQuad` (nil vs require), `OfflinePack`. |
| Phonetic | Identical ICAO + Tree/Fower/Fife/Niner tables. |
| Folders | Canonical / reserved / case-insensitive match frozen since 0.9.9. |
| Manual declination | Port of `ManualDeclination.kt`. |
| Sun / moon | Port of `SunMoon.kt` + ordering tests. |
| WMM | Degree-12 model; coefficients not committed (see `wmm-plan.md`). |
| Waypoints + folders store | Local JSON persistence; additive id-keyed merge. |
| Backup v1 | Zip + `gridfix-backup.json` read/write; version >1 refused; null declination preserved. Graphics/tracks/course encoded; restore slice applies waypoints/folders. |
| GPX baseline | Waypoint import/export with MilGPS `symbolcode` / `color`, elevation, time. |

## Intentional differences

- No satellite count (Core Location).
- Reduced-accuracy permission is a hard stop.
- Grid labels use MapLibre `symbol-placement: line`.
- Declination resolve order: override → live heading → WMM → unavailable (Android uses `GeomagneticField` as the model source).

## Still Android-only (not in this slice)

- Full graphics editor / map overlays for phase lines, areas, etc. (geometry helpers exist; product UI does not).
- Track recording service, course history UI, strip maps, QR, speech callout.
- Terrain / LOS / viewshed / elevation DEM cache.
- KML/KMZ/ATAK CoT interchange beyond GPX waypoints.
- Billing / paywall, crash-report prompt, in-app feedback.
- Landscape map tool rail polish (0.9.23–0.9.25), multi-select batch ops (0.9.27).
- Settings screen UI (codes and backup settings decode exist; no Settings face yet).
- Reference Android zip fixture committed for restore tests (still open — see `backup-format-v1.md`).

## How to re-check the fixture

Regenerate from the Android tree's `kmp/gen_golden.py` and replace both
`GoldenVectors.kt` and this repo's `golden.json`. Do not hand-edit either.
