# Military symbols

The native picker contains the full curated catalog shipped by Android
`release/1.1.0` at `482b417`: 124 unit functions in friendly, hostile, neutral
and unknown affiliations (496 unit PNGs), 20 mission tasks and 15 basic markers.
This matches the app catalog; it does not claim every symbol in MIL-STD-2525.

## Editing and display

Add or edit a waypoint, then open **Military symbols** in the Symbol & unit
section. Search by function or key, select Units, Tasks or Basic, and choose
an affiliation. The editor supports all Android echelon indicators from team
through army, unit designation, waypoint/unit record type and directional task
rotation. Changing a unit's affiliation selects the corresponding unit image.
The library, picker preview and map use the same renderer. The map moon button
uses the shared night setting so the tab bar also switches to the opaque red
field controls, instead of leaving bright native navigation under a red map.
Night map buttons have opaque black surfaces and reserve space above the field
tab bar, keeping their labels visible and actions reachable. Saved values survive
relaunch and remain compatible with the Android backup contract.

Imported MilGPS marker metadata retains its color, shape and character until
explicitly replaced. Its controls support the Android cross, circle, triangle,
square and star appearances. Unsupported symbol codes and unknown native keys
remain preserved; an unknown native key displays a question marker rather than
silently becoming a flag.

## Source fidelity

`scripts/ImportAndroidSymbols.py` imports exact PNG bytes, catalog labels, the
upstream MIT license and Android's SIDC manifest from a Git ref in the sibling
Android checkout. `App/Resources/MilitarySymbols/military-symbol-manifest.json`
records the full upstream commit and SHA-256 digest for every PNG. The raw
resource folder deliberately bypasses Xcode PNG optimization, so built resources
can be checked against the source digests.

At runtime, pixels with all RGB channels below 40 become transparent, matching
Android. Night unit images use Android's red-channel transform with preserved
alpha. Tactical task geometry, arrowheads, rotations, affiliation colors and
echelon marks are ported from Android's `WaypointMarker.kt`; basic platform
pictograms use native SF Symbols. MilGPS characters remain black on colored
shapes for contrast. Unit designation remains record metadata, as before.

Tests check all 496 built-image digests and decodes, day/night transparency,
unique task artwork, task rotation, echelon differences, imported character
contrast and unknown-key preservation. A UI workflow searches an extended unit,
sets its echelon, saves and relaunches, then renders it on the day/night map.
Contact-sheet attachments cover the tasks, basic markers, affiliations and
all echelon indicators. Tactical *map control measures* and their drawing tools
are a separate remaining milestone.
