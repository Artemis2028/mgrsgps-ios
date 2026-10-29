# File-backed KML output — 29 October 2026

Whole-library KML preparation now visits verified deferred local track sources
and writes an owned file off the main actor, using the same native Files staging
and lifetime rules as GPX. Complete local tracks are not clipped to interchange
import ceilings. Other formats, including KMZ and GeoJSON, keep their existing
writers and limits.

The writer retains the existing KML bytes: first-occurrence folder order,
escaped names, point placemarks, tactical graphic prefixes/geometry, closed
polygon rings and track LineStrings (including empty/single-point tracks).
Coordinates stay longitude,latitude,0 as in Android release/1.1.0's
InterchangeFiles.buildKml. Track elevation/time remain outside this KML format.
Strict full-source validation must succeed before output can be presented;
late checksum failures and cancellation discard provisional files.

Output uses approximately64KiB plus the current fragment, without a complete
track point array or coordinate string. Waypoints and tactical graphics retain
their existing in-memory snapshots/geometry; this does not claim every input
is constant-memory. The eager compatibility API still explicitly owns Data.

Validation:

- All587 core cases pass in /tmp/mgrsgps-kml-stream-core-full.log. Five new
  cases prove legacy byte equivalence across folder/shape/track variants,
 300,003 exact coordinates parsed from a file with bounded writes, sink failure,
  late source failure and mid-write cancellation.
- All24 selected native cases pass in
  /tmp/mgrsgps-kml-stream-native-ui-first.xcresult, including a real deferred
 300,003-point KML export, correct file-backed native content type and late
  checksum cleanup with unchanged source/index.
- The first real Files save/reopen reaches the correct import preview, then
  fails its new count assertion: it expected3 point/3 graphic records, but KML
  correctly converts the fixture checkpoint to a point placemark (4 point/2
  line records). Corrected to the established KML contract, keeping all six
  records and the separate track-as-line assertion. The failed bundle is
  retained; its600-second collector finalized with exit65/TEST FAILED.
- The corrected Files save/reopen passes in54.667s and the full366-case native
  suite completes with four opt-in skips/no failures in
  /tmp/mgrsgps-kml-stream-native-ui-final.xcresult. Parent exits0/TEST SUCCEEDED;
  the final KML preview screenshot was inspected. All six records remain.
- Unsigned phone/watch/widget Release passes in
  /tmp/mgrsgps-kml-stream-release.log. All local parents are reaped and the
  single owned simulator is shut down. Changes remain local while hosted113
  validates the previous a54ac75 head. No cancelling push or duplicate run.
