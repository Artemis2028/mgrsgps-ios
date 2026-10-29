# Apple Watch terrain transfer and readout

The phone Terrain visibility panel now has an explicit **Send terrain at map centre**
action. It sends one existing z13 tile, not an area download. Export reads the same
pinned DEM priority as the phone renderer, retaining the selected area's attribution;
otherwise it reads the ordinary elevation disk cache with its provider attribution.
It never invokes fetch, creates a request, resamples an ancestor or downloads a missing
tile. Missing or incompatible cached data produces a retryable result.

## Transport and source ownership

The terrain manifest uses the cache contract in [watch-terrain-cache.md](watch-terrain-cache.md).
It travels separately from the vector map context, whose versions/budgets are unchanged.
A foreground reachable watch receives a message only if the complete binary property
list is at most48 KiB. The watch replies **after** source matching, full manifest/hash/
PNG validation and successful atomic cache installation. Only that positive reply
produces **Terrain saved on watch** on the phone. One preparation/message send is
active at a time; source/session generation changes invalidate old callbacks and
cancel pending preparation. Repeat manual sends get newer persisted revisions.

Larger tiles, an unreachable watch, or message transport failure use native queued
WatchConnectivity file transfer. At most four terrain files are outstanding. UUID-only
files live in a dedicated outbox until completion; activation removes orphan files.
Completion reports transport success (**Terrain sent. Check coverage on watch**),
not installation. Old file completions cannot replace the latest send's status.
Queue pressure, pairing/activation changes, missing cache, rejected installation and
send failures leave explicit retry states. This is an explicit copy, not an automatic
phone-cache deletion mirror.

The receiver derives expected identity from the paired SDK's latest valid map context
and persisted accepted map, applying the existing map revision rule. A terrain packet
cannot select an active source. Mismatched sources are rejected. The file callback
owns bounded payload bytes and installs them before the SDK removes the Inbox file.
The foreground message receiver enforces its independent48 KiB property-list bound.
Both use exactly the same cache validation. Unpair/re-pair/clock/fault/queue-pressure
and interruption rounds remain broader native and physical checks.

## Watch UI

Map information includes **Terrain · map centre**, its DEM elevation and attribution.
It samples the current watch map centre, independently of a phone GPS fix or watch
altimeter. It does not arm navigation or start another location owner. Reads run off
the main actor; cancellation prevents an old camera/source query replacing the current
readout. Missing tiles/no-data/outside coverage remain **Elevation unavailable here**.
The accepted companion source is required even after relaunch; cached data from another
source cannot become the active readout. A four-raster memory budget and disk limits
remain as documented. This adds a numeric readout, not a terrain basemap/contour/LOS
or viewshed overlay.

## Validation, 29 October 2026

- Seven native app terrain integration cases pass, including three new export cases:
  online cache misses/invalid data never fetch, raw PNG/provenance/revision preservation
  with watch cache reopening, and pinned DEM priority with its exact attribution.
- The opt-in paired UI case passes on final source in14.144s. A real native tap on the
  phone send control receives the actual watch's successful-installation reply; no
  transport/receiver/terrain success injection. The synthetic tile's native watch
  record byte count and SHA256 are independently checked. Eight final app/UI cases
  pass, zero failures/skips, Xcode exit0. The opt-in marker is removed afterward;
  unpaired ordinary CI skips this specific paired round.
- The40mm watch displays the expected synthetic100m DEM value and attribution in day
  mode. A cold night relaunch retains100m from its own cache. An earlier no-cache
  capture honestly shows unavailable. Native phone confirmation and both watch captures
  were inspected. No fake GPS or heading callbacks were added for this round.
- Final unsigned phone/watch/widget device Release passes. The636 core tests and68
  Wear unit/build/native cache evidence belong to the preceding unchanged foundation;
  Wear phone transfer/readout is still implementation work.
- Initial native file enqueue alone passed17.289s but produced zero received records;
  it is explicitly **not delivery proof**. [Apple documents that Simulator does not
  support transferFile](https://developer.apple.com/documentation/watchconnectivity/wcsession/transferfile%28_%3Ametadata%3A%29).
  The production foreground message path subsequently provides actual paired-simulator
  installation/readout proof. Physical queued-file delivery remains an open gate.
- All local test/build parents are reaped. Both owned simulators are off; original
  phone/watch preferences are restored byte-for-byte at freshly resolved containers;
  owned terrain cache/outbox fixtures are removed. No server, TAK connection, credentials,
  container or database changes.

Evidence: `/tmp/mgrsgps-terrain-transfer-active.json`, final `.xcresult`/summary, native
phone attachment, `/tmp/mgrsgps-terrain-watch-message.png` and
`/tmp/mgrsgps-terrain-watch-cold-night.png`. iOS pushes remain held while hosted116's
library job is active. Map116 passes; field116 failure triage continues independently.
Next: Wear companion transport/readout, physical Apple queued-file transfer, explicit
cache deletion/area semantics, offline raster packs and terrain analysis overlays.
Real enrolled iOS/Android TAK exchange/renewal still requires coordinated GO; server off.
