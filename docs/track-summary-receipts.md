# Reuse validated finished-track statistics

Android release/1.1.0 (`482b417`) TrackRepository.kt reads TrackInfo metadata
separately from `files/tracks/<id>.txt`; point logs are read when needed. iOS's
immutable v2 field store previously mapped, SHA-256 checked, parsed and summed
every saved log on every startup worker read. Metadata-only edits already reused
immutable point files, but a later launch repeated their geodesic calculation.

The local v2 index now optionally keeps point count and distance with each log
reference, plus a versioned corruption-check receipt bound to that log's SHA-256
and the exact statistics. New immutable logs get receipts after strict row
validation. At read time the regular-file checks and complete point-byte checksum
still run first. A matching receipt reuses statistics and overrides stale
manifest totals; it avoids another row decode/geodesic pass.

Missing, damaged, malformed or unknown-version receipts fall back to the strict
point parser. Successful legacy reads retain a fresh receipt in memory; it is
saved only with the next user-confirmed library edit. Startup itself remains
read-only. A changed/missing log still fails opening and prevents writes, keeping
both index and point files. Receipt checks are for corruption detection, not
authentication against someone rewriting the app's local index and its hashes.
The validation version must change when point parsing or summary math changes.

This is a backwards-compatible optional local-index addition. Earlier app
versions ignore the extra object; their next write may remove receipts, which
simply causes recomputation. External ZIP/protected backups and Android/TAK/watch
wire formats are unchanged. Map/track/export consumers keep exact point bytes.

## Validation

All538 Swift core cases pass in `/tmp/mgrsgps-log-summary-core.log`, including
six new receipt regressions and existing large-log, checksum-preservation,
exclusive publication, migration, stale-source and backup-limit cases.
The six cases cover:
- A20,000-point cached read invokes the point parser zero times, while removing
  its receipt invokes it once; exact metadata and bytes agree.
- Legacy reads do not rewrite their index, then a confirmed folder edit retains
  the same points and publishes the fresh receipt.
- A changed file checksum fails before cached statistics can be accepted;
  failed reads refuse edits and preserve both saved files.
- Five malformed/damaged/future receipt variants fall back to strict parsing.
- A receipt copied from a different point checksum is not reused.
- Verified statistics override stale count/distance in the manifest.

One synthetic warm Debug measurement reads the20,000-point fixture in about
0.00052s with its receipt versus0.06782s without. These are observations on this
Mac, not timing assertions, cold-disk measurements or a whole-app speed claim.
Deterministic parser-call checks prove the expensive extra pass is skipped.

All37 scoped native startup, maintenance, backtrack, staged interchange and
complete backup snapshot integration cases pass in
`/tmp/mgrsgps-log-summary-native.xcresult`. Unsigned device Release including
phone/watch/widget succeeds in `/tmp/mgrsgps-log-summary-release.log`; ten Python
harness cases pass. Current UI validation and hosted scope are recorded in the
parity inventory.

`/tmp/mgrsgps-log-summary-ui.xcresult` passes all three existing native UI
workflows: selected-track detail/menu GPX export through Files at night and
day/night unreadable-library refusal, repair, explicit retry and saved-route/
two-point-track access with relaunch. Night selected-track preview and recovered
library images inspected. All test/build parents finish naturally with0; the
single owned simulator and fake feed are off. Hosted110 runs the preceding
pushed98c5c17 source, so it cannot validate this local receipt change.

## Remaining startup work

The subsequent [on-demand loader](track-on-demand.md) now defers point-byte reads
for validated references at normal app startup/retry/recorder entry points.
The paragraph below describes this earlier receipt-only milestone. Legacy
receiptless/v1 fallback and physical/dense/streaming profiling remain open.

This does not yet provide on-demand point-file reads: startup still maps and
hashes every saved point file. A metadata-only listing and lazy per-track source
receipts need corresponding changes to map snapshots, track/detail reads,
backups, exports and staged mutations so missing or changed data cannot become
an empty track or be silently overwritten. Cold-device storage pressure, dense
rendering and battery/memory profiling remain open. No physical-device or whole-
library startup completion is claimed by the synthetic benchmark.


29 October follow-up: automatic receiptless/v1 cache upgrades and requested
map/fit/backtrack streaming are now implemented and validated locally; see
track-cache-upgrade.md and track-streaming.md. Earlier open-cache notes above
are historical. Streaming export writers and physical pressure/battery checks
remain open.
