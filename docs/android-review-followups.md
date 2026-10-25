# Remaining eacf084 review details

Source rechecked 25 October 2026 against Android `eacf084`, now included in the
`claude/tak` checkout at `38d0170`. This narrows the previous vague
“offline/lasso/protected-file audit” backlog into concrete work.

## Lasso is missing

Android `map/Lasso.kt` and `ui/screens/MapScreen.kt` implement a freehand,
automatically closed screen-space loop, using the even-odd containment rule.
The map does not pan while drawing. Only visible local waypoints and graphics
participate; a graphic is selected when any stored vertex is inside. Remote TAK
contacts do not become editable local records. The selected waypoint markers
and graphic vertices are highlighted. The controls offer Hide, confirmed Delete,
Again and Close. Choosing a draw type ends the lasso. The reviewed Hide action
sets visibility false rather than toggling, including after concurrent changes.

There is no lasso implementation in the current iOS map. Mixed library selection
is implemented, but does not satisfy this map workflow. Add the draw interaction,
selection feedback, explicit idempotent hide, confirmed deletion and drawing-mode
exclusion. Test geometric cases, hidden-folder filtering, remote exclusion,
concurrent visibility changes, partial repository failures and native day/night
interaction. This is an implementation gap.

## Protected interchange files are missing

Android `data/ProtectedFiles.kt` wraps one GPX/KML/other export in a single-entry
ZIP, then uses the same `MGRSGPS-ENC1` envelope as a protected backup. The inner
archive distinguishes a backup from an interchange file. The eacf084 change
rejects a payload larger than the reader permits and removes the temporary
plaintext file even when sealing fails. An export recreated after Android loses
its password on process death fails visibly and removes its empty destination.

Current iOS `BackupTransfer` protects backup ZIPs only. The native interchange
export actions have no equivalent protected-file choice, and protected incoming
files enter the backup reader rather than a single-file interchange decoder.
Add the single-entry contract, bounded authenticated decoding and format dispatch,
protected export options, password/retry/cancel handling and queued incoming-file
review. Keep plaintext preparation in memory, as existing protected backup export
does. Do not persist a password or imply that the current backup-only tests prove
this workflow. Cross-language fixtures and actual Files round trips are needed.

## Offline view-lifetime fix already has the relevant ownership

Android moved offline record writes into repository-owned work so leaving the
map cannot cancel completion. iOS `MGRSGPSApp` owns `MapLayerStore` as a StateObject;
its `downloadTask` begins/finishes through the persistent map library. Neither
`MapScreen.onDisappear` nor `MapLayersView` cancels the task. Pause is explicit,
and already-stored tiles remain resumable. That architecture addresses the
particular view-lifetime issue without transplanting Android's coroutine scope.
This is source evidence, not a new runtime completion/relaunch test. Add a focused
leave-map/finish/reopen regression before closing the validation gate. Physical
background execution, provider failures and storage pressure remain separate.
