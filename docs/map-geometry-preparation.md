# Saved-track map preparation

Android reference: release/1.1.0, TracksOverlay.kt. Drawing uses
`max(1, points.count / 1500)` stride plus the final point. iOS now follows that
preview policy; stored logs, validation and individual GPX export stay complete.
This is per track, not a global budget. Dateline splitting can add edge vertices.

`FieldMapGeometry.prepareOverlay` counts actual nonempty rows, then validates
each point once on a worker while retaining only the sampled path. It builds
track-only GeoJSON and accumulates full-log fit bounds. At most
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

The later row-scan follow-up below removes the transient full coordinate array.
Multiple tracks can still yield large previews, and dense tactical rendering,
physical storage/lock/battery and device memory require separate validation.
Hosted run 40395046579 on d153810 remains in progress and precedes this change.


## Row-scanned preview, 27 October

Saved-track preparation no longer builds a full `[TrackPoint]` array. A first
row scan counts actual nonempty rows, independent of potentially wrong metadata;
a second scan parses and validates each coordinate/time/altitude once, retaining
only Android's sampled preview and the compact full-log extent. Both passes
share the existing row scanner and cancellation checks. Empty or single-point
logs still validate but do not produce a path or alter fit bounds.

This retains the complete log and rejects damaged tails/UTF-8; it does not use
metadata to skip validation or thin the stored/exported recording. Legacy blank
rows and newline forms do not change the preview stride. Source bytes, per-row
strings and all-track preview geometry still consume memory; this change removes
the full decoded coordinate array specifically. Focus/backtrack and other callers
which need every coordinate continue to use the complete local decoder.


Final checks: 492 core tests pass. All 283 native cases pass (four unstaged
opt-in skips), including the 300,001-point worker check with 88 Main pulses
and maximum observed gap 0.00972 seconds. All 12 map/lasso/interchange/recording
UI workflows pass; the host observes 4 to 6 complete points in the same journal
while on Home before foreground activation. Unsigned device Release passes.
Test/build parents exit 0 naturally; deferred-fit and recording screenshots
inspected. Evidence: `/tmp/gridfix-map-stream-core.log`,
`/tmp/gridfix-map-stream-final.xcresult`,
`/tmp/gridfix-map-stream-final-background-check.log`,
`/tmp/gridfix-map-stream-final-images/manifest.json`,
`/tmp/gridfix-map-stream-release.log`.

Hosted run 40395046579 precedes this change: map passes; field has three native
Files interaction failures (large GPX focus, cancellation, route PDF focus).
Library remains live; diagnostics are being retrieved. Local checks do not
establish a complete hosted pass.
