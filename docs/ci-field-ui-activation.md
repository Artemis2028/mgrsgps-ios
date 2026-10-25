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
All 40 current UI classes are accounted for: 35 assigned exactly once and five
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
