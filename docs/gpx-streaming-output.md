# File-backed GPX output — 29 October 2026

Production selected-track and whole-library GPX preparation writes a complete
owned temporary file off the main actor. Native Files receives an independent
copy with the user's approved filename. Cancelling, failing validation or
failing staging removes provisional output; original logs and saved indexes
remain intact. An export owns its source file until presentation finishes.

The GPX writer visits strict local track sources in order, validates their full
checksum/source stamp before success, and buffers approximately64KiB plus the
current XML fragment. It preserves point coordinates, elevation and time,
waypoint metadata and route-only GPX policy. It does not apply interchange
import byte/count ceilings to local logs. Android release/1.1.0's complete-log
GPX export was inspected read-only; long local tracks must remain complete.
An unusually large individual name/fragment still takes its own memory.

The eager compatibility API remains available and owns Data when explicitly
called. FileDocument's compatibility wrapper can likewise materialize Data;
the production native Files presenter uses the file-backed payload. Other
interchange/backup formats still use their existing bounded writers. Protected
exports retain the16MiB protection limit and reject oversized output before
materializing it, without silently exporting plaintext instead.

Validation so far:

- All582 core cases pass in /tmp/mgrsgps-gpx-stream-core-full.log. Five new
  streaming cases cover legacy byte equivalence, a300,003-point output parsed
  from its file, output/sink failures, late source failure and cancellation.
  The long output is31,200,544bytes across476 writes; largest write65,625bytes.
- All364 native cases complete with four opt-in skips and no failures in
  /tmp/mgrsgps-gpx-output-cache-final.xcresult. New native cases cover the
  complete long-library output, independent approved-name copy, late checksum
  failure, partial-file cleanup and cancellation. Source/index are retained.
- All five FieldExportWorkflowTests pass against the production file-backed
  writer: large library, icon-to-list, complete long filename, native cancellation
  and retry, plus selected-track details/menu export at night. Both dense-map
  checks and the protected selected-track Files workflow pass as well: eight UI
  cases total, zero failures,671.210s. Xcode finalized after its600-second
  diagnostic collector timeout, exited0 with TEST SUCCEEDED. Large-library,
  selected-track night, protected-track and dense-map captures were inspected.
  The extreme dense map retains overlapping labels; this change preserves
  every native marker rather than introducing a new decluttering policy.
- Unsigned phone/watch/widget Release passes in
  /tmp/mgrsgps-gpx-output-cache-final-release.log.
- Hosted112 predates this writer and cannot validate it. Its failed Files
  thumbnail activation is separately repaired and passes seven local workflows;
  full hosted confirmation remains open.

Cold-device memory/battery profiles, real providers and physical background
behavior remain field gates. No new server or wire behavior is introduced.
