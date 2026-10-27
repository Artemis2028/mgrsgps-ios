# Hosted field UI interaction repairs

Hosted run `40214931861`, job `121233903024` (waypoint-save commit `8edb313`),
passed build, screenshots and location-feed recovery but failed five UI cases:
both Live Activity workflows, hidden-Record escape controls and both waypoint
save-failure workflows. The job logs were inspected; this was not a timeout.

- A scrolled Live Activities switch was reported hittable beneath Settings'
  navigation bar. Its centre coincided with Done, so the test dismissed Settings
  instead of changing the switch. `revealSettingsControl` now puts the complete
  control below the navigation bar and above the bottom edge before a validated
  visible-frame switch tap. Activity counts, opt-out preserving the underlying
  session, navigation pause/resume, recording backgrounding and session end are
  still asserted.
- After discarding a recording with Record hidden, the now-idle tool's view and
  sheet owner disappear. Older runtimes dismiss the recording sheet immediately;
  others retain Done. The workflow handles either sheet lifetime, then asserts
  that the tool and recording banner are absent and map controls are reachable.
  Stop must still be reachable during the active recording.
- Coordinate-format switching now dismisses the field keyboard and uses the
  validated visible frame, then waits for the latitude field. Field entry and
  retry use the same native-input helpers. The DEBUG-only empty test-directory
  repair button moved from a clipped Form row into the visible save-error banner
  with a 44-point target. It still removes only that empty temporary directory;
  Release does not include it. Initial real write failure, retained draft, stable
  retry, one durable point and relaunch remain asserted.

Validation uses the existing single `GridFix CI Runtime Field Checks` iPhone on
iOS 26.5, with a real Core Location simulator feed of fake positions. The two
waypoint cases pass in `gridfix-ci-field-ui-fixed-20261025.xcresult`; that bundle
still failed the earlier Live Activity/map interactions and is not an overall
passing run. The final `gridfix-ci-live-map-fixed-20261025.xcresult` passes both
Live Activity cases and the hidden-record case. Final screenshots were inspected.
No test assertion was skipped and no production permission logic changed.

The first local replay applied simulator privacy commands in the wrong order,
which removed location access. The corrected setup revokes Always first, then
grants While Using, matching the hosted workflow. Later recording/navigation
checks use real delivered samples, not injected app fixes. Only one owned phone
was booted at a time; the location feed is stopped and the phone shut down after
validation. A complete new hosted run remains required.

## Library/projection follow-up and bounded hosted jobs

Hosted run 40231275491 passed all 188 integrations (two opt-in local TAK skips)
then encountered two further UI failures before reaching the 90-minute job
limit. It did not finish the suite or the later real-location phases. Its
unfinished result bundle could not be exported. This is not a hosted pass.

- The Favourite native menu item exposed an invalid/infinite activation frame
  to XCTest's default tap. Library search now uses the same validated native
  menu helper already used by the other workflows. Favourite persistence,
  first-in-sort, removal and relaunch assertions remain.
- The night projection workflow opened its editor successfully, then swiped
  down twice while already at the top. That dismissed the sheet. It now reveals
  the actual position-method control and changes it directly. The base-selection
  result is awaited before continuing. The invalid-distance rejection, disabled
  Save, corrected preview, coordinate-mode retention and night assertions remain.

The hosted workflow now runs exhaustive library/map/field shards on separate
runners, each with one test simulator and parallel XCTest disabled. The field
shard also executes all app integrations and the five existing dedicated real-
location scenarios. Core tests still gate every build; screenshots run once.
All 42 current UI classes are accounted for: 37 assigned exactly once and five
retained in their dedicated feed phases. New classes automatically receive one
stable shard; missing/renamed configured classes fail selection. Three partition
regressions and the three existing feed-recovery script tests pass. Actionlint,
YAML parsing and all shell-block syntax checks pass. No assertion is excluded.

Artifacts have distinct shard names. Screenshot export requires a completed
xcresult Info.plist; incomplete raw evidence remains in the artifact without
masking the original job failure. The legacy ci-status branch explicitly says
it covers only the library shard; the three GitHub workflow job conclusions
remain the full hosted gate. A complete hosted pass remains required.

The final local bundle `/tmp/gridfix-ci-library-projection-final-20261026.xcresult`
passes all five existing library search and projection workflows on iOS 26.5.
The earlier replay passed the three library cases but still dismissed the night
projection editor; that failed bundle is not counted as a passing run.

## Sharded run 79 follow-up

Hosted run `40244289326` completed all shards without the former timeout.
The map job passed. Library reported night folder Rename, decimal coordinate
selection and the night-mode switch workflow; field reported the real-location
practice workflow. The remaining assertions are retained.

The actual hosted night-library recording shows Rename still in its popup
after the tap. Folder options now use the existing native scrolling field
choice sheet, with red/black night appearance. Rename or confirmed deletion
starts after the choice sheet dismisses; cancellation performs no action and
the captured folder is revalidated. This avoids nested popup presentation.
The folder-chip long-press context menu retains its existing shortcuts.

Coordinate segment taps use the validated visible frame, matching the existing
projection/save-retry workflows. Night-mode taps target the switch value side
and assert the resulting value before dismissing Settings. Save rejection,
corrected coordinates, edit/relaunch, opaque night navigation and day restoration
remain checked. Landscape captures now use the whole display, with an explicit
landscape-window wait; a rotated application-only screenshot could be clipped.

The hosted practice failure already displayed Course complete and the completed
banner: real fixes continued during native UI setup. Only this live-feed start
check now accepts progress or an already completed result. The two scored
points, completion, summary dismissal and persisted practice log are still
required; other setup tests still require the progress state.

