# Original route legs on watch maps

Android release/1.1.0 `ControlMeasuresOverlay.kt` labels phone route segments
1, 2, 3… against the original route card. A bounded watch preview may combine
several such segments. watchOS previously suppressed numbers on simplified
routes; Wear reused the phone renderer and could misleadingly renumber them.

Both phone-to-watch map packets now optionally include `routeVertexIndices`:
the exact original ordinal for every retained vertex. The existing budgeted
simplifiers expose their retained indices instead of rediscovering them by
coordinate equality, which is ambiguous at repeated positions. Geometry,
tolerances, endpoint retention and per-platform packet/vertex budgets stay the
same. A segment between source vertices0 and125 reads `1–125`; the next segment
starting at125 begins at126. Ordinary single legs retain plain numbers.

Both renderers use these labels and both map-info views expose the named route's
original leg ranges. The normal phone renderer retains default sequential
numbering. Legacy simplified packets without ordinals suppress numbers; legacy
unsimplified packets retain ordinary numbering. Wrong endpoint/count/order/type
metadata is refused. The field is additive to version1; existing cache/transport
budgets still omit whole items if the complete encoded scene is too large.

## Validation

- All511 core tests pass in `/tmp/mgrsgps-watch-leg-core-final.log`, including
  source-index mapping at sharp bends,500 identical coordinates, round trip,
  old packet behavior and malformed index rejection.
- All345 native cases pass (four opt-in skips) in
  `/tmp/mgrsgps-watch-leg-native.xcresult`. Shared renderer checks distinguish
  original ranges from phone numbering and omitted labels in day/night.
- The actual iPhone route drawing, segment insertion, repeated point dragging,
  save, edit and relaunch workflow passes in
  `/tmp/mgrsgps-watch-leg-route-ui.xcresult`. Screenshot inspected; ordinary
  phone numbers and point editing remain present.
- Final phone/watch/widget unsigned device Release passes in
  `/tmp/mgrsgps-watch-leg-release.log`; eight Python harness checks pass.
- The paired40mm watch receives revision131 through real WatchConnectivity.
  `/tmp/mgrsgps-watch-leg-delivered.json` records the500-point synthetic phone
  route reduced to four vertices with indices0,125,250,499. The watch cache is
  inspected only after delivery; it is not injected. Actual day/night images
  show original range labels. Normal viewport clipping still applies to off-
  screen segments; the full range list remains in map info.
- Companion branch Android validation passes458 phone and42 Wear unit tests,
  phone/Wear Debug and Release builds and Wear Release lint. The source-budgeted
  standalone Wear fixture has the same four indices and ranges. Emulator day/
  night map captures and final map-info screenshot show `1–125,126–250,251–499`.
  This is emulator cache/rendering evidence, not a new paired Data Layer claim.

All local parents finish naturally. Prior watch preferences are restored after
stopping the apps, the Apple pair and Wear emulator are off, and fake feeds are
stopped/cleared. No TAK wire/infrastructure/credentials or quiet-inside behavior
changes. Physical watch readability, radio, background guidance and battery
checks remain open; this does not add watch route following or boundary haptics.
