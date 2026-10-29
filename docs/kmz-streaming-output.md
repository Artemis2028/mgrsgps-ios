# Complete local-log KMZ output — 29 October 2026

Production whole-library KMZ exports now use an owned file payload. Track
visitors read complete validated saved logs; they do not allocate full track
arrays, a complete KML string or a complete archive in the presentation path.
The existing native Files presenter copies the completed file under the approved
name. Failure/cancellation removes provisional output before presentation.

The container retains the existing single doc.kml STORE member. A first strict
KML visit measures its size and incremental CRC, then a second strict visit
writes bounded chunks. CRC and length must match before the central directory
is written. This preserves the legacy header layout and byte-for-byte output
for equivalent small fixtures. Empty chunks do not reset the CRC. Producer,
sink and cancellation failures propagate. Two visits trade CPU/I/O for bounded
production output and upfront ZIP metadata; no track data is silently truncated.

This writer keeps the ZIP32 member/offset ceiling and throws a readable size
error before overflowing. It does not introduce ZIP64 output. The separate KMZ
import budgets and legacy eager KMZ.build helper retain their limits. Protected
export still checks its 16 MiB envelope limit before reading the completed file;
there is no plaintext fallback. Backup output streaming remains separate work.

Validation:

- Six new core cases cover exact legacy archive bytes/geometry, all 300,003
  coordinates through ZIP CRC validation and an independent XML counter,
  changed second-pass bytes, source/sink errors, empty members/chunks and
  cancellation after output begins. Largest long-source writes stay below
  65 KiB. The test materializes output for independent ZIP/XML verification;
  it does not claim constant-memory test instrumentation.
- All 603 shared-core cases pass. Full native suite: 370 cases complete with
  four opt-in skips and no failures, including file-backed 300,003-point KMZ
  and late-checksum cleanup without changing saved source/index bytes.
- Real native Files save/reopen passes 55.232s with the complete approved .kmz
  filename and all six records (four point placemarks/two lines). Export-name
  and preview captures inspected. The KMZ saved by Files is also read by
  desktop Java17 ZipInputStream and an independent XML reader: one STORE
  doc.kml, valid CRC, four points/two lines. This is container verification,
  not a new Android-app/paired-server interoperability claim.
- Unsigned phone/watch/widget device Release passes. Final Xcode parent exits
  0 / TEST SUCCEEDED. Every local parent is reaped, fake location cleared and
  the one owned simulator shut down.

Evidence: /tmp/mgrsgps-kmz-stream-core-full.log,
/tmp/mgrsgps-kmz-stream-native-ui.xcresult,
/tmp/mgrsgps-kmz-stream-release.log,
/tmp/mgrsgps-kmz-stream-java-check.log and
/tmp/mgrsgps-kmz-stream-images/. Intermediate compiler logs retain the Swift
nested nonescaping-callback error; a synchronous withoutActuallyEscaping scope
resolves it and checks sink lifetime at return. No callback is retained.

This change is held locally while hosted114 validates pushed 5f73683. Physical
memory/provider/cold-device checks, backup streaming and other recorded parity
gates remain open. No TAK server, credentials or infrastructure were changed.
