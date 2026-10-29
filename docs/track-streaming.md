# Stream requested saved tracks — 29 October 2026

Phone map preparation, Show on map camera fitting and Backtrack now visit an
immutable local log in 64 KiB chunks instead of first owning its complete Data.
This extends the existing deferred metadata load; it does not change the track
format, point log, archive contract or saved summary receipts.

The reader validates UTF-8 and every point row, preserving the eager parser's
ASCII and Unicode newline variants, blank rows and final unterminated row. It
keeps one chunk plus the unfinished row, not the whole log. An unusually long
single row can still require that row's memory; there is no newly imposed line
length or point-count limit. Cancellation is checked between chunks and during
scanning. SHA-256 is updated on exact original bytes, with source identity/size/
modification checks before and after reading and an exact total byte count.
Nothing derived from provisional visitor callbacks is published until the full
visit returns successfully. Failure/cancellation revokes cleanup authority.

Map previews make two verified visits to deferred files: count actual rows,
then validate/sample using Android TracksOverlay's max(1,count/1500) stride plus
the last point. Every coordinate contributes to the exact fit extent. Hidden
tracks still skip I/O, and corrupt unsampled tails cannot produce a partial
map. Eager imported bytes retain their existing path. Camera fitting needs one
verified pass and at most six output coordinates, retaining dateline bounds.
Backtrack retains all source coordinates for Android's exact largest-deviation
simplifier; it avoids the full raw-byte copy, not the required random-access
coordinate array. Output geometry, tolerance, vertex budget and reverse order
are unchanged. Existing revision/generation/cancellation/publication checks and
selected navigation targets are preserved.

Compared read-only with Android TrackRepository.readPoints and
TracksOverlay.drawTrack in the local gridfix checkout: Android still reads its
selected log eagerly and draws the same preview stride. This iOS memory change
does not narrow Android's supported route or point behavior.

Compatibility and remaining work:

- Eager Data compatibility APIs and test-injected transformations remain valid.
- Production GPX output now uses a file-backed streaming writer; see
  gpx-streaming-output.md for validation in progress. Other interchange/backup
  writers and bounded watch snapshots retain their existing limits.
- Automatic receiptless/v1 cache upgrade is now implemented (track-cache-upgrade.md).
  Cold-device memory/battery profiling,
  physical field checks and wider accessibility remain open.
- Current hosted112 runs2740063, preceding this change. It cannot validate the
  streaming reader. Local validation is recorded below before committing.

Validation:

- Eight new core cases cover every chunk size1...71 across Unicode separators,
  split UTF-8, a200,000-space row, malformed EOF, final checksum failure, source
  replacement during visitation, visitor failure/retry, cancellation, exact
  deferred/eager long-map JSON/stride/dateline extrema with stale metadata,
  and exact backtrack simplification plus a malformed unsampled tail.
- All569 core cases pass: /tmp/mgrsgps-stream-track-final-core.log.
- Focused native map-fit and backtrack cases include real deferred-source stores
  without materializing trackFiles, preservation of navigation selection and
  durable route publication. All21 focused native cases and three UI workflows pass in
  /tmp/mgrsgps-stream-track-final-native-ui.xcresult. The UI journeys cover
  hidden-track fitting/moving, backtrack route publication and imported route/
  track map/relaunch persistence. Day/night map captures and the backtrack
  route/map were inspected; original overlays and reverse route are present.
- Unsigned phone/watch/widget device Release passes:
  /tmp/mgrsgps-stream-track-release.log. All local parents are reaped; the
  one owned simulator is off and its fake location cleared. No server contact.
- The first focused test compile missed a try in an assertion; it ran no cases.
  The corrected34-case run and final569-case run pass. No fixture/timeout shrink.
