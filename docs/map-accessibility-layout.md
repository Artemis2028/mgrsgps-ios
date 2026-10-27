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
have explicit sizes while its status text continues scaling. The implementation
does not cap text scaling globally or substitute a DEBUG-only text setting.

## Validation in progress

`MapAccessibilityWorkflowTests` launches with the actual global
`UICTContentSizeCategoryAccessibilityXXXL` setting. It exercises day/night details
and layers, landscape field-tool/reference navigation, ruler/boundary exit and
live-recording finish controls. It does not use the isolated reference-only flag.

Intermediate bundles are retained in `/tmp/mgrsgps-accessible-map-global*`.
The portrait day/night case and all three ordinary map-tool workflows pass.
The first two development bundles fail because scrolling stops on partially
visible rows or scrolls past them; final assertions still require complete
viewport bounds. The third bundle's landscape test also fails to find the
overshot field-tool row. The final-source run is
`/tmp/mgrsgps-accessible-map-complete.xcresult`; its outcome must be checked before
claiming this milestone validated.

The earlier device Release build and eight harness checks pass. Final-source
Release is `/tmp/mgrsgps-accessible-map-release-final.log`.
Full-app Dynamic Type, spoken VoiceOver, physical drawing/GPS/locked-screen cues,
independent watch guidance and real enrolled TAK exchange remain separate gates.
