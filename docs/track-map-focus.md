# Opening a long saved track on the map

Android reference: `release/1.1.0` (`482b417`),
`ui/GridFixApp.kt:onViewTrack`, `ui/screens/MapScreen.kt` and
`map/TracksOverlay.kt`. Viewing a saved track opens the map, unhides its parent
folder if necessary and temporarily shows that track without changing its saved
visibility flag. Stored points remain complete; drawing uses the existing
count/1500 stride plus the final point. iOS additionally fits the saved track
when opening it; this preserves that existing iOS convenience.

Previously, iOS decoded every TrackPoint and made another complete coordinate
array just to construct the camera request. Opening an arbitrarily long local
log could therefore duplicate a large amount of memory even though drawing
already used a bounded preview.

`FieldMapGeometry.trackFitPoints` now validates each row once and retains at
most six fit extrema. Normal and wrapped longitude extrema preserve the exact
existing antimeridian-aware bounds; short, single-point and empty logs remain
explicit. No stored points are dropped, no backup limits are imposed on local
logs, and the camera request contains no full decoded point array.

`TrackMapFocusAction` scans captured immutable bytes on a worker. The field
store captures metadata, bytes, identity and revision under its lock. A source
changed during scanning is recaptured; deletion fails rather than returning old
geometry. After revealing a hidden parent folder, the action checks the source
again before returning. Publication checks it once more. Cancellation propagates
to the scanner and cannot produce a late folder reveal or focus. Leaving the
library invalidates its pending focus token, and a newer camera request prevents
an older operation from replacing that intent.

The shared `FieldMutation` handler already used MainActor isolation. Its
completion now also belongs to the original presentation generation: confirmed
work still finishes, but closing and reopening the screen cannot make old work
dismiss or navigate the new presentation. Busy-state duplicate protection and
visible failures/retries remain.

Backtrack simplification still materializes a full coordinate array; startup
still maps/checks referenced logs. Orphan maintenance, dense-map aggregate
memory and physical device performance remain separate work. This change does
not establish physical battery, memory-pressure or locked-screen behavior.

## Validation checkpoint

Core geometry tests cover a 300,003-row dateline log, unsampled latitude extrema,
malformed coordinates/UTF-8 at the tail and empty/single-point logs. Native
cases exercise hidden-folder reveal without changing track visibility/target,
pre-cancellation and in-flight cancellation, deletion and same-ID replacement
during a suspended scan, deletion during folder publication and old
presentation completion after reopen. The long-log native benchmark checks main
thread progress and unchanged source bytes. The library UI flow also checks map
rendering in day/night mode and moving a hidden track afterward.

Final validation: 496 core tests pass. All 298 native cases pass (four unstaged
opt-in local cases skipped), plus three library UI workflows covering mixed
folder deletion, the hidden-track day/night map and move flow, and folder
rename/remove while keeping contents. The final general test parent exits 0
naturally. Earlier completed runs had only their owned diagnostic collection
shortened after all cases passed; their parents also finalized with exit 0.

The final 300,003-point native scan takes about 0.594 seconds, returns six
coordinates and permits 292 main-thread pulses. It retains the original bytes
and selected target. These are simulator measurements, not physical-device
performance guarantees.

Screenshot review additionally caught a compressed night-map grid caption and
layer name. The readout now takes its required vertical space and wraps both
labels. A fresh day/night hidden-track workflow and unsigned device Release
both pass after that layout correction, with natural parent exits 0. Final
screenshots were inspected and show the complete grid interval and layer name.

Evidence: `/tmp/mgrsgps-track-focus-core.log`,
`/tmp/mgrsgps-track-focus-verified-final.xcresult`,
`/tmp/mgrsgps-track-focus-layout-final.xcresult` and
`/tmp/mgrsgps-track-focus-layout-release.log`.
