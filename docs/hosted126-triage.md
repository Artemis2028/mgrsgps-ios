# Hosted run 126: field passes; two native activation failures remain

Run `41005418151` on `d446114a3c9831dd4977c70b76943f878fecc7d1` is terminal. Field passed; map and library failed. Full hosted confirmation remains open.

All three downloaded artifacts match their published sizes and SHA-256 digests:

| Shard | Artifact | Bytes | SHA-256 |
| --- | --- | --- | --- |
| Map | 12958262825 | 617755621 | `c61fc37d977c2ac827d3caa00e66841bc26ea40958bccced0ab2b7e7acf1c57b` |
| Library | 12958755948 | 651924716 | `560267d85d53e0ad9ae32cc583099f4ab9591aefc5da9a7206c9fdda9002f06a` |
| Field | 12957903435 | 743178981 | `5c7a943967c43df318af1a219e9efdc962ecd68a4c342da5e6435f984735df72` |

Field initial integration/UI results are 428 total, 418 passed, ten skipped, zero failed. Later cached stages passed: expiry/recovery one, movement/course-speed one, boundaries five, navigation one, practice fifteen. The stationary external-feed control for random practice storage/relaunch assertions now has positive hosted evidence. This does not close physical GPS/background or TAK gates.

Map results are 52 total, 50 passed, one failed, one skipped. `GraphicWorkflowTests/testDrawRouteInsertKinkDragSaveEditAndPersist` failed before drawing because the options rail did not appear. The final recording and accessibility hierarchy agree that the toggle remained Collapsed and the rail was absent. The synthesized native tap at (346, 717) is the centre of the recorded button frame (318, 689, 56, 56). This differs from earlier failures where the rail was visibly open but a readiness query failed. Exact event-delivery or state cause is unresolved; the evidence does not justify a production change or a longer timeout.

The unchanged drawing workflow passed locally in 58.418 seconds, including inserting/dragging points, saving, editing, and finding the named four-point route after relaunch. Its persisted-route capture was inspected. Setup 54084, test 44020 and cleanup 72597 exited zero and were reaped. Only disposable phone `2E3B1A59-F2B3-4D1F-AF6E-F56EEC975C6D` was cleared, shut down and deleted. No fake GPS feed was used; the user's disarmed watch preview remains available.

Library results are 60 total, 59 passed, one failed, zero skipped. `SettingsBackupWorkflowTests/testSettingsBackupNativeFilesRoundTripRestoresSavedRecordsInDay` failed in 129.406 seconds at line 24, waiting for the Backup & restore navigation bar on the second visit. The initial backup save and record deletion had proceeded. The final recording and hierarchy show Settings still open, with the Backup & restore button frame (20, 584.3, 131.3, 44) containing the recorded activation at (85.7, 606.3). Exact activation cause remains unresolved. The five prior library rail-readiness failures are absent from this finalized result.

The unchanged local settings roundtrip passed in 94.722 seconds, including native Files export/reopen, restoration and persistence after relaunch. The restored-status capture was inspected: one track, one waypoint, one graphic/route and settings. Setup 21426, test 94801 and cleanup 76219 exited zero and were reaped. Only disposable phone `FD7CF7FA-5233-4DE9-9B2D-B930AF231D6E` was cleared, shut down and deleted. No active local test or GPS feed remains. Results are `/tmp/mgrsgps-ci126-settings-local.xcresult` and `/tmp/mgrsgps-ci126-graphic-local.xcresult`. Neither local pass establishes the cause of the hosted activation failures.

No production code, workflow assertions, fixtures or execution deadlines changed during this triage. Current enrolled iOS/Android exchange, renewal/native Renew UI and physical verification remain open. TAK stays off. No merge, publish or release.


A test-only follow-up now acknowledges these two disclosures within their existing wait budgets. After the first tap, it checks for the destination; one native retry is allowed only while that destination is absent and its source remains present and hittable. Map options additionally must still report Collapsed before another tap. The remaining wait uses the original five-second map or ten-second settings deadline. This helper is limited to presentation controls; it does not retry export, delete or restore operations. Focused native validation passed both workflows: drawing57.150s and settings backup93.963s, two tests and zero failures. Persisted-route and restored-backup captures were inspected. Setup11926/test32199/cleanup26343 exited zero and were reaped; only ownedB10302C3-E9B5-4156-831B-A4FA4EF8CAD0 was cleared, shut down and deleted. Fresh hosted confirmation remains open.
