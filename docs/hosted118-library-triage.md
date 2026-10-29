# Hosted 118 library outcome

Run 40883199523 on `bc563bd` is fully terminal: map and field succeed; library
has 59 passes / 1 failure / 0 skips across 60 cases. The failure is
`LargeLibraryWorkflowTests/testDenseMapAccessibilityKeepsEveryVisibleMarkerAfterCameraAndNightChanges`,
which exceeds the original five-minute allowance. The later 42-case console block
passes but excludes the earlier failure; the complete xcresult supplies the total.

Library artifact 12909430057 is downloaded, SHA-256 verified and extracted:
`11ce53f0aeb5f97390b8f4c31aa3cfdf06d1f896e6d78c6ebc9c840277628ee2`.
Result: `/tmp/mgrsgps-ci118-library/build/ui-tests.xcresult`. Summary and selected
activities are saved in `/tmp/mgrsgps-ci118-library-summary.json` and
`/tmp/mgrsgps-ci118-dense-activities.json`. Download parent 96177 and attachment
export parent 65635 are terminal/reaped.

The dense case passes initial visibility checks, hide/show and count comparisons,
then reaches the camera go-to field. At 299 seconds it is deleting the initial
`40R BN ` value before entering the distant grid. The 293-second hierarchy shows
the focused `map-goto-grid`, native keyboard and Select All menu item. A timeout
does not demonstrate lost markers, failed password protection or data loss.

Each verify currently performs two full `markers.count` snapshots; the log shows
roughly 10–12 seconds for dense AX count/existence operations. Text replacement
also spends time on native editing/diagnostic fallback. The app spindump samples
active SwiftUI/Core Animation work and ordinary run-loop processing, not proof of
a deadlock. Native screen recording export contains only “Unexpected Error:
Finished test run with pending attachment.” It is unavailable, so no video-based
conclusion is claimed for this run.

Next: inspect and reduce redundant AX traversal/editor interaction while retaining
the complete marker equality, greater-than-100, hide/show, distant/return camera,
night and original 300-second assertions. Reproduce the exact native case on the
combined held source, inspect captures and finish parents/cleanup before a single
follow-up push. Do not inflate the deadline or claim full hosted green.

Independent watch native control validation passed and its fresh disposable
simulator is deleted; see watch-own-route.md. No new TAK/network/credential,
container or database action. Current enrolled exchange and real renewal remain
open; the server stays off.
