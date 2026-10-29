# Dense waypoint captions

Waypoint captions use a compact collision layout without changing the native
marker set. Every coordinate, symbol, tap target, full accessibility name and
store record remains. There is no count cap, clustering or geometry simplification.
The navigation target gets first choice; other captions use stable saved ID order.
A one-point margin separates contrasting backings, and captions must fit inside
the map viewport. Existing marker selection still opens the full details card.

One noninteractive overlay paints captions above all marker symbols, so adjacent
icons cannot cover the contrasting text backing. It introduces no duplicate AX
elements or gesture interception. Spatial buckets avoid all-pairs caption checks.
A cancellable120ms delay coalesces camera/data changes; captions hide during motion
and return when it settles. A coalesced main-turn callback covers late UIKit view
realization. The render callback schedules only when dirty rather than repeatedly
enumerating a stable map.

Cold visual validation exposed an important SDK edge:5000marker views were attached
while public `visibleAnnotations` was nil. A scheduling-only follow-up did not fix
that. Layout now enumerates owned attached native views and clips their actual
screen-space label bounds instead of depending on that snapshot. A temporary
numerical DEBUG probe established the mismatch and was removed before the final
clean-source checks. The SDK's [6.31 implementation](https://raw.githubusercontent.com/maplibre/maplibre-native/ios-v6.31.0/platform/ios/src/MLNMapView.mm)
also documents occasional annotation-query misses. Native annotation accessibility
policy and SDK counts are unchanged by this caption fix.

## Validation on29October2026

Four layout cases pass: target priority independent of input order; stable ordinary
collisions across bucket boundaries; clipped/invalid caption exclusion; and5000
noncolliding captions without a count cap (about0.015s in the local run).
The existing full native dense-map workflow passes150.303s with its complete
marker-count, hide/show, camera, night and300s assertions intact. Initial day and
final night captures were exported and inspected; both show readable captions above
symbols. Evidence: `/tmp/mgrsgps-label-hosted-views-day.png`,
`/tmp/mgrsgps-label-hosted-views-night.png`, result
`/tmp/mgrsgps-label-hosted-views.xcresult`; parent97260exit0/reaped.

After the numeric probe was removed, all four layout cases pass again, and the
other two failed117library workflows pass44.573s/133.329s under the hosted300s
default/600s maximum execution allowances. Password rejection, durable restore,
full counts and night assertions remain. Parent73259exit0/reaped; result
`/tmp/mgrsgps-ci117-library-local.xcresult`.
Earlier99562completed its600s post-test diagnostic collection and exited0/reaped;
no test was cancelled or device removed while it was active. Initial test-only
Swift typechecker failure24678 was corrected by splitting an expression; every
later build/test parent has been reaped. Fake location was cleared and the
disposable926962A8clone shut down/deleted after the final test parent exited.
Final unsigned phone/watch/widget device Release passes (parent73132exit0/reaped,
log/tmp/mgrsgps-caption-release.log).

## Limits

Only waypoint-caption collisions are resolved. Symbols intentionally remain dense
in the extreme fixture. Basemap/grid, tactical/lane/remote labels and overlap with
surrounding app chrome have separate policies. Not every caption can be displayed
at once. Native day/night simulator proof does not establish physical rendering,
provider, memory/battery or broader map interaction performance. Fresh hosted
confirmation remains required. No TAK connection or infrastructure changes.
