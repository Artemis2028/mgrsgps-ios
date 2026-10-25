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
