# Hosted120 library cancellation — 29 October 2026

Run40920509565 on e0eec01 is terminal: field/map pass; library was cancelled.
GitHub's check annotation confirms the job exceeded its two-hour limit. The
branch stayed at e0eec01 throughout; no new push cancelled it. Individual test
300/600-second limits and the job's120-minute limit were unchanged.

Before job cancellation, KMLPackageWorkflowTests recorded:

- KMLImportMapPersistenceAndATAKFilesPackagePreview:257.055s, failed retrieving
  native snapshots because the application main run loop was busy for30s.
- KMZNativeFilesRoundTripPreservesGeographicCounts:300s allowance exceeded, with
  failure to obtain application launch progress.

KML reached Choose location at73s. UIKit animation completion did not arrive
by134s; subsequent native Files-picker queries reported the busy main loop.
The following dense case started after the KMZ failure, but no successful dense
or complete-suite result is claimed. The job later reached its two-hour limit.

The94,070,551-byte library artifact12926277351 matches GitHub SHA256
3cd841eb9739df7d48e3c1cfedc9bbb65d87ac4a825c6f2c16646da6535507bc.
It retains a staging xcresult without Info.plist, not a finalized result bundle.
No reliable complete test counts, final activities, spindump or recording are
claimed from it. Logs and retained app output support the specific errors above;
they do not establish which production or native service code blocked the loop.

Evidence: /tmp/mgrsgps-ci120-library.log and
/tmp/mgrsgps-ci120-library/build/ui-tests.xcresult/Staging. Download/parse parents
50247/99788 are terminal/reaped. A focused native reproduction of the two failing
cases is running on a fresh iOS26.2 simulator, with the original assertions and
deadlines. No production change, new hosted run or deadline increase yet.


## Focused local reproduction and next-run diagnostics

On a fresh iOS26.2 simulator, the unchanged KML case passes80.597s and both
selected cases pass with zero failures in143.351s. Xcode finalized exit0/TEST SUCCEEDED after its600-second simulator-diagnostics
collector timed out; parent71722 is reaped and the result bundle is finalized. The local
runtime/toolchain differs from hosted Xcode26.6/SDK26.5, so it does not establish
that the hosted fault is fixed. No production Files change was justified by the
available evidence.

The follow-up adds a read-only CI observer for the existing native stall signals
(animation completion absent / app main loop busy). It captures at most three
one-second stacks, once per PID, and only for the exact MGRSGPS executable in the
chosen simulator's own app bundle. It never signals/stops the app, reads account
files, injects input/location or changes test outcomes/deadlines. The existing
cleanup trap stops only the diagnostic observer; its bounded sample child has an
eight-second subprocess timeout. Artifacts include the observer log and stacks.
Managed app tests use synthetic test stores; no live login fixture is staged.

All13 Python observer/feed/recording tests pass, including exact binary ownership,
wrong-device exclusion, once-per-PID and three-sample limits. Workflow YAML parses.
No new native stall/sample result or fixed hosted fault is claimed yet. Current
production641core/watchsimulator/unsignedRelease results remain applicable: this
follow-up changes CI diagnostics only, alongside the already validated watch UI.


Final native evidence: KML80.597s, KMZ62.754s, two cases/zero failures. ATAK and
KMZ reopened previews were inspected with their complete filenames and expected
1waypoint/1graphic and1waypoint/2graphics counts. After test finalization, the
collector successfully sampled exactly the healthy owned test app once; its
output contains a native call graph. This verifies the macOS process matching
and sampling path, not reproduction of the hosted stall. Probe58152 exit0/reaped.
Fake GPS was cleared and fresh695B phone shutdown/deleted only after every parent
was terminal. The user's watch preview was preserved. All13 Python tests and
workflow YAML parsing pass; test/job deadlines remain unchanged.
