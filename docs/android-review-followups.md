# Remaining eacf084 review details

Source rechecked 25 October 2026 against Android `eacf084`, now included in the
`claude/tak` checkout at `38d0170`. This narrows the previous vague
“offline/lasso/protected-file audit” backlog into concrete work.

## Lasso implemented after this audit

Android `map/Lasso.kt` and `ui/screens/MapScreen.kt` implement a freehand,
automatically closed screen-space loop, using the even-odd containment rule.
The map does not pan while drawing. Only visible local waypoints and graphics
participate; a graphic is selected when any stored vertex is inside. Remote TAK
contacts do not become editable local records. The selected waypoint markers
and graphic vertices are highlighted. The controls offer Hide, confirmed Delete,
Again and Close. Choosing a draw type ends the lasso. The reviewed Hide action
sets visibility false rather than toggling, including after concurrent changes.

The iOS implementation now provides the freehand loop, native map projection,
selection feedback, explicit idempotent Hide and confirmed Delete. Tap corners /
Select loop and Select visible offer accessible alternatives. Worker-staged
repository phases retain only unfinished IDs on failure. Drawing modes end the
lasso. Core, native projection/pan and filesystem tests cover the cases above;
day/night native loop/confirmation/hide/delete/relaunch workflows are recorded in
[map lasso](map-lasso.md). Physical gesture/large-text/dense-library validation
remains. Mixed library selection continues as a separate workflow.

## Protected interchange files implemented after this audit

Android `data/ProtectedFiles.kt` wraps one GPX/KML/other export in a single-entry
ZIP, then uses the same `MGRSGPS-ENC1` envelope as a protected backup. The inner
archive distinguishes a backup from an interchange file. The eacf084 change
rejects a payload larger than the reader permits and removes the temporary
plaintext file even when sealing fails. An export recreated after Android loses
its password on process death fails visibly and removes its empty destination.

The iOS port now implements the single-file contract, authenticated bounded
format dispatch, all six export choices, protected saved-track GPX and
password/retry/cancel handling through queued incoming review. Plaintext stays
in memory and only encrypted bytes reach Files. The explicit backup importer
remains distinct. Independent Java fixtures and reverse-direction verification
cover all six formats; actual GPX/KML Files save/reopen and the existing protected
backup workflow pass. See [implementation/evidence](protected-interchange-files.md)
for native confirmation, queue and remaining physical-provider checks.

## Offline view-lifetime fix already has the relevant ownership

Android moved offline record writes into repository-owned work so leaving the
map cannot cancel completion. iOS `MGRSGPSApp` owns `MapLayerStore` as a StateObject;
its `downloadTask` begins/finishes through the persistent map library. Neither
`MapScreen.onDisappear` nor `MapLayersView` cancels the task. Pause is explicit,
and already-stored tiles remain resumable. That architecture addresses the
particular view-lifetime issue without transplanting Android's coroutine scope.
The native regression now gates synthetic raster responses, starts the normal
Layers download, leaves both Layers and Map for Position, releases responses only
there, waits for actual completion, then returns and relaunches with Offline only.
Both day/night workflows pass. Native tests also cancel the caller before
completion, inspect every stored tile after reopening, prove offline lookups make
zero network calls, and verify explicit Pause/Resume retains the same area ID.
See [offline-map validation](offline-maps.md). Physical background execution,
provider failures and storage pressure remain separate.

## Newly identified saved-area controls still missing

The current Android checkout at `6f9865f` retains the offline-area Rename and
Update actions in MapScreen. iOS currently offers Show, Resume for incomplete
areas, and Delete, but lacks Rename and explicit fresh Update for a complete area.
Android Update re-fetches even previously cached tiles and records interrupted/
failed status. An iOS Update must bypass both saved pinned tiles and browse cache,
retain existing coverage on failure, persist update-pending state across relaunch,
and finish only after the requested refresh succeeds. Remaining stored/expected
tile counts, size/date metadata and these controls are implementation work, not
iOS limitations; the view-lifetime regression does not close those gaps.
