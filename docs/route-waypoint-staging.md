# Staged route waypoint generation

Android WaypointRepository.replaceRouteWaypoints and its UI callback were
rechecked at 56acca2. Route ID and vertex index own a generated point; its name
does not. The selected duplicate is authoritative, otherwise the first stored
owner wins. Other incomplete/duplicate legacy owners become standalone points,
preserving UUIDs that a course may reference. Regeneration retains existing
owner IDs, creation dates, symbols, visibility and favourites while updating
route-derived name, coordinate and folder. Removed authoritative vertices clear
selection only when that selected UUID actually disappears.

## Preparation and publication

RouteEdit captures proposed new UUIDs and a creation time once per confirmed
generation. The app constructs it on a worker. Each immutable waypoint snapshot
then computes the complete owner replacement, encodes JSON and writes a staged
file on a worker. Store identity/revision checks and atomic publication remain
on Main. A stale snapshot is discarded and rebased with the same intent.
An invalid/oversized result or failed write leaves the published library intact.
The 10,000-waypoint cap includes retained legacy duplicates and is an app
format/implementation budget, not an iOS limit.

The application checks that the complete source route is still current before
preparation and immediately before publication. Changed/deleted sources stop
with a reopen instruction; cancellation cannot publish a late preparation.
The legacy synchronous API shares the same generation engine.

## UI and navigation startup

Generate waypoints and route-card vertex preparation now use the existing
asynchronous mutation owner. Progress, success and errors remain visible above
the scrollable route card. A long route cannot bury its failure below its legs.
The detail uses an inline native title so the route name stays visible with
the banner; day/night palettes remain native field styling.

Follow checks foreground/location permission before starting generation. It
shows preparation and a Cancel start control. The route screen redirects only
when navigation actually starts. Failed waypoint publication keeps the existing
target and never starts GPS/haptics. A cancelled permission request cannot
generate points or start after a later grant. A source/generation guard also
prevents late startup after cancellation during preparation. Existing route
following, lane guidance and the separate quiet-inside monitor are unchanged.

## Validation

442 core tests pass. New cases cover no early disk/memory publication, stale
preparation, failed write/retry, stable ownership, selected legacy duplicates,
empty regeneration, invalid coordinates and the complete library limit.
The 199-case native suite passes with two unstaged local TAK opt-in skips.
New application checks observe Main-thread publication, repeated generation,
changed-source rejection immediately before publication, cancellation, failed
navigation waypoint save/retry and cancellation before a permission grant.

The existing route creation/repeated-generation UI workflow passes. The first
new generation-error UI check revealed that the failure row was below the
visible route card. That mixed UI bundle is not counted as fully passing.
The corrected persistent-banner workflows pass: day generation failure, repair,
repeated generation and relaunch without duplicates; night follow failure
remaining on the route, repair/retry and successful navigation.

The real simulator-location NavigationWorkflow also passes automatic waypoint
advance, pause/resume, background completion and completed-state relaunch.
Evidence: `/tmp/gridfix-route-staging-core-verified.log`, native suite in
`/tmp/gridfix-route-staging-native.xcresult`, corrected UI bundles
`/tmp/gridfix-route-staging-ui-final.xcresult` and
`/tmp/gridfix-route-staging-rendered.xcresult`, and real-GPS result
`/tmp/gridfix-route-staging-live.xcresult`.

## Remaining work

Navigation target selection still uses a synchronous preference write after
route-card vertex preparation and at runtime checkpoint transitions. Navigation
progress/settings/session persistence, practice setup/history, startup reads
and the combined finished-track archive cap remain implementation work.
Physical locked-screen GPS/haptics, storage pressure and larger-library field
validation remain open. This milestone does not close practical parity.

The final inline-title day/night captures were inspected in
`/tmp/gridfix-route-staging-rendered-screens/`. Both corrected UI cases pass
in that final bundle. Final phone/watch/widget simulator Release, actionlint
and all six CI partition/location-feed script tests pass. The new UI class
is assigned exactly once to the field shard (42 total UI classes, including
the five dedicated feed scenarios).
