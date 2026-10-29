# Hosted run 121: map workflow triage

Run 40942842806 on 905f92b completed the map shard with 52 tests: 50 passed, one failed, one skipped. Field and library were still running at this checkpoint; this is not a full-run result.

Artifact 12932308896 (588,965,003 bytes) matched GitHub SHA256 `5c90170cb884ec64044d917c6abaffd722b3bfee06b403cba873c482fcf69909`. Its finalized result bundle identifies `MapLayerWorkflowTests/testManualPanCancelsFitRequestedWhileSavedGeometryWasLoading()` as the sole failure. The pan-change assertion passed. The failure was the helper waiting for `1 routes · 1 tracks` after tapping the debug Finish saved map load button; the loading gate remained visible. The native recording shows coordinate HUD rows reflowing around that tap. This supports a moving-target test interaction explanation, without proving a production defect or hosted repair. The hang-observer log was empty.

The test helper now permits one additional native tap only while the idempotent debug gate-removal button remains present and hittable. It retains the original ten-second readiness budget and overlay, loading, pending-fit, manual-pan and Go to assertions. Production code, job/test deadlines and fixture data are unchanged.

On a fresh iPhone 16e / iOS 26.2 simulator, all three saved-geometry workflows passed: manual pan 22.300s, newer Go to 33.483s, pending Show all 15.139s; three tests, zero failures, 70.922s total. Parent 33654 exited zero and was reaped; setup parent 31427 also exited zero/reaped. Native manual-pan and Go to captures were inspected with loaded counts and retained camera intent. This is local evidence, not a hosted pass.

Evidence: `/tmp/mgrsgps-ci121-map-summary.json`, `/tmp/mgrsgps-ci121-map-pan-activities.json`, `/tmp/mgrsgps-ci121-map-pan.mp4`, `/tmp/mgrsgps-ci121-map-pan-contact.png`, `/tmp/mgrsgps-ci121-pan-local.xcresult`, `/tmp/mgrsgps-ci121-pan-local.log`, `/tmp/mgrsgps-ci121-pan-local-summary.json` and exported images. Fake location cleared; only disposable phone 5FE14F75-46A1-4214-A5C5-14D6922FFC52 shut down/deleted after terminal parents. Intentional user watch preview retained.

Hold this follow-up locally until all CI121 jobs are terminal. Current enrolled iOS/Android exchange and renewal remain open; TAK stays off. No merge, publish or release.
