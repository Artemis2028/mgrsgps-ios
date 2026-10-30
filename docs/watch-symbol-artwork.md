# watchOS military marker artwork

Android reference: `release/1.1.0` (`482b417`),
`app/src/main/java/app/gridfix/android/ui/WaypointMarker.kt` and
`WaypointSymbols.kt`. Android draws task paths on their own, rotates directional
tasks, leaves S/G/C text badges upright and adds affiliation frames to ordinary
markers. Its 496 unit PNGs are already bundled unchanged on both Apple targets.

The watch previously used a separate PNG loader, SF basic glyphs without the
phone affiliation frame and rotated task-name badges. It now compiles the same
`App/Sources/MilitarySymbolArtwork.swift` as iOS. The phone SwiftUI wrapper stays
in `MilitaryMarkerRenderer.swift`; no phone theme or view environment is needed
by the shared artwork. Both render all 20 task symbols, echelon marks, affiliation
frames and MilGPS shape/character/color metadata. Names stay outside the image
and upright. Directional rotation is normalized before multiplying by pi,
including finite extreme values; S/G/C remain upright as on Android.

`UIGraphicsImageRenderer` is unavailable on watchOS. The watch uses an explicit
128×128 RGBA CoreGraphics context with the same 64 pt, top-left,2× drawing space
and a UIKit pushed context for text/images. iOS retains its native image
renderer. Watch image/asset caches are limited to 4 MiB and 128 entries; the phone
retains its existing 16 MiB cache. Snapshot validation/budgets, visibility and
WatchConnectivity transport are unchanged. Watch red uses Android's explicit
FF3B30; native utility SF icons retain their system shapes and can rasterize
differently from the iOS image-renderer context or Android Material icons.
This is shared military artwork, not a promise of identical system-icon pixels.

## Validation

Seven native military-symbol cases pass in the first corrected adapter run:
all 496 resource hashes, asset alpha/night transforms, all 20 distinct task
artworks in both drawing contexts, rotation/echelons/imported character behavior,
unknown-symbol distinction and catalog attachments. Exact alpha coverage checks
compare the phone and bitmap contexts for every task plus selected NATO/basic
geometry; the imported numbered triangle is RGBA-identical. Initial exact
fallback-system-icon alpha comparison failed because that UIKit rasterization
is context-dependent; that icon is verified as distinct from a flag and
visually inspected rather than described as pixel-identical. The final
follow-up additionally checks wrapped/negative/extreme finite rotation.

Actual paired 40 mm Apple Watch SE simulator delivery (revision 94) contains exactly
six visible markers from the isolated phone fixture: SBF 90°, Ambush 0°, Screen 90°,
hostile diamond, friendly infantry/platoon and imported cyan circle 6. The
distant synthetic rally is hidden. No watch cache or decision is injected.
Screenshots show the SBF arrow pointing right, the upright S, actual ambush
curve/teeth, hostile diamond frame, platoon dots and black imported 6 in both
day and night. Map controls/Apple attribution remain visible. This check has
no fresh watch fix and does not claim GPS, compass, touch or haptic validation.

Local evidence:
- `/tmp/mgrsgps-watch-symbol-native-final.xcresult` (7 cases, 0 failures).
- `/tmp/mgrsgps-watch-symbol-images/` (day/night phone and bitmap contact sheets, inspected).
- `/tmp/mgrsgps-watch-symbol-delivered-map-final.json` (actual received revision 94).
- `/tmp/mgrsgps-watch-symbol-final-day.png` and `-final-night.png` (inspected).
- `/tmp/mgrsgps-watch-symbol-regression.xcresult`: final seven native cases plus
  the phone edit/save/relaunch/map/night UI workflow pass, parent exit 0 naturally.
  Attachments are in `/tmp/mgrsgps-watch-symbol-regression-images/`.
- `/tmp/mgrsgps-watch-symbol-release-final.log`: unsigned device Release build,
  including the watchOS device target, succeeds. The paired simulator Debug
  build also succeeds in `/tmp/mgrsgps-watch-symbol-paired-build.log`.

The isolated phone workspace is backed up/restored, and existing local watch
precision/night overrides are retained (10 digits/night). Reinstall changes the
simulator data-container UUID: restoration resolves the current container again,
then actual WatchConnectivity revision 97 replaces the six-marker fixture with
the prior visible SYNTHETIC INF scene. The restored receipt is in
`/tmp/mgrsgps-watch-symbol-restored-map.json`. All owned devices and feeds are
off after the checks. Only the owned phone/watch pair is used
for delivery; the CI test phone is off during paired checks. No Android process,
TAK server, key, credential or real location is involved.

## Still missing

The subsequent [tactical drawing milestone](watch-tactical-graphics.md) closes
the decorative path/area rendering gap. MGRS grid/terrain/contours/viewshed
layers, custom tiles/offline-pack transfer and
independent watch boundary/haptic/background guidance remain implementation
gaps. Physical wrist/touch readability, radio, battery and resource-pressure
checks remain open. The broader iOS parity goal and real enrolled TAK gate
remain active.
