# Automatic saved-track cache upgrade — 29 October 2026

Normal app startup, explicit failed-read retry and the recorder's cold load all
request deferred field data. Receiptless v2 logs now undergo full streaming row,
checksum and source validation on that first load; only their immutable source
and computed summary remain in the loaded document. A matching current receipt
still skips point I/O entirely. Missing, corrupt or changed sources keep the
existing read failure behavior; they cannot become a writable empty library.

After successful publication, the shared loader starts one optional utility
worker to prepare the cache upgrade. V2 logs reuse the exact existing filenames
and bytes. A v1 ZIP is strictly decoded under the existing archive bounds, then
its complete records/logs are staged into the v2 store. The v1 recovery archive
is neither deleted nor rewritten. This removes the need for a user edit solely
to persist validated receipts. Legacy v1 still temporarily owns its decoded
archive bytes on the first launch; it is not a streaming ZIP reader.

The worker stages a complete atomic index and any new immutable logs, and
constructs deferred references before publication. The normal main publication
path checks the store identity/revision and disk provenance. A concurrent edit
wins; stale work is discarded, not rebased over the changed metadata. Ordinary
successful edits/restores already persist the upgraded cache. Cancelled or
failed maintenance leaves the successfully read library usable and the original
source intact, and can retry without a user edit. A subsequent healthy launch
neither rewrites the index nor reparses cached logs.

Prepared read snapshots remain read-only. Synchronous compatibility loads keep
the eager policy, and do not silently migrate. Archived preferences are not
applied by this storage upgrade, and no recording/navigation/TAK sharing session
is started. Existing map/read workers use their revision checks if the cache
publication supersedes a captured snapshot.

Validation:

- Eight new core cases cover receipt persistence/exact log reuse, no writes
  during preparation or a healthy second launch, v1 archive/record preservation,
  concurrent in-store edits, a competing store's publication, corrupt source
  refusal, failed upgrade/retry and cancellation/retry.
- The existing receiptless deferred-read test now asserts streaming validation
  with no owned log bytes and an unchanged index during preparation. Eager
  compatibility tests still prove strict fallback with no writes.
- All577 core cases pass: /tmp/mgrsgps-track-cache-core.log. The focused40-case
  cache/summary/load/startup suite also passes.
- All360 native cases complete with four opt-in skips and no failures. A new
  production-workspace case verifies deferred legacy loading, main-thread
  publication, unchanged recovery bytes, no application of archived night mode,
  an idle recorder and disabled TAK connection/sharing. Existing recovery,
  concurrent edit, backup/export, map/backtrack and cleanup cases pass.
- Current native/UI bundle: /tmp/mgrsgps-track-cache-final-native-ui.xcresult.
  Both UI workflows pass: day/night cold library loading and failed modal-read/
  explicit retry/recovered route-track visibility at night. All three resulting
  loaded/recovered library captures were inspected. Xcode then waited600s for
  simctl diagnostics, reported that collector timeout, finalized the result
  bundle and exited0 with TEST SUCCEEDED. The active run was never cancelled or
  duplicated; /tmp/mgrsgps-track-cache-xcodebuild-finalizing.txt records the
  diagnostic-collector wait. All parents are now reaped, the one owned simulator
  is off and fake location cleared. Ten Python harness cases pass in
  /tmp/mgrsgps-track-cache-harness.log.
- Unsigned phone/watch/widget Release passes:
  /tmp/mgrsgps-track-cache-release.log.
- The first native test draft was inserted into a helper class and failed to
  compile; it ran no cases. Moved to the actual test class before the passing
  full native run. The failed bundle is retained; no product assertion weakened.

Streaming export writers, cold-device pressure/battery measurements and physical
field/accessibility gates remain open. Hosted112 on2740063 predates both this
upgrade and cbdbb39's streaming consumers; its results cannot validate them.


The earlier hosted111 field artifact12854312737 was additionally downloaded,
SHA-256 verified as0e50f96a69ff4ae1eaebc75ac6255c2b10c762c55feb822d2c55a565831adae8
and extracted to /tmp/mgrsgps-ci111-field. Its main field UI and all five
dedicated fix/movement/boundary/navigation/practice logs end TEST SUCCEEDED.
This preserves the historical background evidence; it does not validate this
new local cache change. All three hosted111 shard artifacts are now verified.
