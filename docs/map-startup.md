# Offline-map startup preparation

Normal launches prepare the saved-map catalog, map preferences, bundled style,
HTTP cache and elevation-cache objects on the same shared startup worker as
waypoints. The main actor receives the complete map store before map rendering
or live app services are attached. MapLibre's global protocol installation and
all published UI state remain on the main actor.

The prepared pipeline already has the saved Offline only value. Its creation
does not fetch tiles. Imported MBTiles stay selected, with the saved grid,
terrain switches and camera settings. Existing tile budgets, provider catalog,
download behavior and archive formats are unchanged.

The handoff checks metadata for both `map-prefs-v1.json` and
`OfflineMaps/library.json`, including missing-file states. A newly created,
removed or replaced source triggers preparation again before publishing app
services. After three changing-source attempts, the loading card offers Try
again with the map-specific error. A malformed catalog retains the existing
read-only error behavior and original bytes; imports/downloads cannot replace
it with a writable empty catalog.

Existing direct MapLayerStore callers and synthetic UI fixture seeding retain
their synchronous setup API. The normal shipping path uses worker preparation.
Tile archive access during rendering, map preference writes and the other small
settings/course startup sources are separate work; this is not a claim that all
app I/O is asynchronous or every tile archive is opened before rendering.

## Validation

The first focused run passes 20 native integrations and both cold-library and
offline-map UI workflows: `/tmp/gridfix-map-startup-regression.xcresult`.
New native cases verify a real imported MBTiles tile, saved camera/layer/grid,
offline-only network refusal, unchanged preference/catalog bytes, changed or
missing sources, corrupt-catalog preservation and one service-graph publication
after a preference replacement. Final validation passes all 251 native cases (four unstaged opt-in checks
skipped) and seven UI workflows: cold day/night library/link retention, all
three map-layer workflows and all three terrain workflows. The offline-map
relaunch now explicitly uses the production worker-loading path. Evidence:
`/tmp/gridfix-map-startup-final.xcresult`. Inspected screenshots show the retained
offline map at night, day viewshed and readable night loading card. Final
phone/watch/widget Release passes:
`/tmp/gridfix-map-startup-final-release.log`.