Local `/tmp/gridfix-ci79-final.xcresult` passes all four former hosted failures
on the same iOS 26.5 phone, including the real simulator-location feed.
The subsequent folder-sheet checks are recorded separately below. The first
three-case replay executed successfully but stalled gathering simulator
diagnostics; that diagnostic subprocess was stopped and it is not the final
evidence. A subsequent folder replay caught a native confirmation tap that
left Keep contents in Base visible; it now uses the validated frame helper.
No assertion or test class was excluded. Full hosted green remains required.

The final choice-sheet bundle `/tmp/gridfix-ci79-choices-final.xcresult` passes
the night cancellation/rename workflow, full mixed-folder rename/delete-keeping-
contents persistence workflow and night/landscape/day-restoration workflow.
Screenshots confirm the new red/black choice sheet. Full-display capture exposed
a separate compact-height problem: the portrait header and vertically stacked
filters left no visible record in landscape. Compact-height phones now put
Routes & tracks in the header and folders/search alongside each other, preserving
44-point controls and the ordinary portrait layout. The landscape regression
now opens the saved waypoint, Add and Routes & tracks through their visible
frames and verifies each resulting editor/library. It resets device orientation
in setup and teardown so a failed rotation cannot leak into the next test.
XCTest can report invalid activation points for these visible controls after
rotation; actual interactions and results provide the check instead.

Final compact-layout bundle
`/tmp/gridfix-ci79-landscape-actions-final.xcresult` passes the expanded native
night/landscape/day workflow. The landscape screenshot shows the complete
waypoint row below folders/search, with all four night navigation buttons and
header actions visible. Actual frame taps open the existing waypoint editor,
new-waypoint editor and Routes & tracks library. Screenshots were inspected.
The final phone/watch/widget simulator Release build passes. Hosted CI still
needs a complete pass on the pushed revision.

## Older Xcode watch type checking

Runs 40251073307 and 40252856747 passed core tests but stopped during build:
Xcode 26.6 could not type-check the watch camera bounds expression, which joined
four optional mapped/flattened arrays with overloaded additions. Full build
artifacts identify WatchMapView.swift:124; the tailed job output omitted the
actual error. Bounds preparation now appends explicitly typed GeoPoint arrays
in the same order, with unchanged camera geometry. Debug watch simulator builds
for arm64 and x86_64 pass locally. CI now prints all compiler error lines on a
failed build as well as retaining its complete log. Actionlint passes. The
older compiler is available on GitHub, so its subsequent run remains the
authoritative compatibility check.

Hosted run 40253455102 at 56d7a3f confirms all three Xcode 26.6 simulator
builds pass after the watch bounds refactor. Full job outcomes were still
in progress at the library-persistence checkpoint. The new day/night library
failure class is automatically included once in the library shard; see
[library staging evidence](library-worker-persistence.md).

## Superseded PR runs

CI now uses a workflow concurrency group scoped to the PR number (or branch
for non-PR events), cancelling older grouped runs when that same PR receives a
new commit. Other PRs/branches remain independent. Before this change, the
3f93b15 and 6baed60 jobs queued behind older 56d7a3f jobs. A cancelled run is
not a pass; all three jobs on the final head still must finish successfully.
The completed map job on 40253455102 is retained as partial older-head evidence.


## Target-selection follow-up

The new `NavigationTargetWorkflowTests` class is assigned exactly once to the
map shard. The current inventory is 43 UI classes: 38 in the three normal shards
and five dedicated real-location scenarios. Six script tests and actionlint
pass. See [target save behavior and validation](navigation-target-persistence.md).

Older run `40253455102` completed with passing map and failed library/field
shards: decimal-entry snapshot, route append, and recording Live Activity status
reveal. All builds passed. These remain diagnostic evidence, not a full CI pass.
Current/final-head hosted results must be evaluated separately; cancelled older
runs are not passes.


## Hosted 04617f0 diagnostics

Run 40267500064 field job 121393243322 completed with failure. Job logs identify
LaneCueWorkflowTests line 26, LiveActivityWorkflowTests line 21 and
OrientationWorkflowTests line 49. Map/library were still running when inspected.
These are pending repairs; no full hosted pass is claimed. Course progress worker
validation is recorded separately in [course persistence](practice-progress-persistence.md).


## Reminder choices and explicit settings hit targets

The 04617f0 lane failure's accessibility dump still contains the open reminder
menu, with Every 5 min selected and Every 10 min visible. The reminder now uses
the existing scrolling FieldChoicePicker; the Android minute values and saved
integer remain unchanged. Guide settings also use the field palette and an
opaque content background in day/night mode.

The Live Activities failure retained value 1 after the opt-out tap. SwiftUI
exposed both a label-wide outer Switch and a nested actual Switch; the native
switch helper now targets the latter's validated centre. The product row has a
minimum 44-point height. The workflow still requires actual ActivityKit counts,
opt-out without stopping navigation/recording, background recording, and
pause/resume/end lifecycle transitions.

The orientation failure was Portrait after a pinned Flipped relaunch, before
the later Auto assertion. The regression now reveals the whole control and
uses a validated segment frame, then separately checks its selected state and
the actual window geometry. No rotation assertion is removed.

Settings also attaches the orientation scene host to its presented window, so
its observed preference changes can request geometry while the root is covered.
The root host remains for shortcuts and normal application lifecycle. This uses
the existing public scene/mask API and does not alter Android integer values.

