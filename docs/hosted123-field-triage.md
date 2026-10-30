# Hosted run 123: field build-copy failure

Run 40973150871 on bb6af73 finished with map success and field/library failure. The field artifact 12944388076 (487,573,054 bytes) matched SHA256 `e8fd6b31d15f08d37157decc7524822c5eb0ce0c74be9ce27a52f09cb7064254`.

Initial field integration/UI results: 428 total, 418 passed, zero failed, 10 skipped. The subsequent expiry/recovery invocation failed before executing any tests: CopySwiftLibs for GridFixWatch.app reported “No such file or directory (2)” during a repeated build. The finalized expiry result has zero tests and unknown outcome. No exact missing-path root cause or provider regression is established. Later field stages were skipped.

The five post-build field invocations now use test-without-building to reuse the products already compiled by the initial integration/UI test action. The initial action still builds. Selection, destination, result paths, signing, feeds, assertions and 300/600-second limits are unchanged. This avoids the redundant watch build-copy phase; hosted confirmation remains required.

Local native validation reused existing products on a fresh iPhone 16e/iOS 26.2 simulator. The full PositionFix workflow passed in 46.363 seconds (one test, zero failures): the external fake OS GPS observer stopped delivery after observed freshness and resumed after observed stale assertions. Retained grid, disabled QR, stale day/night readouts, fresh recovery and Navigate/compass-unavailable assertions passed. Both stale screenshots were inspected. Result: `/tmp/mgrsgps-ci123-fix-cached.xcresult`; log: `/tmp/mgrsgps-ci123-fix-cached.log`. Setup 92778 and test 93456 exited zero and were reaped. The owned feed exited; fake location was cleared and disposable BCEE7F2D-736B-49E2-9A19-342B3395B535 was shut down/deleted. User watch preview retained. Workflow YAML parses.

Library failure requires separate artifact triage before a combined follow-up push. No full hosted pass claimed. TAK remains off; real enrolled exchange, renewal and physical gates remain open. No merge, publish or release.
