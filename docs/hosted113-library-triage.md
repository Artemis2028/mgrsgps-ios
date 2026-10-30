# Hosted 113 library triage — 29 October 2026

Run40807863444 on a54ac75 is terminal. Field/map shards pass. The complete
library result bundle reports56 passes and four failures across60 cases. The
console's final selected-tests block reports only42 tests/three failures; it
omits the earlier timed-out dense-map test. Use the full result summary.

Library artifact12873327051 is SHA-256 verified:
255d295dbfeb04e8dbac24beac434a341ad2af9ddf8f2ea83d5859946c0a6f32.
It is extracted at /tmp/mgrsgps-ci113-library. The summary is retained at
/tmp/mgrsgps-ci113-summary.json and stage log at
/tmp/mgrsgps-ci113-library-failed.log.

Failures:

- Dense map complete-accessibility case exceeds the existing300s allowance.
  Initial repeated native marker-count/Compass/attribution queries each consume
  substantial time. Its spindump includes idle run-loop and SwiftUI graph work;
  this is not a proven product deadlock. Every marker must stay accessible.
- Dense library search/grid/night case times out waiting for Map options to
  acknowledge Expanded. Its recording ends with the visible plus still closed.
- Filtered Select All displays0 instead of3 selected after consecutive native
  Select/Select All taps. Filtering itself still shows exactly one item in each
  of the three sections. No count/fixture assertion has been weakened.
- Complete10,000-split day case succeeds through initial first/last navigation,
  then fails to reopen Checkpoint splits after relaunch. The recording retains
  the expanded saved result and visible View all10,000 splits link.

The four unchanged workflows ran locally together on iOS 26.2 with the CI
3-second synthetic GPS feed. Dense search/grid, filtered Select All and saved
splits pass unchanged in 45.675/11.456/46.514s. The stronger dense accessibility
case instead reproduces a product cache defect: after returning to the original
camera, 907 markers are accessible while the SDK reports 924 annotations.
The baseline completed four cases with one failure, then finalized exit 65
after its diagnostic collector. Its bundle and log remain at
/tmp/mgrsgps-ci113-library-baseline.xcresult and the same stem with .log.

The repair marks visibility dirty using a constant-time render callback. On the
next accessibility read it compares complete native annotation/view identities
before reusing ordering. A changed native element count invalidates immediately.
Camera/data guards, native ordering, sparse-map fallback and all SDK elements
remain. No marker is capped, hidden, substituted or dropped from assertions.

The same four unchanged UI workflows now pass together:

- Complete visible marker counts through hide/show/camera/night: 179.270s.
- 5,000-waypoint search/grid/selection/night: 46.581s.
- Filtered mixed-section Select All: 11.410s.
- Complete 10,000-split first/last/relaunch workflow: 46.574s.

Final result: four cases, zero failures, exit 0 / TEST SUCCEEDED in
/tmp/mgrsgps-ci113-map-visibility-repair.xcresult. The matching .log retains full
steps. Exported night dense-map/grid-search and final 10,000th split captures
were inspected under /tmp/mgrsgps-ci113-map-visibility-repair-attachments/.
Extreme-density marker labels still overlap; no decluttering/cap is introduced.
Unsigned phone/watch/widget device Release passes at
/tmp/mgrsgps-ci113-map-visibility-release.log. Every local parent is reaped,
synthetic location cleared and the one owned simulator shut down.

This closes the reproduced visibility-cache defect. Three hosted failures have
local baseline and repaired-head passes, but remain intermittent until fresh
hosted confirmation; no claim of a proven shared cause or full hosted green.
No assertions, fixtures, selection counts or time limits were relaxed. No TAK
connection, server or real position was used.
