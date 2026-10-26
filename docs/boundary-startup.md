# Boundary library preparation before live services

Normal startup now prepares `boundaries-v1.json` on the shared worker before
constructing the live service graph. The worker decodes the saved perimeters,
checks unique IDs/counts and validates their geometry. The existing 2 MiB file
limit is checked against metadata before reading and against the bytes afterward.
Boundary count, vertex and geometry rules are unchanged.

Source metadata includes missing-file state. Creation, replacement or removal
invalidates the snapshot; shared startup retries before publishing services.
The monitor also refuses a prepared snapshot from another directory or one
whose source changed before installation. The main executor checks metadata
and installs validated values without rereading or revalidating the geometry.
Existing direct synchronous fixture/caller construction remains available.

Saved interrupted monitoring never arms itself: areas and the interrupted notice
return, but the location driver and alerts stay inactive until the user starts
monitoring with the app open. Malformed, oversized, duplicate-ID and invalid-
geometry files remain kept and read-only. The separate quiet-inside crossing
policy is unchanged; no heading/route guide behavior is added to this mode.

## Validation

- `/tmp/gridfix-boundary-startup-native-final.xcresult` passes all 268 native
  cases, with four unstaged opt-in local skips and no failures. Coverage includes
  worker restoration without GPS/alerts or source writes, invalid libraries,
  source creation/replacement/removal, wrong-directory refusal, damaged startup
  and replacement retry before one service graph is published.
- All three actual simulator boundary workflows pass in
  `/tmp/gridfix-boundary-startup-final.xcresult`: straight drawing/point movement/
  save, direct side long-press/drag, and real Core Location background exits.
  Both saved drawing and interrupted monitoring relaunch through the shared
  worker. Crossing and saved-library screenshots were inspected.
- The initial combined bundle retains four failed assertions in one new unit
  fixture: it created two different IDs instead of a duplicated ID. The fixture
  now reuses the same saved area; the corrected full native run above passes.
  The production source and all three UI workflows were unchanged by that fix.
- Final phone/watch/widget Release passes in
  `/tmp/gridfix-boundary-startup-release.log`.

After both runs finished, Xcode's owned auxiliary `simctl diagnose` children
(PID229/parent97606 and PID4272/parent3899) stalled. Only those diagnostic children
were stopped. Their parents finalized with exit 65 for the initial unit failure
and exit 0 for the corrected native run respectively. No active test was stopped.
The one owned iOS 26.2 phone was shut down; the fake feed stopped and its location
was cleared. No TAK server was used. Physical locked-screen alert delivery,
ordinary boundary writes and the remaining startup/storage work are separate.
