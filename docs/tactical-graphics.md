# Map graphics and route drawing

Reference: Android `release/1.1.0`, commit `482b417`, specifically
`GraphicsRepository.kt`, `ControlMeasuresOverlay.kt` and `ui/screens/MapScreen.kt`.

Open the map's pencil button, choose a graphic type and tap to place vertices.
The map draws straight segments. Long-press and drag a numbered point to move
it, or drag a small + handle along a segment to add a new point and bend the
line. Tapping a + handle inserts a point there. Select a point for the crosshair
Move here, Add point and remove actions; Add point inserts after the selection. Save commits the drawing
atomically; Cancel restores the saved version. Name, folder, affiliation and
record visibility live in Details, with echelon selection for tactical boundaries.
Rings, sectors and single-point graphics automatically open Details once their
fixed number of points has been placed, matching Android's completion prompt.

The saved graphics panel supports show, edit, visibility and confirmed deletion.
Visible graphics also open their map editor when tapped near an edge or point.
Folder visibility and graphic visibility both control saved overlays. Hidden
records can still be edited from the panel. Drawing edits remain a preview until
Save; they do not publish intermediate positions into an active navigation route.

## Android drawing set

All 30 Android types use their own control-measure presentation:

| Presentation | Types |
| --- | --- |
| Open line, labels at both ends | Phase line |
| Open line with echelon size mark | Tactical boundary |
| Broad outlined arrow, open rear, bends along shaft | Axis of advance |
| Line with terminal solid arrow | Direction of attack |
| Filled, closed outline with doctrine label prefix | Objective, assembly area, landing zone, pickup zone, battle position, engagement area, NAI, TAI, sketch area |
| Numbered legs and vertex marks | Route |
| Boxed S/G/C and arrows outward at both ends | Screen, guard, cover lines |
| Left-facing scallops along drawing direction | FLOT |
| Left-facing teeth, wire crosses, parallel sides | Obstacle line, wire obstacle, cleared lane |
| Closed outline with mine marks or outward teeth | Minefield, strongpoint |
| Six-armed mark | Roadblock |
| Centre cross and radius label | Range ring: centre and edge |
| Clockwise wedge at maximum limit radius | Sector of fire: apex, left limit, right limit |
| Cross, pennant, star, native text | Target reference point, checkpoint, decision point, text label |

Affiliation colors, two-tone red night rendering and hostile `ENY` labels follow
Android. Labels paint a halo and then their ink separately to keep text legible.
The canvas redraws during camera movement and sits above the raster basemap and
below native waypoint/edit handles. The map stays flat, matching Android's 2D
field map. Adjacent dateline vertices unwrap into the same nearby world copy.
Rings and sectors use their enclosing circle when fitting the camera.

The renderer keeps imported vertices beyond Android's 64-point drawing cap.
Interactive creation allows up to 4,096 vertices, with fixed counts for the
seven fixed-placement types. Imported drawings with more vertices retain all
coordinates and can be moved/deleted, though further insertion requires being
below the creation cap. Obstacle decorations retain continuous spacing but skip
work outside the visible viewport, so zooming into a very long line does not
walk millions of invisible teeth or crosses.

## Routes and navigation

Route taps snap to the nearest visible waypoint within 30 screen points,
including tapping its native map marker. Other graphic types do not snap.
A newly saved route offers to generate stable route-owned navigation waypoints.
The saved route's card and automatic-follow controls are available from the
panel as well as Routes & tracks. Route edits retain the original ID, creation
time, folder, affiliation, echelon and visibility. Existing automatic-follow
safety rules pause if the saved route or its generated waypoints change.

A tactical boundary is an **open control-measure line**. It never starts a
monitoring session or sends alerts. Quiet-inside permitted perimeters, backstops
and handrails remain in the shield panel with separate geometry, persistence,
background GPS and crossing policy. Security lines are also visual graphics.

## Verification and remaining work

Core tests cover every type's placement rules, fixed counts, kinks and coordinate
changes, persistent route identity/metadata, invalid points and dateline circle
bounds. Native tests render all 30 types into day/night contact sheets, exercise
long routes beyond 64 points and bound off-screen obstacle work. UI workflows
exercise map drawing, midpoint-handle insertion/dragging, save/edit/relaunch, ring/sector
completion, route snapping and generation, and isolation from boundary alerts.

The ruler/area-measure mode, terrain readouts, profiles, line-of-sight and viewshed
are separate remaining tools. This milestone does not implement those tools.
Physical outdoor readability and large field-library performance still need a
device check; neither is a claim that missing tools are restricted by iOS.
