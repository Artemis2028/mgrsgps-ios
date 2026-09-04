# Magnetic declination on iOS

*The one piece of the Android app that has no iOS equivalent, and the plan for it.*

## The problem in one line

Android hands us the World Magnetic Model for free — `android.hardware.GeomagneticField(lat, lon, alt, time).declination`, one line, always current because the OS ships the model. **iOS has no equivalent.** Nothing in Core Location, Core Motion or MapKit exposes a magnetic model you can query at an arbitrary point and time.

This matters more here than in most apps. Declination is not decoration in a land-nav tool: it is the number that turns a grid azimuth into something you can set on a lensatic compass. Getting it wrong by two degrees puts you 35 m off at a kilometre.

## There is a free half, and it is worth taking

`CLHeading` gives both `trueHeading` and `magneticHeading`. Their difference **is** the declination, computed by iOS from its own internal model:

```swift
let declination = heading.trueHeading - heading.magneticHeading   // east positive
```

Both must be valid — `trueHeading` is negative when Core Location has no location fix, and `magneticHeading` is meaningless while `headingAccuracy` is negative. When both are good this is exact, free, and always current. Take it.

What it cannot do is everything the app uses declination for *other* than "here, now, with the compass running":

| Use | Heading-derived? | Why not |
|---|---|---|
| Compass rose, magnetic north pointer | **Yes** | The compass is running and you are standing there |
| G-M angle for the map sheet you are holding | No | Wanted before the compass has settled, and for the sheet's centre, not your feet |
| Bearing to a waypoint two valleys over | No | The declination that matters is at the *waypoint*, and it can differ by a degree |
| Route card built at the FOB for tomorrow's ground | No | No fix there, no heading, possibly no signal |
| Strip map PDF for a route across a region | No | Every leg wants its own value |
| Any of it with the phone flat in a pouch | No | No heading updates at all |

So the answer is both: derive when a heading is live, fall back to a carried model otherwise, and let the operator override either from Settings — the Android app already has that override, and an operator handed a G-M angle in the OPORD trusts the order over any model.

## The carried model

The World Magnetic Model is a degree-and-order-12 spherical harmonic expansion: 90 Gauss coefficient pairs plus 90 secular-variation pairs, public domain, jointly produced by NOAA/NCEI and the British Geological Survey. WMM2025 is valid 2025.0 through 2030.0. The coefficient file is about 4 KB of plain text.

### What is already built and proven

`GridFixCore/Sources/GridFixCore/WMM.swift` is complete and its *engine* is verified:

- **The Schmidt semi-normalised Legendre recursion** was checked against SciPy for every degree and order up to 12 across colatitudes 0.5° to 179.5°: worst error 8e-15 in value and 9e-13 in the θ-derivative. `WMMTests` re-checks it two ways — against the degree-1 and degree-2 closed forms, and against numerical differentiation of its own values.
- **The field summation** is proved with dipoles, whose answers are known exactly. An axial dipole must give declination zero at every point on earth; a dipole tilted by `g₁¹` must give a declination field antisymmetric in longitude. Both hold to 1e-9.

That dipole test earned its place immediately: the first draft had the sign of the X (north) component inverted. It is invisible in the dip angle, which only reads Z, and it produces a declination that is 180° wrong **everywhere** — the kind of failure that looks like a working app until someone walks the wrong way. The axial-dipole test caught it in seconds.

- **The COF parser** handles NOAA's format and refuses an incomplete or malformed file rather than silently returning a partial model.

### What is outstanding

**The coefficients.** They are not in the repository and they must never be typed from memory or from a model's recollection — a plausible-looking wrong coefficient is exactly the failure mode this whole session has been avoiding. One manual step:

1. Download `WMM.COF` from NOAA/NCEI: <https://www.ncei.noaa.gov/products/world-magnetic-model>
   (the "WMM Coefficient File" download; BGS mirrors it at <https://geomag.bgs.ac.uk/>)
2. Also download `WMM2025_TestValues.txt` from the same page.
3. Drop `WMM.COF` into `GridFixCore/Sources/GridFixCore/Resources/`, and the test values into `GridFixCore/Tests/GridFixCoreTests/Resources/`.
4. `swift test` — `testTheRealModelIfItIsBundled` stops skipping, and the validation job below starts running.

Licence position: the WMM is a US Government / NERC joint product, in the public domain, explicitly free to redistribute in software. Attribution in the About screen is courtesy, not obligation, and we should do it anyway.

### The validation gate

NOAA publishes a test-value file: about 1,300 rows of `date height lat lon` with the expected declination, inclination, and all field components. That file is the only thing that can validate the coefficients, and it should be a hard CI gate, not a manual check:

```
- name: Magnetic model against NOAA's own test values
  run: swift test --filter WMMValidationTests
```

Tolerance: match NOAA to **0.01°** in declination. Their own tables are printed to two decimals, and a correct implementation lands well inside that. Anything looser is not a test.

Until that file is committed the suite skips those cases and says so. A magnetic model that quietly returns *something* is worse than one that admits it has nothing.

## Expiry — the part most implementations get wrong

WMM2025 is invalid after 2030-01-01. Past its epoch the secular variation extrapolation drifts, and by a few years out the error exceeds the model's own 1° accuracy claim. Android does not have this problem because the OS updates the model; a carried model does.

The app must therefore:

- know its own validity window — `WMM.validUntil` and `isValid(at:)` are already there;
- show the operator the declination source when it is not the live compass, and say plainly when the carried model is out of date rather than quoting a stale number;
- prefer the heading-derived value whenever one is live, since that one never expires.

Refreshing is a five-year chore: download the new COF, drop it in, run the suite. Put a reminder on the calendar for late 2029.

## Order of resolution

The app should take the first of these that is available, and always tell the operator which one it used:

1. **Operator override** from Settings — a G-M angle from the map sheet or the order beats every model. Already the rule on Android.
2. **Heading-derived** — `trueHeading - magneticHeading`, when both are valid and `headingAccuracy` is non-negative. Only for the current position.
3. **The carried WMM**, when it is bundled and unexpired.
4. **Nothing** — show grid and true north only, and say the magnetic reference is unavailable. Do not show a zero and let it read as "no declination here".

## Alternatives considered

- **IGRF instead of WMM.** Same mathematics, degree 13, also public domain, five-year epochs. No advantage for a navigation app; WMM is what the US military references and what Android reports. The engine handles either if the parser is pointed at an IGRF coefficient file.
- **Compute it server-side.** Rejected outright: the app is offline-first, and the whole point is working in a valley with no signal.
- **Ship only the heading-derived path.** Cheapest, and wrong. It would silently drop route cards, strip maps and remote-waypoint bearings to true north, which is a quiet, unlabelled loss of a military convention.
- **Wait for Apple.** There has been no magnetic-model API for fifteen years. Not a plan.

## Effort

The engine is written and its mathematics is proved. What remains is: fetch two files, wire the resolution order into a `DeclinationService`, add the validation test, and put the source label in the readout. Call it **one working session** once the coefficient file is in hand — and it cannot start until someone downloads it, which is the one thing this sandbox cannot do.
