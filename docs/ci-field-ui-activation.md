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
