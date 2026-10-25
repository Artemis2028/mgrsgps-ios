# Map-tool visibility

Reference: Android `claude/hide-map-buttons` at `4c8216d`,
`SettingsRepository.MapTools`, its tests and map deck filtering. Settings →
Map buttons, or the map's always-available slider button, opens the seven
switches: Layers, Locate, Ruler, Draw, Go to, Tools and Record. Show all map
buttons resets only these preferences. Night and button settings remain
reachable when everything else is hidden; Add and Show all visible data are
independent iOS controls.

The same Android keys are stored in the same ordered comma-separated
`hiddenMapTools` backup setting. Unknown keys are dropped on decode/encode;
missing settings default to all shown. Local JSON persists the string as an
optional field so earlier settings files still load. Both ordinary and protected
backups share this setting. The worker-prepared settings restore captures it;
a concurrent preference edit invalidates a stale prepared settings publication.

## iOS grouping and active controls

- Layers controls the raster/offline layers button.
- Locate controls current-location recentering.
- Ruler controls a new direct start/close ruler button. Distance measurement
  also remains available in the field-tools chooser, as hiding is a map-button
  preference rather than removing the underlying feature.
- Draw controls graphic/route, navigation-lane and quiet-inside-boundary library
  buttons together. Their separate editing/monitoring behavior is unchanged.
- Go to controls a new map-coordinate entry button.
- Tools controls the measurement/field-tools chooser and terrain-visibility
  button together.
- Record controls the map recording button.

Hidden modes remain active until explicitly finished/canceled. An active ruler,
drawing, temporary area measurement/viewshed, or recording adds its group back
to the visible policy. While a drawing owns the map, its dedicated finish/cancel
panel takes precedence over opening a new measurement chooser. Existing editor Cancel/Done controls and the global
recording banner remain independent of hiding. Recovering, permission-waiting,
saving and failed/recoverable recordings also retain recording access. This
avoids hiding a user's route out of a session. Hiding Draw does not stop lane
navigation or quiet-inside boundary monitoring, and no preference starts either.

Portrait uses two columns wide enough for the complete glass/capsule button
bounds. Compact landscape scrolls the shared controls horizontally, keeping
individual targets at their native size. The map HUD and drawing finish panels
remain separate from that tool layout.

## Go to and ruler

Go to reuses the validated waypoint coordinate draft/parser, accepts a full
MGRS/USNG grid or decimal latitude/longitude and prefills the centre's zone and
100 km square. Entries with invalid ranges or uneven grid digits cannot apply. Decimal positions
beyond the existing map projection's ±85.05112878° coverage show an explicit
message instead of silently moving to a clamped latitude.
Showing a coordinate moves only the map: it does not add/select a waypoint,
start recording, navigate or monitor a boundary. As in Android, a map wider
than zoom 14 goes to zoom 15; an already close zoom is preserved. The native
Go to panel adds latitude/longitude entry alongside Android's grid workflow.
Ruler uses the existing anchor/crosshair calculation and existing north/unit
preferences; closing it stops only measurement.

## Validation

Core tests cover Android key order, unknown-key filtering, legacy/default
settings, JSON/ZIP compatibility and active-mode visibility. App integration
reopens local preferences, restores them through the ordered backup coordinator,
resets them without changing other settings and rejects stale prepared settings
after a concurrent tool edit. Native workflows cover actual switches and their
resulting map controls, relaunch/reset, grid entry and map movement, hidden active
ruler/drawing and recording access. Existing measurement/route drawing workflows
are included as regressions. Physical small-screen/dynamic-text and field touch
checks remain required; watch companions have their own map controls.

## Results

All 355 core tests and 149 app integration cases pass locally. The latter
include preference reopen/reset, Android-compatible backup restore and rejection
of a prepared settings publication after a concurrent map-tool edit. The first
native preference attempts did not activate the full-row switches; the helper
now taps the actual knob and verifies each resulting value before continuing.
Existing measurement cases passed in that initial run.

The closed `gridfix-map-tools-native-final.xcresult` passes eight native cases
with zero failures/skips: three new map-tool workflows, the existing route
bend/drag/save/edit/relaunch workflow and all four measurement workflows.
These verify hiding all seven groups, relaunch/reset, grid Go to, keeping hidden
active ruler/drawing finish controls reachable, and keeping Stop accessible
when Record is hidden during actual recording. Day/night settings and maps,
active recording and compact landscape measurement screenshots were inspected.

The subsequent clean `gridfix-map-goto-decimal.xcresult` passes both settings
integration cases and the expanded native preference/Go to case (three passes).
It additionally rejects decimal positions outside the existing Web Mercator map
coverage and accepts a normal decimal position, with a corresponding camera
move. The decimal-entry night screenshot was inspected. The final unsigned
phone/embedded-watch Release build passes. The source-less invalid-frame runtime
warning recorded during protected-backup validation is still present; no new
platform limitation is inferred. Physical small-screen/dynamic-text/touch and
full hosted CI remain separate gates. 
