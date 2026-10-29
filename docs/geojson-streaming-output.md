# File-backed GeoJSON output — 29 October 2026

Production whole-library GeoJSON now writes a complete owned native file while
visiting validated local logs. It retains Android TabularFormats.GeoJsonFormat's
feature ordering, metadata, seven-decimal coordinate rounding, graphic geometry
and omission of tracks with fewer than two points. Tracks remain LineStrings;
altitude/time are outside this geographic format. Imports retain their limits.

The writer buffers approximately64KiB plus one fragment and the first point of
the current track. Waiting for its second point preserves the existing short
track rule without trusting summary counts. Complete track arrays and the whole
FeatureCollection are not materialized by production output. Waypoint snapshots
and individual graphic geometry keep their existing representation. Shared
feature helpers preserve eager compatibility metadata; compact output changes
whitespace, while parsed geographic contents are unchanged.

Every source, including an omitted single-point track, must finish strict
validation. Cancellation, sink errors or late checksum failure discard the
provisional native file. Approved-name copies and protected-size checks use the
same staging/ownership rules as GPX/KML. KMZ and backup writers retain their
existing limits; no claim that all export formats are streaming.

Validation:

- All592 core cases pass in /tmp/mgrsgps-geojson-stream-core-full.log. Five new
  cases cover parsed semantic equivalence with the eager exporter (names,
  metadata, shapes, negative rounding, empty/single-point tracks),300,003 exact
  output coordinates with bounded writes, sink failure, late checksum failure
  and cancellation. The long test validator may own a parsed output array;
  production generation does not.
- All368 native cases complete with four opt-in skips/no failures, and both
  real GeoJSON Files/map workflows pass in
  /tmp/mgrsgps-geojson-stream-native-ui.xcresult. New native cases validate a
  deferred300,003-point output and cleanup after a late checksum failure.
  Whole-library Files roundtrip passes55.002s; the existing paste/import/map/
  export/reopen workflow passes78.909s. Final preview and map captures inspected.
- Unsigned phone/watch/widget Release passes in
  /tmp/mgrsgps-geojson-stream-release.log. Xcode finalized after its600-second
  diagnostic collector timeout with exit0/TEST SUCCEEDED. Every local parent
  is reaped; fake location cleared and the single owned simulator shut down.
  This local follow-up is held while hosted113 validates a54ac75.
