# Hosted run 122: map rail readiness

On 0cf1542, map job 123744443549 failed with finalized totals 52 tests: 50 passed, one failed and one skipped. Prior manual-pan/load-gate test passed. Field passed; library was still active at this checkpoint.

Artifact 12940256133 (642,986,327 bytes) matched GitHub SHA256 `73d8a8bb2e3d545aa04c3df18324c7da7619e0e996adcba563bbe1707e9c75e3`. Download parent 52129 and extraction parent 89775 exited zero/reaped. Summary `/tmp/mgrsgps-ci122-map-summary.json`; activities `/tmp/mgrsgps-ci122-map-controls-activities.json`. Hang-observer log empty; no stack claimed.

The sole failure was `MapToolWorkflowTests/testHiddenActiveRulerAndDrawingRetainFinishControls()` after 41.271s. NativeMenuInteraction.swift required the rail scroll container itself to be hittable after hiding the active ruler and closing settings. The native recording `/tmp/mgrsgps-ci122-map-controls.mp4` and contact sheet show the rail visibly open, with the ruler panel crossing the container activation area and tool rows still usable. This scopes a test readiness problem, without a claimed production change.

The helper now waits for a fully contained, nonempty, hittable native child row. Requested-tool scrolling, full-row geometry and hittability remain checked separately. Five-second rail readiness and 300/600-second test limits are unchanged; no injected state or fixture change.

Fresh iPhone 16e / iOS 26.2 validation passed both workflows: active ruler/drawing 71.397s and hidden tools persistence/reset/Go to/day/night 123.429s; two tests, zero failures, 194.825s total. Result `/tmp/mgrsgps-ci122-rail-local.xcresult`; log `/tmp/mgrsgps-ci122-rail-local.log`. Native active-drawing and night Go to result captures inspected. Setup70247/test15685 exited zero/reaped. Fake location cleared; only disposable AC2C6598-5982-4CE1-BAB9-A506E2893DD4 phone shut down/deleted. Intentional user watch preview retained.

Test-only follow-up held locally while hosted library remains active. No redundant core/Release runs for this helper change. Full hosted confirmation, current enrolled iOS/Android exchange and renewal remain open. TAK stays off; no merge, publish or release.
