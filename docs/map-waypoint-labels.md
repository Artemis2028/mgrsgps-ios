# Dense waypoint captions

Waypoint captions now use a compact collision layout after the native camera and
annotation views settle. Only captions are suppressed: all native markers, exact
coordinates, symbol sizes, tap targets, full accessibility names and store records
remain. There is no marker/count cap and no clustering or geometry simplification.
The navigation target gets first choice; other captions use stable saved ID order.
A one-point margin separates contrasting caption backings. A caption must fit in
the map viewport. Selecting a marker still opens its existing details card.

Layout uses screen-space label bounds and spatial buckets rather than testing
every label against every other label. Captions draw in one noninteractive overlay above all marker symbols, so adjacent
icons cannot paint over the contrasting backing. Full accessibility remains on the
original marker views, without duplicate overlay elements. A cancellable120ms delay coalesces camera,
annotation realization and data changes; the renderer callback schedules only
when dirty and does not repeatedly enumerate a stable map. Captions hide during camera movement and return when it settles. This change is
limited to waypoint captions; tactical canvas, route, lane, grid and remote-layer
label policies are separate.

Four App unit cases pass: target priority independent of input order, stable
ordinary collision handling across bucket boundaries, invalid/clipped caption
exclusion, and5000noncolliding captions without a count cap (0.017s in this local
run). The final existing native dense-map test passes147.579s with unchanged full
marker-count, visibility, camera, night and300s assertions. The four layout cases
also pass on final source. Final parent99562 is still collecting simulator diagnostics (child42917,
`simctl diagnose --timeout=600`). It must finish and be reaped before final
artifact inspection, fake-location clear or clone removal. No parent exit0 or
completed cleanup is claimed yet. Earlier rendering runs pass143.527s/142.232s; the first capture
revealed icons painting over captions, corrected by the shared caption overlay.
The final run additionally covers hiding captions during camera movement.

Ownership: parent99562, log/tmp/mgrsgps-label-settled-final.log,
result/tmp/mgrsgps-label-settled-final.xcresult,
disposableiOS26.2device926962A8-9AAB-4FFF-AD25-EE9C8D2D17FA.
An initial test compilation exceeded Swift's typechecker budget for a new test
expression; it was split into explicit statements. Parent24678 exited65/reaped.
No product behavior was changed for that compiler correction.

Held locally while hosted117 library continues. No cancelling push, duplicate
hosted run, TAK connection, server/container/database change, merge or release.


Only waypoint-caption collisions are resolved. Symbol density, basemap/grid labels,
tactical annotations and overlap with surrounding app chrome are separate policies;
this is not a claim that every label can be displayed at once. The extremely dense
fixture intentionally retains all symbols even where they overlap.


The completed142.232s overlay run's capture
`/tmp/mgrsgps-label-overlay-night.png` was inspected: caption text and compact black
backings remain above neighboring icons. It precedes the two-line camera-motion
visibility follow-up. That final source has passed all five test bodies; its
parent's diagnostics completion and final capture are the remaining local steps.
