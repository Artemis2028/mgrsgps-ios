# Saved-track map preparation

Android reference: release/1.1.0, TracksOverlay.kt. Drawing uses
`max(1, points.count / 1500)` stride plus the final point. iOS now follows that
preview policy; stored logs, validation and individual GPX export stay complete.
This is per track, not a global budget. Dateline splitting can add edge vertices.

`FieldMapGeometry.prepareOverlay` validates every visible local log once on a
worker, builds track-only GeoJSON and accumulates full-log fit bounds. At most
six original extrema preserve latitude and both longitude intervals, including
unsampled excursions and graphic circle/sector extents. Tactical graphics remain
in their existing separate renderer.

`FieldOverlay` clears old geometry immediately on hide/delete/change and rejects
late results using cancellation and generation tokens. Discarded overlays cancel
their workers without retaining the map. Errors remain visible with explicit
retry; ordinary refreshes do not restart a failed load. Style replacement and
night-mode changes reuse prepared geometry and apply the latest palette.

Show All waits for pending geometry. A newer camera request or manual gesture
cancels that intent; a finished background load cannot move the camera back.
The archive must be ready before Show All is enabled. Loading/retry UI also
covers the field-library startup phase.

## Validation, 26 October

- 490 core tests pass: exact Android sampling/endpoints, unsampled bounds,
  dateline/ring extents, folder/item visibility and malformed-tail rejection.
- All 281 native cases pass, with four unstaged opt-in checks skipped. New cases
  cover replacement after a noncooperative old worker, failure/retry, cancellation
  and release, and a real 300,001-point log prepared off Main. The last case
  records 67 Main pulses with a maximum gap of 0.00724 seconds in this run;
  this simulator measurement is not a physical-device performance guarantee.
- All 12 selected UI workflows pass: offline layers, deferred Show All, newer
  Go To, manual pan, day/night lasso hide/delete/relaunch, GeoJSON routes/areas,
  and recording/discard/recovery. Real background journal growth is 3 to 6
  complete points in the same session before foreground activation.
- Unsigned generic-device Release build passes. Both xcodebuild parents exit 0
  naturally. Inspected screenshots show deferred fit, retained pan/Go To,
  night selection and readable recording values.

Evidence: `/tmp/gridfix-map-preparation-core-final.log`,
`/tmp/gridfix-map-worker-final.xcresult`,
`/tmp/gridfix-map-worker-final-background-check.log`,
`/tmp/gridfix-map-worker-final-images/manifest.json`, and
`/tmp/gridfix-map-worker-release.log`.

Remaining: full decoded log arrays still exist transiently on the worker,
multiple tracks can still yield large previews, and dense tactical rendering,
physical storage/lock/battery and device memory require separate validation.
Hosted run 40395046579 on d153810 remains in progress and precedes this change.
