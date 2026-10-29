# Hosted run 121: library workflow triage

Run 40942842806 on 905f92b is terminal: field passed, map and library failed. The finalized library result reports 60 total tests, 59 passed, one failed and none skipped. KML and KMZ workflows passed this run; this does not establish the cause of the previous Files stall.

Artifact 12934405685 (719,245,096 bytes) matched GitHub SHA256 `b8e25b8a6613f4e8eeffbf5c7bf1df4800889caee70f2b2405528946c4d6a609`. Download parent 49096 and extraction parent 74453 exited zero and were reaped. Evidence is in `/tmp/mgrsgps-ci121-library`, summary `/tmp/mgrsgps-ci121-library-summary.json` and dense activities `/tmp/mgrsgps-ci121-library-dense-activities.json`. The hang-observer log was empty; no captured stack is claimed.

The sole failed case was `testDenseMapAccessibilityKeepsEveryVisibleMarkerAfterCameraAndNightChanges`, at line 75 waiting for more than 100 native markers after returning with Go to. It failed an assertion after 299.408 seconds, not a test-allowance termination. Earlier hide/show and distant-empty assertions passed. Native video `/tmp/mgrsgps-ci121-library-dense.mp4` and contact sheet `/tmp/mgrsgps-ci121-library-dense-return.png` show the correct full grid accepted, the camera returned and dense flags rendered before the end. The early native marker-count query consumed about 9.3 seconds and retried at the wait deadline.

The pending test-only change uses the existing verify helper after return: wait up to ten seconds on the SDK annotation count, then assert exact SDK/native count equality, more than 100 markers, Compass and About this map. It retains hide/show, empty distant view, return and night checks, original 300/600-second allowances and fixture contents. No production change or hosted repair is claimed.

Fresh local validation first stopped at initial SDK readiness, before the changed return step. A native post-failure screenshot showed the system location permission alert. Parent 79931 exited 65 and was reaped. After simulator permission grant, parent 98112 completed the full dense workflow successfully in 118.394 seconds, one test and zero failures. Result `/tmp/mgrsgps-ci121-dense-granted.xcresult`, log `/tmp/mgrsgps-ci121-dense-granted.log`. The day attachment was still permission-occluded and is not a clean day visual claim; the final night attachment was inspected unobstructed. SDK/native marker equality, hide/show, distant empty/return and night assertions all passed. Extreme symbol overlap remains visible and is not resolved by this test-only change.

Both test parents and setup 52696 are terminal/reaped. Fake location cleared; only disposable A6655870-1AEA-4EFA-B106-E7056C53619C phone shut down/deleted. The intentional user watch preview remains. No redundant core or Release build for these UI-test-only changes.

Current enrolled iOS/Android exchange and renewal remain open. TAK stays off. No merge, publish or release.
