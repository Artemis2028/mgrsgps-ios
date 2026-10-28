# Hosted110 field failure — 28 October 2026

Run40729291858 tested98c5c17. Map47 and library59 UI cases pass. The field job
was cancelled after its two-hour maximum; GitHub check122960900902 explicitly
records “The job has exceeded the maximum execution time of 2h0m0s”. The
following dedicated background/fix/course phases were skipped.

All artifacts are SHA256-verified and extracted locally:

| Shard | Artifact | SHA256 |
| --- | --- | --- |
| Map | 12840097437 | b286a89ce05bee6f423e7e306e0555b3a954fb3210d25cf2be697054aad8942d |
| Library | 12841300349 | df9bff377acf5b66e5d13611ad7186ae13a5e70db59372a5cb5acfd6cfc5ca8c |
| Field | 12842322586 | 1ecf2208e5b6871d945ec41d9db5290f6ecb46445cb47705082e03139e96ae43 |

## First failure, not the later cascade

FieldExportWorkflowTests.testNativeExportCancellationAllowsAnotherCompleteExport
entered an invalid slash filename, confirmed Choose location was disabled,
and tapped export-filename-cancel at41.21s while the filename keyboard had focus.
The animation-idle notification then timed out. Subsequent queries could not
snapshot the app. Its own diagnostic log reports “Unable to perform work on
main run loop, process main thread busy for30.0s”. The next single-track test
could not get launch progress; the following field-fix test never advanced.
This is a failure, not proof that the skipped workflows passed.

The first freeze precedes the test's native Files cancellation gesture. There
is no evidence to blame document-provider permissions or the slash validation
itself. The UI evidence points to the focused filename-sheet dismissal; its
precise runtime deadlock stack was not captured.

## Repair candidate

ExportFilenameView clears its FocusState before Cancel or Choose location
closes the naming sheet. The invalid-filename error remains; the redundant
valid-filename footer is removed because the file extension is already shown.
The existing test still cancels with the keyboard focused, then independently
cancels the actual native Files sheet, exports again, and imports the complete
three-waypoint/one-graphic/one-track library. It passes locally on iOS26.5 in
/tmp/mgrsgps-export-focused-cancel.xcresult. Hosted used Xcode26.6, so a new full
hosted run remains required before claiming the first failure is repaired there.
All three UI cases in that bundle pass: keyboard-focused Cancel → native Files
Cancel → complete library export/import; both night single-track exports (detail
and menu) reopening exactly one track; and day/night portrait/landscape map
options. Whole-display screenshots replace app-region captures after rotation;
the final complete night-landscape image was inspected.

Unsigned phone/watch/widget device Release passes in
/tmp/mgrsgps-export-focused-cancel-release.log. The prior complete UI milestone
is babdcf1; saved-track local commits also need hosted confirmation.
