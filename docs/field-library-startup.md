# Deferred field-library startup

Normal launches first prepare waypoints before constructing the service graph; see [waypoint startup](waypoint-startup.md). Debug and Release then read the finished field library on one shared worker, then publish its complete snapshot on the main actor. The initial screen shows a readable loading card in day and red/black night modes. Actions stay disabled until the read finishes. UI fixture seeding remains synchronous setup; a dedicated cold relaunch exercises the production deferred path with a deterministic Debug-only loading gate. Shipping builds have no gate button.

Concurrent callers share the same load. Cancelling a view does not cancel another client or discard a completed read. A stale snapshot cannot replace edits or publish into another store. Existing v2 corruption does not fall back to an old legacy ZIP, and read failures remain read-only: edits, track points, restore and backup refuse an unreadied/damaged library. Legacy bytes are read unchanged until an explicit later mutation migrates them.

Navigation keeps its saved route paused without starting GPS or cues before readiness. Practice preserves its saved run/target and ignores scoring fixes until readiness. Finishing a recovered recording waits for the same load before installing its track and acknowledging the journal. The phone bridge waits before publishing local map/guide/TAK context.

TAK folder sharing distinguishes unknown saved data from deletion. Unreadied/corrupt graphics preserve their previously advertised UIDs while known hidden waypoints still withdraw. A bad waypoint source likewise preserves its own prefix. Explicitly unsharing every folder remains authoritative, including offline withdrawal remembered across sessions. A visible message explains queued updates. No CoT contract, trust behavior or sharing default changes.

## Validation, 26 October 2026

- Full core suite: 474 pass, including six deferred-read concurrency, cancellation, corruption, legacy and stale-publication cases.
- Native suite: 239 executed, two opt-in live-server tests skipped, no failures. Includes paused route, practice score/target, recording recovery/journal and TAK prefix/full-unshare regressions.
- Cold relaunch retains routes/tracks and readable loading in day/night; protected backup restore passes. Evidence: `/tmp/gridfix-field-startup-all-native-ui.xcresult`. All tests completed successfully; only its supplementary simulator-diagnostics child was terminated after completion to avoid the ten-minute diagnostics stall.
- Actual background-location recording/save/map and large GPX native Files reopen pass: `/tmp/gridfix-field-startup-recording-files.xcresult`. Files helper acknowledges picker dismissal before retrying an ignored thumbnail tap.
- Phone/watch/widget Release build passes: `/tmp/gridfix-field-startup-release.log`.

The read still validates every finished log on its worker. This is not lazy metadata-only startup. Per-log limits, settings/course startup reads, guarded orphan maintenance, damaged-course recovery IO, physical storage pressure and full hosted CI remain open. Waypoint startup is now deferred before service construction. Enrolled real Android/iOS simulator exchange and sustained delivery subsequently passed; physical validation remains separate.

Saved-map preparation now also runs before the service graph; see [map startup](map-startup.md).
