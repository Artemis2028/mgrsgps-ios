# Marker descriptions follow the visible artwork

The imported MilGPS marker overrides a waypoint's fallback symbol in Android
`release/1.1.0` (`482b417`) and in the existing iOS renderer. Android's
`app/src/main/java/app/gridfix/android/ui/MilGpsMarker.kt` describes that imported
shape and character. iOS target choices previously described only the hidden
fallback, so a cyan circle with `6` could be announced as a flag. The shared
`WaypointMarkerDescription` now follows the same precedence.

Valid imported shapes announce shape/character/marker and omit the hidden
fallback, affiliation frame and echelon. Exclamation/question marks use spoken
names so punctuation settings do not erase their meaning. Invalid imported
codes fall back to the actual base symbol. NATO affiliation comes from its
catalog key; an inconsistent legacy affiliation field does not add a second
contradictory frame. Echelons are described for unit/basic markers, while task
paths omit the echelon they do not draw. Unknown keys stay explicitly
unrecognized rather than masquerading as a known flag.

The shared description is used by the iOS native target chooser, target header
image, map annotation value and library edit row; names/grids/selection state
remain separate. MapLibre exposes the annotation title as its accessibility
label, so the imported example's map label is `IMPORTED` and its selected value
is `Circle 6 marker, Navigation target`. The watchOS map marker and its scene
information list use the same core helper with the actual received metadata.
No artwork, saved metadata, wire fields or selection behavior changes.

## Validation

- `/tmp/mgrsgps-marker-descriptions-core-final.log`: all 509 core tests pass.
  New cases cover all 157 supported imported shape/character combinations,
  all 496 unit keys across the available echelons, basic frames, task paths,
  invalid codes, explicit unknown keys and actual phone/watch snapshot encoding
  and replacement. The earlier 508-case run also passes; the final run adds
  the snapshot round trip and supersedes that count.
- The initial new UI locator incorrectly assumed MapLibre retained the wrapper's
  `Waypoint IMPORTED` label. The failed bundle
  `/tmp/mgrsgps-marker-descriptions-ui.xcresult` and focused diagnostic
  `/tmp/mgrsgps-marker-descriptions-map-diagnostic.xcresult` are kept. The actual
  hierarchy and screenshot show the existing circle/6, exact `IMPORTED` title
  and correct value; the test now requires that native label and the unchanged
  exact description/selection value. No production workaround or relaxed symbol
  assertion was added for that fixture mistake.
- `/tmp/mgrsgps-marker-descriptions-final.xcresult`: seven native rendering
  checks and all five target UI workflows pass. The new workflow requires exact
  descriptions in chooser/header/map/library in both day and night; existing
  target selection/cancel/relaunch, military glyphs and failed-save retention
  cases remain green. Day map and night chooser/header/map screenshots were
  inspected. The final parent exits naturally with 0; the two earlier failed
  fixture bundles remain failed and are not counted as passes.
- Eight Python harness checks pass in
  `/tmp/mgrsgps-marker-descriptions-harness.log`. Unsigned device Release also passes for phone, watch and widget in
  `/tmp/mgrsgps-marker-descriptions-release.log`, natural parent exit 0. The
  owned simulator is shut down and no fake feed ran for these symbol checks. No paired-watch or physical VoiceOver runtime
  result is claimed by these iOS UI cases.

This verifies native accessibility values, not a person navigating with
VoiceOver on a physical phone/watch. Spoken pronunciation, focus order, large
text, watch map browsing and wrist interaction still need those checks. Dense
map/library accessibility performance remains a separate gate. Independent watch
alerts/background guidance and offline-pack/terrain transfer remain implementation
work. Wear OS source is unchanged by this Swift description follow-up.
