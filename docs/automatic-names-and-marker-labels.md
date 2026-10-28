# Optional names and compact map labels — 28 October 2026

Rafael requested these naming conventions as a UX change beyond Android1.1.0.
An empty name now saves through the normal durable edit path:

| Item | Example |
| --- | --- |
| Waypoint | WP1, WP2 |
| Unit | EN-INF-PLT-1, FRN-INF-ABN-PLT-1, UNK-UNIT-1, NTRL-INF-1 |
| Route | RT1, RT2 |
| Generated route point | RT1WP1, RT1WP2 |
| Other graphic | RING1, SECTOR1, PHASE-LINE1 |

Unit names use the existing catalog function/echelon codes; absent echelons
are omitted. A typed name is retained. Automatic numbering advances beyond
matching saved names, including hidden items, and is allocated in the saved
snapshot instead of at editor presentation. Stale preparations must rebase
before publication, so two concurrent blank creations cannot both save WP1.
No new backup/TAK/watch fields or identifiers were added.

Both the map drawing editor and the library route editor accept blank names.
Route regeneration retains point IDs, selection and custom point renames. It
reuses an established RT reference and avoids another route's reference; a
custom-named route cannot consume the point prefix of a saved RT1 route that
has not generated its points yet. Existing authored names, including imported
Start/Finish names, are not rewritten. No new item defaults to Start.

Map marker text uses an11-point semibold font in a20-point-high backing whose
width follows the text, capped at150 points. The symbol remains44 points and
centered at the actual coordinate. A translucent dark backing plus a fine light
or red border keeps contrast without a fixed130-by26-point text bar. Full names
remain available in the waypoint details and accessibility label.

The TAK sheet now explicitly fills its navigation viewport and paints the safe
area/navigation background. Day/night unconfigured captures show no gray side
gutters. No server connection or credential change was needed to validate it.

## Validation

-557 core cases pass in /tmp/mgrsgps-automatic-names-core-final.log, including
  six naming cases for numbering, all affiliations/echelons, concurrent stale
  preparation, durable publication, route rename preservation and graphics.
-357 native cases pass with four opt-in skips/no failures in
  /tmp/mgrsgps-auto-names-native-final.xcresult, including mixed custom/numbered
  route reference reservation. An earlier356-case full native bundle also passes.
-Seven drawing/military UI cases pass in /tmp/mgrsgps-auto-names-final.xcresult:
  both custom and blank military names, echelon persistence, map/day/night render,
  route bends, snapping, fixed ring/sector placement and tactical boundaries.
-Three final UI cases pass in /tmp/mgrsgps-auto-route-tak-final.xcresult:
  blank and custom route creation/repeated point generation; blank WP1/WP2;
  compact map labels; and unconfigured TAK in day/night.
-Source-compatible GPX route/track map persistence and two route staging/failure
  workflows pass in /tmp/mgrsgps-auto-names-ui.xcresult. Its one failed snap case
  expected the old generic Route name; the final full drawing suite verifies RT1.
-Initial core failures likewise expected Android's old “Renamed WP…” convention.
  Updated assertions preserve ownership/selection checks and the new naming rule.
-Current unsigned phone/watch/widget Release passes in
  /tmp/mgrsgps-auto-names-release-last.log; ten Python harness cases pass.
-Representative small WP2 and full military name map labels plus day/night
  gutter-free TAK screenshots were inspected. Owned simulator/feed are shut
  down after reaping the final parents. Full hosted confirmation remains open.
