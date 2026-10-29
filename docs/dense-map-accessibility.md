# Dense map accessibility — 29 October 2026

Hosted111's5,000-waypoint/1,000-graphic workflow exceeded300s after opening Map;
each native accessibility query took about13s. A runtime sample during the same
unchanged local fixture showed the main thread inside accessibility enumeration
and MapLibre's repeated spatial query/sort. Evidence:
/tmp/mgrsgps-dense-map-main-sample.txt. The initial eager-to-lazy marker-container
scan optimization alone did NOT fix this; its repeat failed menu acknowledgment
in73.914s. The failed bundle is retained at
/tmp/mgrsgps-ci111-dense-lane-files-262.xcresult.

The pinned SDK is MapLibre6.31.0. Its
[per-index accessor](https://github.com/maplibre/maplibre-native/blob/ios-v6.31.0/platform/ios/src/MLNMapView.mm#L3350)
queries and sorts visible annotations for every requested index. FieldMapView
uses the public visibleAnnotations/view-for-annotation APIs to calculate the
nearest-first native view order once for a camera/data snapshot. It never caps
markers, changes their rendering, substitutes a summary, or hides AX nodes.
The native SDK still supplies the element count, location, compass, basemap
features and attribution. Sparse/non-view annotation maps, callouts and tracking
modes fall through to the SDK. No private selector or SDK patch is used.

Cache identity includes camera, viewport, content inset, location visibility and
annotation revision and native user-location view identity. Public add/remove
paths, waypoint/theme sync and style loading invalidate it. A GPS coordinate
update does not change fixed-marker ordering when tracking is off; appearance
or replacement of the native location view still changes the cache identity.
Reverse element lookup uses identity indices.
The ordinary native marker views keep their labels, traits, IDs and actions.
Map update container lookup also stops at the first hosted annotation instead
of requesting every view just to find that first container.

Android's pinned MapScreen draws viewport-visible waypoint controls over its
map instead of using this native iOS annotation accessor. No Android geometry,
visibility, marker or wire behavior changes were needed. Exact rendering is
retained on iOS; the dense screenshot still has heavily overlapping labels at
this extreme density. Readable individual labels require zooming. Physical
VoiceOver/touch, memory/battery and a future explicit decluttering policy remain
separate review items, not proven by this simulator fix.

Validation:

- The unchanged large-library search/grid/selection/night workflow passes in
 46.833s after the first cache repair, then45.558s on the final source.
- All six cases pass in /tmp/mgrsgps-dense-map-final2-262.xcresult: the four
 existing large-library workflows, a new native marker-count/camera/night check,
 and ordinary marker selection/navigation after a layer change.
- The new check compares actual accessible waypoint counts against the SDK's
 reported visible annotation count (initially924), pans far enough to remove
 all markers, returns and changes night mode. No fixture shrink or time-limit
 increase. Its first draft expected the wrong SDK wording, corrected to the
 actual annotation(s) string without weakening count equality.
- The final extension passes in /tmp/mgrsgps-dense-map-visibility-final2-262.xcresult: real library hide/show removes/restores the original marker, with exact native-count equality after each change and camera/night checks retained. Its first attempt passed a newline into a strict replacement helper; submission is now separate. A subsequent run never launched because the simulator denied preflight as Busy; after reaping the terminal parent and restarting the single owned simulator, the same test passes. A prepared fake location was supplied to the native SDK too; no app decisions/annotation lists were injected. The simulator/fake location are shut down/cleared afterward.
- Current unsigned phone/watch/widget device Release passes in
 /tmp/mgrsgps-map-accessibility-release.log; ten Python harness cases pass in
 /tmp/mgrsgps-map-accessibility-harness.log. Core math is unchanged.
- Dense/night and largest-text waypoint captures were inspected. Full hosted
 confirmation of the final source remains open.

Hosted112 follow-up: the original dense workflow again failed map-options
acknowledgment under hosted load. This remains an open hosted gate, not a
confirmed complete fix. MapLibre6.31.0's public view-for-annotation method
returns its user-location view, so native prefix detection can use that identity
without asking the expensive per-index accessor. The GPS callback no longer
discards ordering that depends only on a stationary camera and fixed markers.
The attached-view guard and every native element remain intact.

The preceding source already passed the unchanged dense workflow locally with
the CI3-second moving GPS route in
/tmp/mgrsgps-gpx-native-dense-live-baseline.xcresult (46.959s); continuous GPS
is therefore a performance hypothesis, not a proven deterministic local cause.
Fresh exact-count/hide/show/camera/night passes in171.637s and the unchanged
original dense workflow passes in45.805s on the refined cache in
/tmp/mgrsgps-gpx-output-cache-final.xcresult, under the same3-second fake GPS
route. All eight selected UI cases pass. Xcode finalized after its600-second
diagnostic collector timeout, exited0 with TEST SUCCEEDED. The dense/night
capture was inspected: all markers are retained, with the previously recorded
extreme-density label overlap. Full hosted confirmation stays open.
Unsigned phone/watch/widget Release passes in
/tmp/mgrsgps-gpx-output-cache-final-release.log.
