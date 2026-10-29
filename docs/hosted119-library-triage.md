# Hosted119 library timeout — 29 October 2026

Run40903664862 on40e7e63 is terminal: field and map shards pass. Library's complete
result is60 tests:59pass,1failure,0skip. The only failure remains
LargeLibraryWorkflowTests.testDenseMapAccessibilityKeepsEveryVisibleMarkerAfterCameraAndNightChanges,
which exceeded its original300-second allowance. The restarted runner's final
42-test success subtotal does not make the whole shard green.

Artifact12916882688 is582364714 bytes; the downloaded ZIP matches GitHub SHA256
8efb1340d2dbba472d2b44e6ab40036449dd998d6f60dfc20bb35a202f23d345.
Complete summary and activity tree are retained at
`/tmp/mgrsgps-ci119-library-summary.json` and
`/tmp/mgrsgps-ci119-dense-activities.json`. Native log:
`/tmp/mgrsgps-ci119-library.log`. Parent27367 downloaded successfully and was
reaped; parent8027 extracted/parsed successfully and was reaped.

The native activity log reaches Go to replacement: long press257.88s,
Select All menu-item tap285.10s, delete288s and typing the complete distant grid
at298.65s before the300s timeout. This is accumulated native accessibility/input
latency, not evidence by itself of a production deadlock. The retained day PNG
was inspected: synthetic dense map markers, compact grid and controls are visible;
extreme label overlap remains a readability limitation. No night/final-failure
screen or video conclusion is inferred from that earlier capture.

The follow-up keeps the same full-coordinate assertion, all SDK annotation versus
individually accessible marker checks, hide/show, distant camera/return and night
steps and the original300/600s timeouts. Go to already prefills the current zone
and square; the test now completes a matching visible prefix with native typing
instead of unnecessarily selecting/deleting it. An unexpected prefix retains the
existing full replacement fallback. No production map, fixture density, marker
count, assertion or timeout was weakened. Local native verification is pending. First fresh-device run exited65 before
Go to: the SDK map existed with Zoom17x but had not yet published annotations.
The test now waits within its existing10s window for the SDK dense annotation
count before retaining the exact per-marker equality and >100 checks. A rerun
is active; the first run is not counted as a prefix-typing pass.


## Follow-up validation

The complete native dense case passes in121.051s on a fresh iOS26.2 simulator,
with the same300/600s timeouts and every original marker/visibility/camera/night
assertion. Evidence: `/tmp/mgrsgps-ci119-dense-fixed.xcresult` and
`/tmp/mgrsgps-ci119-dense-fixed.log`. Parent76702 exits0 and is reaped.
The test day attachment is occluded by a first-use permission prompt; it is not
claimed as a clean visual. Its night capture was inspected. After test completion,
OS location grant and a separate launch of the same synthetic day fixture yielded
an unobstructed inspected `/tmp/mgrsgps-ci119-dense-day-unobstructed.png`.
That additional capture is not a repeat/full workflow claim. Extreme symbol/label
density remains an honest readability limit; no native marker was hidden to pass.
Setup8897 and visual54614 are terminal/reaped. Fake GPS was cleared, disposable
B3DA2F42 shut down/deleted and original clients untouched. No further core/Release
rerun is warranted for this UI-test-only follow-up: current production641core and
watchsimulator/unsigned phone-watch-widgetRelease passes remain valid.