Local `/tmp/gridfix-settings-ci-repair.xcresult` passes all five targeted UI
workflows: lane persistence/day-night, both actual ActivityKit lifecycles,
pinned/Flipped/relaunch/Portrait/Auto geometry, and shortcuts on all four main
screens. The final `/tmp/gridfix-settings-ci-final.xcresult` passes 12 related
native cases and the expanded lane workflow after applying backgrounds directly
to Form sections; it also opens/cancels the night choices and retains Every 10
min. Exported day/night settings and choice screenshots were inspected. The
native cases cover orientation masks/persistence, Live Activity consent/lifecycle
and lane backup/failure ordering. Core math is unchanged; the previous full core
and native checkpoints remain 449 and 223 (two opt-in local TAK skips).

The final phone/watch/widget simulator Release build passes in
`/tmp/gridfix-settings-ci-release.log`. The real-location feed was stopped and
cleared; the single owned phone is shut down. Other devices were untouched.

These are local repairs. They do not establish a full hosted pass or physical
locked-screen reliability. No location permissions, lifecycle/count assertions,
route-continuation assertions, or dedicated feed scenarios were removed.


## Hosted 9bb27fc diagnostics

Run 40273435731 map shard passes. Its completed field job 121411790203 fails
four UI cases: FieldExportWorkflowTests lines 17/26 (native filename replacement
and reopening the saved track), LiveActivityWorkflowTests line 12 (status reveal
at y786.7…802.4 oscillates near the helper's lower margin), and
RoutePDFWorkflowTests line 35 (native filename field not found). Library later
hit the 90-minute job limit after protected-backup filename presentation failed,
GeoJSON reported an unresponsive main thread, and the next malformed-input case
never finished. That job is cancelled by its deadline, not a passing run. No full hosted pass is claimed. The earlier lane
selection and pinned-orientation cases pass in this hosted run.

The 673 MB field artifact exceeds the connector's 512 MB download limit. It was
retrieved through gh into `/tmp/gridfix-ci90-field`, including the completed
xcresult, logs and screenshot exports. Follow-up repair will preserve file
save/reopen counts, route persistence and ActivityKit lifecycle assertions. The
local course and independent-log checkpoints remain unpushed while this run
finishes; a pass on 9bb27fc would not validate those changes.


### Follow-up from the completed run

The exported large-library failure's AX description shows the native filename
control at `{97,778.3,151,22}` under an application window at `{inf,inf,0,0}`.
Its recording visibly contains the Save as footer. The former helper rejected
this valid native control because it tested containment against that invalid
application frame. Taps now retain finite-control and hit-test checks, but use
the native element coordinate when the application origin is invalid. Files
scrolling also anchors to its collection view instead of the application origin.
A failed frame wait records a whole-display screenshot and AX/frame diagnostics,
then returns without sending a bogus tap.

The Live Activity status helper now moves toward the viewport centre with a
bounded slow drag and hold instead of full swipes that overshoot in both
directions. The complete-row visibility requirement remains. The PDF hosted
recording reaches the native save browser but its Save as footer is absent;
the PDF exporter now belongs to the presentation root outside the PDF content
and its ShareLink toolbar. The filename failure also captures the full AX tree.
Hosted confirmation of this presentation change remains required.

All six hosted XCTest commands enable per-test execution limits (300-second
default, 600-second maximum). A stuck test should produce a bounded diagnostic
failure rather than consume the whole job and prevent later cases from running.
The same UI classes, imports/exports, exact filenames, record counts and lifecycle
assertions remain; no failing workflow was excluded.

`/tmp/gridfix-ci-library-replay.xcresult` passes five workflows: protected backup
with wrong-password rejection/restore, CSV duplicate/persistence, GeoJSON native
save/reopen, malformed input/night preview, and real-location recording Live
Activity lifecycle. This includes the bounded Settings drag; it precedes the
subsequent infinite-window Files fallback and root PDF exporter changes. The
final Files replay is recorded below after completion. Six CI Python script
regressions, actionlint, YAML parsing and all 16 shell-block syntax checks pass.
The first YAML attempt used Python without PyYAML installed; the successful
check uses the system Ruby YAML parser. Final phone/watch/widget simulator
Release passes in `/tmp/gridfix-ci90-release.log`.


The final `/tmp/gridfix-ci90-files-final.xcresult` passes all five export cases:
protected backup/password failure/restore; 5,000-waypoint/1,000-graphic GPX
save/reopen; both chosen-track night exports; GeoJSON save/reopen; and route PDF
Share/Save/relaunch. The parent xcodebuild finalized with exit 0 before any next
XCTest/simulator work. This run includes the infinite-window Files fallback and
root PDF presenter. A subsequent test-build compiles the final failure-only
screenshot/AX diagnostics without repeating unchanged workflows. Exported PDF,
readable night CSV preview and visible Live Activities screenshots were inspected.
Final-hosted confirmation remains open; this is local evidence, not a claim that
the intermittent hosted PDF footer problem can no longer occur.


## Hosted 9a258c7 follow-up

Run 40295990817 completed: the whole library shard passes. Map fails only the
active-recording tool-hide switch; field reports one practice integration,
large GPX reopen and navigation Live Activity opt-in. PDF native save, track
exports and recording Activity lifecycle now pass hosted. Core tests and all
three simulator builds pass. This is still a failed overall run.

The pending-course-target integration constructed SystemNavigationFeedback on
a fresh simulator. Its final guide startup could wait for notification consent,
which this ordering test never supplies. Practice integration fixtures now use
their existing feedback double unless explicitly supplied, as the other driver/
feedback ordering tests do. The real permission workflow remains in UI tests;
no production consent or feedback logic changes. Wait failures now report their
calling test line. All 58 practice/navigation integrations pass locally in
`/tmp/gridfix-ci91-practice-native.xcresult` after that fixture correction.

The two hosted switch recordings visibly retain the old switch value after the
synthesized tap. Setting now waits for the requested value and, only when it
remains unchanged, tries the actual UIKit leaf hit point. It rechecks before
every action and stops immediately on acknowledgement, so a successful change
cannot be toggled back. Three attempts remain bounded; failure is still fatal.
The existing target values, session counts, opt-out/session continuation and
active-tool escape assertions remain. No production switch behavior changes.

The Files recording stays in its native browser after tapping `(69,291.8)`;
that point is the filename's top edge in the 118×189.7 icon cell. The helper now
opens the upper-quarter thumbnail using the cell's coordinate space and verifies
that actual point is below navigation and above the tab bar. The full 5,000-point/
1,000-graphic review counts remain required. A final replay of all three affected
UI classes is in progress; no passing result is inferred from these edits alone.


Local `/tmp/gridfix-ci91-ui-fixed.xcresult` passes all seven cases across the
three affected UI classes, including real recording/navigation ActivityKit and
active-tool escape controls. The final helper also scrolls according to its
thumbnail hit point, rather than the old text-centre point. With that final
geometry, `/tmp/gridfix-ci91-final.xcresult` passes protected backup password
failure/restore and all 58 practice/navigation integrations. All tests finished
before the owned auxiliary `simctl diagnose` child stalled; only that diagnostic
child (PID64075, parent62972) was terminated. The xcodebuild parent then finalized
successfully before the next simulator run. Test results are complete; the
supplementary diagnostic collection was shortened.

Screenshot review also exposed a production contrast issue: the daytime map's
hard-coded black foreground leaked into darkening glass buttons. Map action
rows/grids now use light symbols in a dark native glass environment; their night
palette remains red. The coordinate card retains its light surface/black text,
and the map tab bar uses the dark control scheme. The final day/night map replay
and Release build are recorded below after completion. This is a scoped control
appearance change, not a map imagery/night-model or quiet-boundary change.


Final map appearance checks pass in `/tmp/gridfix-ci91-map-contrast.xcresult`:
the existing day/night hide/reset/Go to/relaunch workflow and the actual-location
hidden-Record/Stop/discard workflow. Exported screenshots show light symbols on
dark native day glass, a readable coordinate card, and preserved red/black night
controls. Final phone/watch/widget Release passes in
`/tmp/gridfix-ci91-release.log`. No new UI class, test exclusion or permission
shortcut was added. All owned test executors finished before simulator shutdown;
the location feed was stopped/cleared. Full hosted green remains the next CI gate.

## Hosted run 40349066649: native presentation follow-up

All three UI shards on `2fdd91e` finished failed, with eight affected cases:
large GPX reopening, the track export filename field, TAK preview opening,
backup filename focus, two protected GPX workflows, navigation-lane reopening
and target-selection error presentation. Field artifact video shows two distinct
Files failures: an import picker ignores thumbnail activation, and a track
export save picker opens without a filename footer. The latter is not evidence
that the Export button was ignored. The hosted runtime is iOS 26.2; a matching
OS-version runtime is downloading for local reproduction (available build
23C52 differs from hosted 23C54).

The first local replay, `/tmp/gridfix-ci95-ack-replay.xcresult`, passes backup,
large GPX, lane, target and TAK preview cases. The combined night track case
fails during its second reopen: its new filename is absent from the virtualized
Files cells after the old 16-page traversal bound. Earlier exports remain in
this owned simulator. Native filename keyboard-focus acknowledgement worked in
this run. The next replay will exercise native Files search for the exact new
filename when it is not already exposed; no import count, protected-password or
relaunch assertions are removed. The missing filename-footer issue remains open
until reproduced or verified on the older runtime/hosted runner.

All six selected tests in the initial replay finished before Xcode's auxiliary
`simctl diagnose` child (PID73682, parent70028) stalled in the known SDK build
parsing diagnostic. Only that child was terminated; the parent then finalized
with exit 65, preserving the track-case failure. The native search repair is in
a new sequential replay, not a duplicate of the active test executor.

The search experiment (`/tmp/gridfix-ci95-files-search.xcresult`) found each new
file, but Files exposed two `File View` collections: the underlying folder and
its search-results presentation. The unscoped test query was ambiguous. The
final helper chooses the visible result collection and scopes its matching cell
to that collection. It keeps the native thumbnail activation and dismissal
acknowledgement. It does not delete prior documents or bypass the native provider.

Final `/tmp/gridfix-ci95-files-final.xcresult` passes all seven selected cases:
night backup export/delete/restore/relaunch, large GPX with all 5,000 waypoints
and 1,000 graphics, both single-track export paths, protected GPX and night KML
password retry/cancel/import/relaunch, protected single-track export and queued
incoming confirmations. Exported day/night review and restored-library screenshots
were inspected for readable content and the expected counts. Combined with the
lane, target and TAK preview passes in the initial replay, all eight hosted
failure cases now pass locally. This is not a full hosted green result.

All seven tests finished before the owned supplementary `simctl diagnose` child
(PID84152, parent78367) stalled. Only that child was terminated; the parent
finalized successfully (exit 0). Fake location/link feeders were stopped and the
simulator location override cleared. The older-runtime filename-footer gate
remains open for the iOS 26.2 replay and the next hosted run.

The same seven Files cases also pass on the newly installed iOS 26.2 arm64
runtime (23C52) at pushed head `90391ec`, in
`/tmp/gridfix-ci96-ios262-files.xcresult` (exit 0, no diagnostic interruption).
Inspected older-runtime night GPX/KML previews retain readable text and exact
record counts. The missing filename footer did not reproduce. This OS version
matches the hosted runner, but its runtime build differs from hosted 23C54 and
the local Xcode is newer; hosted run 40366024560 remains the full verification
gate. Only the new owned phone was booted after the prior phone was shut down.

## Hosted run 40366024560 on 90391ec

All three shards completed with UI failures; core484 and native259 pass. Six of
the previous eight failure cases now pass in hosted CI (backup/protected files,
TAK preview, lane reopening and target selection). Seven cases fail in this run:
large GPX export, the combined track export, PDF filename focus, favourite Name
sorting, backtrack route-card opening, repeated route waypoint generation and
lane backup export.

Field recordings distinguish a real presentation symptom from harness issues:
the large GPX Save picker opens without a filename footer, whereas the track
case has a visible, focused filename and keyboard at the helper's frame failure.
The lane backup hierarchy likewise has a Save picker but no filename field.
Selected field videos/hierarchies were fetched using ZIP byte ranges into
`/tmp/gridfix-ci96-field-ui/`; its large-file final frame is
`/tmp/gridfix-ci96-large-failure.png`. The full ZIP download was superseded;
its partial `/tmp/gridfix-ci96-field.zip` is not a complete artifact.

The production candidate registers each complete field export document in a
separate presenter before raising its presentation flag. It keeps filename/type/
bytes immutable while Files closes, instead of changing the optional document
and type from the presentation binding. This addresses a possible SwiftUI state
lifetime race; the hosted-only missing-footer cause is not proven yet. PDF's
existing fixed-document exporter stays unchanged. A real native cancellation/
repeat-export workflow has been added to validate the new presenter lifecycle.

The harness candidate uses native filename coordinates when selection menus
change, preserves keyboard-focus and exact cleared/replacement value checks,
and acknowledges sort/route-choice/route-card menu opening before continuing.
No case, assertion, content count or test shard is excluded. Local replay and
final hosted confirmation remain pending for this candidate.

The full candidate replay in `/tmp/gridfix-ci96-native-export-repair.xcresult`
passes all 268 native cases (four unstaged opt-in local skips) and all 13 selected
UI cases. This includes all seven hosted failures, protected GPX/KML retry/cancel/
import/relaunch, backup restoration and real native export cancellation followed
by another saved/reopened file. Final Release passes in
`/tmp/gridfix-ci96-native-export-release.log`. The cancellation review and night
single-track preview screenshots were inspected. The new cancellation case now
requires its exact complete fixture counts (three waypoints, one route, one
track); that strengthened assertion is being replayed separately. Hosted
confirmation of the missing-footer candidate remains open.

The strengthened native-cancel case also passes at final source in
`/tmp/gridfix-ci96-native-export-cancel-final.xcresult`: after dismissing Files
without saving, the next export reopens with all three waypoints, one route and
one track. No active test/diagnostic process was interrupted in either candidate
run; both xcodebuild parents exit 0. Fake feed/link helpers stopped, simulator
location cleared and the single owned phone was shut down before the push.

## Hosted run 97 and direct native export presentation

Run 40379715936 on 2f850c9 is terminal: map succeeds; library fails its final
post-unfavourite ordering assertion; field fails large GPX's missing native
filename footer and route PDF's filename-focus acknowledgement. Core/native
checks pass there. Full hosted green remains open.

The complete field xcresult and both failure videos were retrieved. The large
GPX video really has no filename accessory. The PDF video shows a selected name
and keyboard, but the corresponding XCTest snapshot still describes the earlier
ActivityListView/ShareSheet.RemoteContainerView and its filename query is empty.
The input helper now reasserts its foreground owner before re-resolving focus,
retaining the focus and exact cleared/replacement text assertions; a failure
also retains a screen capture and hierarchy. The library test acknowledges the
durable favourite removal and the final ordering before its original comparison.

Field exports now stage a complete file on a worker in a unique temporary
directory. A UIKit host presents UIDocumentPickerViewController directly with
that immutable source and asCopy=true. Save/cancel/interactive dismissal retains
the source through the modal lifetime, then cleans up only its directory; a
dismantled host cannot complete into a newer export. This retains the native
Files workflow and normal provider/filename choice. It replaces materialization
through the previous SwiftUI fileExporter document bridge.

An initial candidate embedded the native picker as a child of a SwiftUI sheet;
all three field-export UI cases reproduced the missing accessory locally. That
candidate's native checks, library/PDF/recording cases ran to completion; its
xcodebuild outcome is failure, not evidence of a repair. The corrected host
lets UIKit own the modal presentation. Its final replay passes all 277 native
cases (four unstaged opt-in skips) and 11 UI workflows in
`/tmp/gridfix-ci97-native-presentation.xcresult`. This includes all three hosted
failure cases, exact 5,000-waypoint/1,000-route GPX reopening, cancellation/re-export,
both single-track exports, favourite persistence/removal/order, PDF and recording.
The large GPX and exact-content cancellation review screenshots were inspected.

Seven additional UI regressions pass in
`/tmp/gridfix-ci97-native-protected.xcresult`: native backup and protected-backup
delete/restore/relaunch in night mode, hidden lane restoration into the route
card/PDF, protected GPX and night KML password retry/cancel/import/relaunch,
protected single-track export and separately confirmed queued incoming files.
Night KML review and protected-backup restoration screenshots were inspected.
Both xcodebuild parents finalize exit 0, with no diagnostic interruption.
Final Release passes in `/tmp/gridfix-ci97-native-presentation-release.log`.
No case, shard, focus check, exact content count or text-edit assertion is
removed. Full hosted confirmation of the repaired candidate remains open.


## Run 98: native editor focus and first-use keyboard

Hosted 40395046579 on d153810: map passes. Field completes 277 native cases
with no failures (four unstaged checks skipped); its 36 UI cases have three
failures: large GPX filename focus, cancellation's absent filename, and route-PDF
filename focus. Library remains in progress at this checkpoint.

Retrieved the full field xcresult and inspected screenshots plus cancellation
video. Both focus failures show the actual editor selected; the full app AX tree
contains the exact DOCPicker filename identifier with `Keyboard Focused`, even
though the leaf query's description does not acknowledge it. The first GPX
screenshot additionally shows the system keyboard's first-use slide-to-type
introduction and Continue. The later cancellation video genuinely has no footer;
it follows the failed/interrupted first export, so a clean replay is required.

The shared UI helper now handles that specific native introduction and waits
for it to dismiss. It positively checks focus on the exact filename identifier
in a freshly resolved app tree, retaining the previous focus requirement.
The existing exact clear/value, native Save, full-content reopen, cancellation,
track identity and persisted-route assertions are unchanged.

A freshly erased owned iOS 26.2 simulator passes all five FieldExport/RoutePDF
workflows in `/tmp/gridfix-ci98-fresh-files.xcresult`. The log records the actual
Continue tap before editing; large GPX reopens all 5,000 waypoints/1,000 routes,
cancellation re-exports the complete 3-waypoint/1-route/1-track fixture, and both
night single-track paths and PDF/native Save preserve their existing assertions.
Screenshots inspected. The test parent exits 0 naturally. This local Xcode 27.1,
iOS 26.2 23C52 check does not substitute for hosted Xcode 26.6 / 23C54 confirmation.


Three additional regressions pass in
`/tmp/gridfix-ci98-files-regression.xcresult`: native backup deletion/restore/night
relaunch, protected-backup wrong-password/retry/restore, and protected-KML
retry/cancel/import/night relaunch. No test or assertion is removed. The prior
final product checks remain 492 core / 283 native, all 12 selected map and
recording UI cases, and unsigned device Release; this follow-up changes only
the shared UI input helper. Full hosted confirmation remains open.

The supplementary three-case test parent finalized exit 0 after its exact owned
post-test simctl diagnostic was shortened; all cases had already finished. The
fresh five-case parent exited 0 naturally. Protected-backup restoration screenshot
was inspected. No active test was stopped or duplicated.


## Run 98 library replay and waypoint choices

The hosted library shard is terminal: 41 cases, two failures, about 60 minutes
of UI work. Favourite removal times out waiting for the star to disappear;
night search cannot find its input after tab changes. The field/map conclusions
above stand. The whole hosted run is not green.

The favourite failure reproduces locally in
`/tmp/gridfix-night-contrast-final.xcresult`. Its recording shows the actual
Remove favourite popup still open after the attempted native tap. No save action
ran; adding a longer persistence wait is not the fix. Waypoint actions now use
the existing native scrolling FieldChoiceSheet, as tracks/folders do. Choices
run after dismissal, revalidate the waypoint and preserve an explicit favourite
on/off intent. Edit, visibility, navigation, map focus and confirmed deletion
remain available. Cancellation has no queued action.

Night secondary text is brighter red on opaque black: solid-color contrast
changes from about 2.79:1 to 4.95:1. Search gets an explicit matching prompt
instead of system gray. The existing night search workflow now captures the
empty prompt, filtered results, cleared/Name-sorted results and return to day.
The first local run passes those steps plus night folder forms, recording and
TAK preview; its favourite failure is retained as diagnostic evidence, not counted
as a passing suite.

Measured run-98 UI durations are roughly library 59.9 minutes, map 37.1 and
field 36.6, excluding the dedicated location stages. The complete protected-file
class (about 7.6 minutes) moves from library to map; workers stay at three and
all cases remain. The three partition/discovery regressions pass, proving every
class still runs exactly once or in its dedicated location scenario.


Final candidate: all 283 native cases pass (four unstaged local skips), and all
17 selected library/search/folder/startup/coordinate workflows pass in
`/tmp/gridfix-waypoint-choice-final.xcresult`. After all cases finished, its exact
owned post-test diagnostic was shortened and the parent finalized exit 0.
The focused waypoint-choice walkthrough passes separately in
`/tmp/gridfix-waypoint-choice-actions-final.xcresult`: choice cancellation,
edit/save, hide/show, map focus, target navigation, cancelled deletion, confirmed
deletion and persisted absence after relaunch. Its parent exits 0 naturally.
An initial walkthrough stopped on an ambiguous Navigate label (the background
tab shares it); it now selects the sheet's existing exact action identifier.
That failed run is not counted as passing. Favourite removal also passes again
in that earlier two-case replay. Day/night choice and empty-search screenshots
were inspected. Final unsigned device Release passes in
`/tmp/gridfix-waypoint-choice-release.log`. All eight Python harness checks pass
in `/tmp/gridfix-choice-script-checks.log`. Fresh full hosted validation is next;
no old failure assertion or test was excluded.


## Hosted run 100: graphic choices and Files acknowledgements

Hosted 40422227897 on 57348f7 is terminal: map passes; library has one
backtrack route-card failure; field has four failures (large GPX reopening,
export cancellation's missing filename accessory, PDF filename focus and
recording recovery's initial nonzero-point gate). This is not a full green run.
The full library artifact was retrieved through the connector. The field
artifact exceeded its size limit and was retrieved through authenticated gh.

The backtrack video and AX hierarchy show Route card still in the visible
popup after attempted activation. Graphic rows now use the same native
scrolling choice sheet as waypoint/track rows; route presentation and
mutations wait for its dismissal and re-resolve the current graphic. Visibility
stores the explicit show/hide intent from the choice, and deletion still needs
confirmation. Cancel does nothing. A new day/night workflow covers cancellation,
hide/show, route-card presentation, cancelled deletion and durable visibility.

The PDF failure screenshot and final root hierarchy both positively show the
exact native filename editor with Keyboard Focused. A three-second waiter can
expire while the root snapshot itself is resolving. The helper retains that
exact positive focus gate, allows ten seconds and checks a final fresh snapshot
before retrying. Exact clearing/replacement assertions remain. Large GPX's
video retains the exact file in Files after ignored thumbnail-coordinate taps;
its helper now retries that same cell with UIKit's native hit point, only while
the picker remains. Filename readiness allows thirty seconds. Recording still
requires a real accepted nonzero Core Location point, allowing forty-five
seconds for a hosted simctl operation that can take twenty seconds.

Final local replay passes all ten selected UI cases in
`/tmp/mgrsgps-ci100-actions-verified.xcresult`, including every hosted100
failure and the additional day/night graphic-action, track export, night PDF,
discard and real background recording workflows. Its parent exits 0 naturally.
The host reads the actual recording journal on Home: four points become six
in the same session before foreground activation. Day/night choices, night
route card, exact 5,000-waypoint/1,000-route GPX review and readable recording
screenshots were inspected. Unsigned device Release passes in
`/tmp/mgrsgps-ci100-actions-release.log`, and all eight harness checks pass.
No core model or native integration code changed in this UI repair; the previous
496 core/309 native results remain separate evidence. Android release/1.1.0
GraphicRow exposes map focus, a route card and deletion; those actions remain
available, with explicit visibility and confirmed deletion retained on iOS.

No hosted repair is claimed from local checks alone. Full hosted101
(40429934209) on 39da6e4 is confirmed live with the preceding
certificate/branding/track-focus work; these new repairs stay local while that
run remains live. All owned simulators/emulators and feeds are off after local
checks. Physical screen-lock delivery remains separate.


## Hosted101: laid-out native export host

Hosted run 40429934209 on `39da6e4` is terminal: map passes; field has one route-PDF
filename-focus failure and library one ordinary backup filename absence. The
PDF failure's final root tree again positively identifies the exact editor as
Keyboard Focused. The previously held positive-focus/fresh-snapshot follow-up
passes locally and is still required in the next hosted run.

The full library artifact and video were retrieved. At the ordinary backup
failure, Files shows On My iPhone is Empty with a Save button and no filename
accessory, matching the absent editor in AX. The exporter was attached through
a zero-size UIViewControllerRepresentable. It now inherits its parent's viewport
in a non-interactive background; UIKit presents only after the host has appeared,
joined a window and has positive laid-out width/height. Files still owns its
modal presentation. Complete immutable staging, source lifetime, native rename,
save/cancel and generation-scoped cleanup stay unchanged. This is a candidate
layout correction, not a claim that the precise hosted OS cause is proven.

A fresh local simulator replay is in progress. Its first native suite exposes a
local harness setup issue: privacy was granted before the app's first install,
so two background-location cases fail with notDetermined and two further
location cases skip. That bundle is not a passing native result. The private
local runner now mirrors the repository CI workflow's install-before-grant
ordering. The active UI run is preserved; the required While Using assertions
will be rerun after it ends with the installed app. No permission assertion is
weakened or converted to a skip.

So far the fresh ordinary/protected full backup workflows and complete large
GPX round trip pass, with exact data and boundary assertions unchanged. Final
remaining UI, native, Release and screenshot evidence will be recorded below.


Final viewport candidate validation:

- Fresh `/tmp/mgrsgps-ci101-native-viewport-verified.xcresult` passes all 14 UI
  workflows: ordinary/protected backups and quiet-boundary restore, complete
  large GPX, native cancellation, night single-track exports, KML/KMZ/ATAK,
  protected GPX/KML/track, queued incoming confirmation and both PDF workflows.
  Its native phase has the documented two first-install permission failures;
  the bundle is an overall failure and is not reported as green.
- With the app installed before privacy grant, final
  `/tmp/mgrsgps-ci101-native-viewport-final.xcresult` executes 316 native cases,
  four unstaged opt-in skips and no failures. Both real background-driver
  checks now pass under While Using, with assertions unchanged. The same bundle
  passes ordinary backup, native PDF save and real background recording UI.
  There are 15 distinct passing UI workflows across these final candidate runs.
- The host reads the actual journal while the app is on Home: three points
  become six in the same session before foreground activation. Recording,
  ordinary/protected restored-library, exact large-GPX review and saved-PDF
  screenshots were inspected. Both parents finish naturally (initial 65 because
  of the native setup failures; final 0).
- Device Release passes `/tmp/mgrsgps-ci101-native-viewport-release.log` and all
  eight harness checks pass. The 504 core and 39 Wear test results belong to the
  preceding unchanged model/watch code and remain separate evidence.
- Pushed `7b36a5d` includes the earlier graphic/backtrack/watch follow-ups and this
  native presenter. Full hosted run 102 (40438839779) is confirmed live on that head
  with all three jobs active; full hosted green remains open. Evidence-only
  documentation follows locally until it finishes, without cancelling the run.
  The one owned test phone and fake feeds are off after checks. No server,
  credential, container or database changes.


## Hosted 102: five UI failures, October 27

Run `40438839779` on `7b36a5d` is fully terminal; all three shards fail.
The five failing cases are:

- Library: ordinary backup export filename (`BackupWorkflowTests.swift:17`)
  and protected backup filename (`:72`).
- Map: protected GPX filename (`ProtectedFileWorkflowTests.swift:26`) and
  decimal Go-to activation (`MapToolWorkflowTests`).
- Field: navigation target activation after actual fix expiry/recovery
  (`PositionFixWorkflowTests.swift:45`). The fresh/stale/recovery assertions
  have passed; the missing heading readout follows target selection.

Both route-PDF cases pass this run. The exporter viewport candidate does not
resolve all Files naming failures. In the protected-GPX hierarchy the native
Save button exists but the filename accessory does not. In the Go-to failure
hierarchy MGRS remains selected and its grid field is still present after the
attempted Lat/Lon switch. The fix-recovery failure hierarchy retains the
Alpha/Bravo/Charlie popup and the underlying empty-target prompt after the
attempted Alpha action. These are concrete activation/presentation failures;
no assertion has been weakened or mislabeled as a full hosted pass.

Field artifact `12707188391` and map artifact `12707107940` are downloaded to
`/tmp/mgrsgps-ci102-field` and `/tmp/mgrsgps-ci102-map`; library logs are read.
The next work is these iOS activation/Files failures. The watch follow-ups
`12bcbf2` and `03d51c6`, and evidence `44057c7`, remain local pending that
consolidated correction; no redundant known-failing hosted run is started.


## Hosted 102 follow-up candidate: settled Files and target choices

The native export host now waits for its own attached viewport and for its
UIViewController owner to have no presented controller or active transition.
It presents the same complete staged copy with UIKit full-screen presentation,
rather than beginning an adaptive save sheet while another sheet may be closing.
The wait is cancellable and bounded at 30 seconds, with an explicit retry error;
parent removal cancels it. File lifetime, independent staging directories,
exact filename edits, native Save/cancel and content checks remain. This uses
Apple's public [document export API](https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller).
No private Files views, app Documents exposure or replacement filename form is
introduced. The precise hosted footer cause remains unproven until a full
hosted run confirms the candidate.

Navigation target selection uses the existing native scrolling choice sheet
instead of the popup left open in the failed hierarchy. A choice is applied
after dismissal, rechecking course lock, in-flight mutation and current
waypoint identity; Cancel leaves the saved target intact. Durable selection
and visible failure/rollback stay in the existing worker-staged action.
Android's NavigateScreen target selector also shows military glyphs: the
chooser and selected-target header now render the actual symbol, affiliation,
echelon, rotation and imported metadata. Choice rows expose a symbol value
and selected accessibility trait. Grouped written MGRS replaces the compact
machine string in the target header, retaining the iOS precision preference.
Android currently asks for eight digits on that secondary line; this is a
native presentation difference, not an iOS restriction.

Go-to's test now uses the existing native segment helper and requires the
segment's selected state before editing its actual decimal fields. It still
checks invalid latitude, exact entry, camera movement and no navigation or
recording side effect. The coordinate parser and all filename/content
assertions are unchanged.

Local evidence on a freshly erased owned iOS 26.2 simulator (23C52, Xcode 27.1):

- `/tmp/mgrsgps-ci102-controls-files.xcresult`: 11 export integration cases
  and 11 UI workflows pass, parent exit 0 naturally. This includes the four
  hosted backup/protected-GPX/Go-to failures, complete large GPX, cancel/re-export,
  nested track-detail export, target rollback/cancel/persistence and PDF save.
- `/tmp/mgrsgps-ci102-target-symbols.xcresult`: all four target UI workflows
  pass after military glyph/VoiceOver additions. Night chooser/header images
  are inspected.
- `/tmp/mgrsgps-ci102-freshness.xcresult`: actual CoreLocation feed stops after
  observed fresh fix, assertions observe expiry/stale retention, feed resumes
  only after the test's signal, then target selection completes and heading
  remains unavailable rather than synthesizing north. Parent exit 0; READY,
  RESUME and DONE receipts are in the matching log, with phase evidence in
  `-feed.log`. This covers the fifth hosted failure.
- `/tmp/mgrsgps-ci102-target-grid-final.xcresult`: grouped target-grid UI check
  passes. Android's cached NGA MGRS 2.1.3 independently returns
  `40RBN3422807099` for the synthetic point 24.4548,54.3783; the UI shows
  `40R BN 34228 07099`. The first new expected string had a transcribed
  easting typo; it is corrected against that independent reference, not by
  weakening the exact assertion. Reference log:
  `/tmp/mgrsgps-ci102-android-target-grid-reference.log`.
- These follow-ups cover 13 distinct UI workflows across the separate runs;
  repeated target cases are not counted twice. No claim that they are one
  final all-test bundle is made.
- Final unsigned device Release passes in
  `/tmp/mgrsgps-ci102-final-release.log`. Eight Python harness checks pass in
  `/tmp/mgrsgps-ci102-controls-harness.log`. Private local runners skip only
  verbose sysdiagnose collection after an assertion; tests, failure artifacts,
  screenshots and checks remain. Repository CI settings are unchanged.

Screenshots inspected include the actual protected-backup native filename bar
(`controls-files-images/1CFD4CAA-E554-4634-A3AB-F771F3D25BA5.png`), restored
night backups, decimal Go-to, military choice/header, and final grouped grid
(`target-grid-final-images/C197479B-91A6-48EA-896F-779BE0466BA7.png`), all under
`/tmp/mgrsgps-ci102-`. The owned simulator and fake feeds are shut down.

Hosted 102 instead uses Xcode 26.6 (17F113), iOS 26.2 build 23C54; local evidence
does not close that toolchain/runtime gate. The consolidated follow-up needs
a new full hosted run. Physical Files providers, iPad presentation, dense
target-list ergonomics and imported-marker VoiceOver descriptions remain
checks/work. No TAK server, identity or credential is changed.
