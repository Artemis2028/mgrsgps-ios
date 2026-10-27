# Map layout at accessibility text sizes

MGRS GPS previously placed the complete map HUD alongside two fixed columns of
icons. With the system's largest text size, text and symbols escaped the viewport.
This is an application layout defect, not an iOS limitation.

At accessibility sizes the map now shows its full selected-precision centre grid,
offline status and a Map actions button. All controls are in a native scrolling
list with wrapping labels. The centre card opens scrolling details containing
the grid interval, layer, available terrain information, overlay status and retry,
TAK access, decimal coordinates and attribution. Attribution's native SDK action
and logo remain visible on the map; its icon has an explicit symbol size.

Landscape puts the centre summary alongside actions. While a tool or selected
waypoint panel is open, landscape leaves the actions button above the map;
centre details remain available from that list. Tool panels have their own
bounded scrolling region. Boundary, graphic, lane, ruler and area rows stack at
accessibility sizes. Lane role selection becomes a native menu. Ordinary-size
layouts, drawing geometry, monitoring and navigation policy are preserved.

Hidden-tool preferences still apply, including active-tool escape controls.
Recording uses the same start policy and recording panel. Recording-banner icons
have explicit sizes while its status text continues scaling. Boundary-name entry
has a native keyboard Done action, and the panel supports interactive keyboard
dismissal while scrolling. The implementation
does not cap text scaling globally or substitute a DEBUG-only text setting.

## Local validation

`MapAccessibilityWorkflowTests` launches with the actual global
`UICTContentSizeCategoryAccessibilityXXXL` setting. It exercises day/night details
and layers, landscape field-tool/reference navigation, ruler/boundary exit and
live-recording finish controls. It does not use the isolated reference-only flag.

Intermediate bundles are retained in `/tmp/mgrsgps-accessible-map-global*`.
The portrait day/night case and all three ordinary map-tool workflows pass.
The first two development bundles fail because scrolling stops on partially
visible rows or scrolls past them; final assertions still require complete
viewport bounds. The third bundle's landscape test also fails to find the
overshot field-tool row. The final-source bundle `/tmp/mgrsgps-accessible-map-complete.xcresult` passes
346 native cases (four opt-in skips), route draw/edit/save/relaunch, global
largest-type day/night details/layers, landscape field-tool/reference navigation
and live-recording finish/discard. Its boundary case fails waiting for a
virtualized Draw boundary row before scrolling. The corrected test scrolls that
real list and `/tmp/mgrsgps-accessible-map-boundary-final.xcresult` passes.
Across these and the preceding ordinary map-tool bundle, eight distinct UI
workflows pass; repeated runs are not added together.

Final-source phone/watch/widget unsigned device Release and eight harness checks
pass (`/tmp/mgrsgps-accessible-map-keyboard-release.log`,
`/tmp/mgrsgps-accessible-map-harness.log`). Portrait day/night and recording
screenshots are inspected. App-region landscape captures on this simulator have
incorrect portrait cropping/rotation metadata. Display-level recapture in
`/tmp/mgrsgps-accessible-map-landscape-display.xcresult` passes both landscape
cases; full-display map screenshots are inspected. The original artifacts remain
untouched. A stronger full-panel-button assertion exposes a focused name field
shrinking the panel below a complete button height. The native keyboard Done
action and interactive scroll dismissal fix that exit path.
`/tmp/mgrsgps-accessible-map-keyboard-final.xcresult` types a boundary name,
dismisses the actual keyboard, scrolls until Cancel is wholly inside the panel,
and cancels successfully. Its full-display screenshot is inspected. The stricter
intermediate failure is `/tmp/mgrsgps-accessible-map-full-panel.xcresult`.
All local parents finish naturally; the owned simulator and fake feed are off.
Full-app Dynamic Type, spoken VoiceOver, physical drawing/GPS/locked-screen cues,
independent watch guidance and real enrolled TAK exchange remain separate gates.
