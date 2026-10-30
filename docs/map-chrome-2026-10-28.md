# Compact map controls — 28 October 2026

The map opens with a compact full-grid disclosure card. Tapping it expands
map-centre latitude/longitude in the saved DD/DDM/DMS format, UTM, grid spacing,
terrain values, layer/overlay status and TAK access. The coordinates describe
the crosshair, not an invented device fix. The full accessibility-size details
sheet remains available.

A circular bottom-right plus opens an animated vertical options rail. The
plus rotates to a close symbol; Reduce Motion uses an opacity transition.
The rail uses 44-point actions with tighter spacing, a valid waypoint-pin
symbol, and enough portrait height for all default actions. Its buttons sit close to the right edge. Short landscape viewports scroll
inside a bounded rail. Hidden-tool preferences and active drawing/ruler/
recording finish controls retain their behavior. Add waypoint is an explicit
pin action inside the rail. Day native tabs now use the light color scheme,
fixing white selected symbols over pale map glass; the night palette remains.

Settings omit the position-face, orientation, grid-name and north-reference
explanations. Orientation state is exposed as the picker accessibility value.
Night mode has a plain toggle label. Redundant drawing/map-button instructions
are removed; errors, model provenance and permission limitations remain data.

## Android comparison

Local Android release/1.1.0 Coordinates.kt and SettingsRepository.kt match the
iOS Format functions: MGRS/USNG, UTM, and lat/lon DD/DDM/DMS (DDM default).
Claude confirmed the formats in FOR-IOS.md at22:14:27, correcting the branch
comparison method at22:32:58 while retaining the same coordinate conclusion.
Map-centre lat/lon/UTM are Rafael's requested addition: Android displays those
on Position, not its map HUD.

Both apps already supply automatic magnetic correction. Android uses its
GeomagneticField model unless manually overridden. iOS uses a manual override,
then a valid current-position true/magnetic CLHeading pair, then bundled WMM.
G–M is declination minus grid convergence. Missing iOS references remain absent;
removing explanatory text does not substitute zero. No magnetic math changed.

Claude also flagged unreleased1.2 missing-key restore behavior. A subsequent
source audit confirms iOS already implemented it in0d84a55, with passing core
and native restore tests; see settings-presence-audit.md. No duplicate port is
needed. This correction does not change the map UI milestone.

## Validation

- Final product source: /tmp/mgrsgps-map-options-final.xcresult passes five
  native FieldPlanning cases, compact portrait/landscape/day/night disclosure,
  hidden-tool persistence/reset/coordinate entry, recording stop reachability,
  and pinned/automatic orientation persistence.
- Active ruler/drawing case in that bundle fails because its assertion opens
  the rail, then its next tap hits a covered control. The test now explicitly
  closes options before operating the underlying finish/cancel controls.
  /tmp/mgrsgps-map-options-finish-controls.xcresult confirms the corrected
  active ruler/drawing workflow and all four largest-text map workflows pass.
  Nine distinct current-product UI cases pass across these two bundles; the
  initial failed case is retained as evidence.
- Source-compatible bundles: offline layers/day-night/native tab persistence,
  GPX route/track import/visibility/relaunch, and settings-write retry all pass.
- /tmp/mgrsgps-map-options-final-release.log passes unsigned device phone,
  watch and widget Release. Ten Python harness cases pass.
- Final portrait expanded/collapsed and night landscape screenshots inspected;
  all default portrait actions are fully visible and the waypoint icon renders.
  Initial failed bundles are retained, including accessibility element identity
  and a landscape test gesture that opened Control Center; the helper now
  drags within the rail rather than from its system edge.

## Hosted110 remains a separate failed gate

Run40729291858 on98c5c17 is terminal. Map47 and library59 UI cases pass.
Field122960900902 is cancelled: GitHub's annotation explicitly says the job
exceeded2h0m0s. Logs contain two Files/export failures, including launch-progress
failure and a five-minute test allowance, followed by a stuck main test process.
Dedicated background/fix/course checks were skipped, not passed. Artifacts for
all three jobs have verified SHA256 values; field artifact12842322586 has digest
1ecf2208e5b6871d945ec41d9db5290f6ecb46445cb47705082e03139e96ae43.
Field artifact diagnostic inspection is next. Current UI/storage source still
needs full hosted confirmation.
