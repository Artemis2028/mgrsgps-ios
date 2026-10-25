# GridFix for Apple Watch

Native SwiftUI companion, watchOS 10+. Swipe between **Position**, **Navigate** and **Map**. Selecting Map opens a full-screen map cover outside the page pager, so map pan/zoom gestures do not compete with page swipes. Native close returns to the Map launcher; its Open map button reopens the cover.

Position is a fixed instrument: zone, easting and northing fit together on the 40mm display. The right-side **FORMAT** button cycles **4D → 6D → 8D → 10D**, saving a local format override; **PHONE** resumes the latest synced phone precision. GPS accuracy (± metres) and age appear separately at the top: ten-digit formatting never claims one-metre GPS accuracy. Tap the zone / ⓘ row for connection/cache diagnostics and night controls. These secondary details scroll in a sheet; the primary grid does not scroll. Instrument numerals dominate the screen: approximately 48 pt Antonio for five-digit rows on 40mm and about 51 pt for shorter rows at default text size. CoreText measures the bundled digit ink bounds so unused ascender/descender space can be removed while rounded digit tops/bottoms remain intact. Width/height constraints adapt the size for large labels; the FORMAT tap target remains 44×44 pt. Labels adapt to text size. Unavailable-fix em dashes use ordinary text layout, independent of digit trimming.
Position uses the Android Glance font assets (Antonio bold/Fira Mono/Saira Semi Condensed) and bone/amber/lume palette. Phone night mode turns the app content red on black. Position details and Navigate also offer a local Night mode toggle for disconnected use; Follow phone night mode removes that persistent local override. The system watch clock and system UI follow watchOS appearance; the app cannot promise that every system surface becomes red.

## Build

From the repository root, run `xcodegen generate`, then:

```sh
xcodebuild -project MGRSGPS.xcodeproj -scheme GridFixWatch \
  -destination 'generic/platform=watchOS Simulator' \
  -derivedDataPath /tmp/gridfix-watch-derived CODE_SIGNING_ALLOWED=NO build
xcodebuild -project MGRSGPS.xcodeproj -scheme GridFixWatch \
  -destination 'generic/platform=watchOS' \
  -derivedDataPath /tmp/gridfix-watch-device-derived CODE_SIGNING_ALLOWED=NO build
xcodebuild -project MGRSGPS.xcodeproj -scheme MGRSGPS \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/gridfix-phone-watch-derived CODE_SIGNING_ALLOWED=NO build
swift test --package-path GridFixCore --filter WatchSnapshotTests
```

Do not pass a global `-sdk iphonesimulator` when building the phone scheme: that overrides the embedded watch target's SDK too. Signing and an Apple development team are needed for installation on real devices. The phone bundle embeds the watch app; the watch app may run independently after installation. This is Apple watchOS, separate from Google's Wear OS app.

## Location and navigation

Only when-in-use location permission is requested. The watch starts its own CoreLocation foreground session when active and stops when inactive/backgrounded. There are no workout/background modes, route logging, complications, notifications or haptic guidance. Apple may provide assisted location through the paired system; “Watch location” identifies the app's CoreLocation session, not a claim of independent satellite hardware reception.

The displayed grid and navigation numbers require current location authorization, precise location, finite nonnegative accuracy ≤25 m and finite fix age ≤10 seconds. Revoking authorization immediately stops acquisition and clears the retained fix. A fresh fix outside the core’s -80…84° MGRS coverage is labeled OUTSIDE MGRS COVERAGE. Receipt age is anchored to system uptime so a clock adjustment cannot revive an expired fix. Invalid/stale fixes suppress grid/bearing/distance rather than present them as current; the last reported accuracy and age remain visible. At the target's uncertainty radius, the app replaces bearing with “Within fix uncertainty.” Distances use shared Vincenty math and phone units. Bearings show TRUE, MAG or GRID explicitly; magnetic uses the phone's manual override or a valid bundled WMM. Expired/missing models suppress magnetic bearings.

The first version deliberately displays numeric bearing to the waypoint. It does not rotate a target arrow or claim a compass heading. Apple Watch heading availability varies with hardware and simulator; compass and haptic behavior require paired-device testing before future guidance features.

## Phone → watch contract

`WatchSnapshot` in GridFixCore is versioned, Codable and validated before application. The phone observes waypoint/settings changes and sends a **complete latest application context**, which WatchConnectivity coalesces while offline. Every snapshot includes settings plus the selected waypoint's ID/name/coordinates, or nil to explicitly clear selection (including deletion). The primary packet carries the selected target/settings only. A separate bounded map packet carries visible library items; no phone location or basemap tiles are transferred. The phone republishes after activation, reachability changes and watch installation/pairing changes. Switching watches reactivates the session.

The watch saves the last valid snapshot to local defaults, restores it after relaunch, and shows its age as **CACHED SYNC**. **PHONE REACHABLE / PHONE NOT REACHABLE** reflects WCSession reachability, not an assertion that Bluetooth, pairing or delivery succeeded. An offline watch cannot discover a phone-side clear until the next context delivery; the cached label makes this limitation visible. Without any sync, position still works, and Navigate asks the user to select a waypoint on iPhone. Transfer is one-way; there is no watch library editor or selection override.

## Map and visible-library sync

`WatchMapSnapshot` uses its own `gridfix.map.v1` data key in the same complete application context. Every valid update replaces all cached map arrays, including empty arrays after hide/delete. Item visibility AND canonical, case-insensitive folder visibility apply to waypoints, graphics and finished tracks. A selected navigation target does not override hidden map visibility. The separate BoundaryMonitor contributes only its displayed/active area, matching the phone map; it has no folder/visibility flag and transfers no alert state.

The bridge observes waypoint/settings/field changes plus boundary areas/displayed/active IDs, debounces 250ms, captures values atomically on the main actor, then decodes/simplifies tracks off-main. It never subscribes to GPS updates or sends unfinished live recorder data. A generation guard drops superseded builds. A persisted per-phone source UUID and increasing revision guard against delayed updates and clock rollback; the watch rejects an older or conflicting equal revision before applying either map or navigation/settings from that context. The displayed timestamp remains an age label. Native WatchConnectivity authenticates the paired counterpart. The receiver reads the current received context inside main-actor delivery tasks.

MapKit SwiftUI on watchOS 10 supplies native pan/zoom, plus three floating 44pt controls for zoom in/out and recenter. Floating status/info leaves the map and native Apple Legal attribution exposed. Recenter follows a fresh watch CoreLocation fix; a pan or manual zoom enters Browsing and stops automatic following. Stale/poor/unauthorized fixes remove the location marker and disable recenter. The phone overlay remains cached, with its age/link state and limitation counters in Map info. The Apple basemap may need a connection; offline availability is controlled by MapKit and is not guaranteed. No paid key is required.

The watch bundles the phone's 496 NATO PNGs by resource-folder reference and preserves affiliation, echelon and imported MilGPS shape/character/color metadata. Task point symbols use named badges; basic points use SF glyphs and unknown keys a question-mark glyph. Task-glyph rotation is normalized, matching the phone's task-only rotation behavior; labels stay upright. This is not full phone icon-rendering parity. Routes, finished tracks, typed tactical paths/areas, range rings, Mercator sector arcs and the displayed boundary render as geometry. Decorative tactical teeth/arrows are simplified, not replaced with generic pins. Names appear when zoomed close and remain listed in Map info. This version does not implement MGRS grid, terrain/contours/viewshed layers, calibrated images, custom tile sources, phone offline-pack transfer or boundary monitoring. These are implementation gaps, not claims that watchOS forbids them.

Application transfer limits: **48KiB actual JSON bytes**, including Unicode; ≤150 waypoints and ≤64 combined field items. Lines/tracks over 160 vertices use the existing largest-deviation/endpoint-preserving TrackBacktrack simplifier (tolerance 0, max 160). Areas keep all vertices or are omitted if over 256; they are never decimated into another shape. Track source files over 2 MiB, malformed items, latitudes outside ±85° and dateline-crossing areas/sectors are omitted explicitly. Lines use FieldMapGeometry's dateline splitting; cached-map fit uses its shorter longitude interval. Map info shows omitted/simplified counts. The builder trims complete items to the byte budget, preserving a valid complete-empty replacement when necessary.

The MapKit APIs and availability were checked against the installed watch SDK interfaces. Latest-state context semantics follow [Apple's WatchConnectivity documentation](https://developer.apple.com/documentation/watchconnectivity/wcsession/updateapplicationcontext(_:)).

## Verification limits

The official watchOS 27.0 (24R362) simulator runtime was downloaded with Xcode's supported CLI and installed. Validation used a dedicated **Apple Watch SE 3, 40mm** and dedicated iPhone 17 pair; the main development iPhone simulator was not changed. Native Device Hub screenshots verify all four grid formats, full zone/easting/northing and right-side controls on one non-scrolling screen. Ten-digit night mode also fits with SwiftUI accessibility3 text size. Instrument numerals have fixed font metrics; labels scale. Navigation keeps distance, absolute bearing and reference visible together.

Real WatchConnectivity delivered the selected synthetic waypoint, units/reference/precision/night settings and explicit selection clearing. Local 6D/day overrides continued to apply after receiving a 4D/night phone context; resetting Follow phone picked up those latest settings. Relaunch restores the cache. Watch CoreLocation delivered location while the dedicated phone simulator was shut down. Clearing simulator location suppressed both grid rows after the 10-second freshness limit and showed STALE FIX with the retained age/accuracy.

Simulator caveats: `simctl ui ... content_size` reports unsupported on this watch runtime, so the large-text case uses the explicit DEBUG SwiftUI environment. CUA can inspect native Device Hub and its toolbar, but coordinate taps return `noWindowsAvailable` and watch-app AX children are unavailable; actual precision/night/map button taps and touch drags are **not claimed as automated**. The map cover removes pager gesture competition structurally; device touch routing still needs a hardware check. DEBUG launch controls exercise the same persisted settings for layout/state coverage. Some `simctl io screenshot` PNG captures omit glyph pixels even from the system clock; saved native Device Hub window captures provide an independent full-display check.

WatchConnectivity's simulator service reported reachable again after the paired phone simulator was shut down, despite simctl listing the pair disconnected. The app reports the actual WCSession value; simulator evidence cannot validate a reliable physical out-of-range transition. Real device pairing/delivery latency, GPS reception/accuracy, permission changes, wrist wake/sleep and control ergonomics still need hardware checks. No fabricated demonstration location is built into the app.

Device checklist: install paired phone/watch builds; select, rename, move and delete a waypoint; explicitly clear selection; change units/reference/precision/night mode; put phone out of reach and relaunch watch; reconnect and verify latest state replaces cache; deny/reduce/grant location; verify stale numbers disappear after 10 seconds and acquisition stops on background. Test a small watch display and large Dynamic Type for readable scrolling.

Font licenses are bundled beside the original Android font files.

## Isolated simulator fixtures (DEBUG only)

Launch the dedicated phone simulator app with `-uiTesting -uiTestWatch` to seed a temporary store with **SYNTHETIC RALLY** at 24.4639,54.3873. Optional `-uiTestWatchClear`, `-uiTestWatchNight`, `-uiTestWatchPrecision4` and `-uiTestWatchMag` set explicit clear/night/four-digit/manual-magnetic contexts. These switches require the existing isolated `-uiTesting` store and cannot seed production data. Launch watch with `-watchNavigate` to select its second page. With explicit `-watchUITesting`, `-watchPrecision 4|6|8|10|phone` and `-watchNight day|night|phone` exercise local override/follow state, `-watchDetails` opens the diagnostics sheet, and `-watchLargeText` supplies SwiftUI’s accessibility3 text-size environment. These flags change actual local preferences/layout only; they never supply location or target data. The watch has no mock fix or target injection: simulated location must be delivered through the simulator’s location controls and targets/settings through the real WatchConnectivity context.

Map fixtures: phone `-uiTesting -uiTestWatch -uiTestWatchMap` seeds synthetic visible/hidden waypoints, a NATO infantry point, route/area/ring, finished track and displayed fence in the temporary test store. `-uiTestWatchMapClear` hides Base in a fresh temporary store to send a complete-empty overlay while retaining the separate navigation target. Watch `-watchMap` opens the map; with `-watchUITesting`, `-watchMapPan`, `-watchMapZoom`, `-watchMapRecenter` exercise the same camera actions programmatically and `-watchMapInfo` opens sync/limit details. DEBUG camera logs record actual MapKit center/span/follow state; these checks do not simulate physical touch gestures.

Map runtime checks on the dedicated 40mm simulator: real WatchConnectivity delivered two visible waypoints and five typed field items, excluding the hidden-folder point. A later complete-empty packet (revision 18) persisted zero waypoints/features after hide, while the separate hidden selected navigation target remained intact. Actual MapKit camera logs verified programmed pan enters Browsing, zoom halves local span to 0.003, and recenter returns to the delivered watch fix at span 0.006 and resumes following. CLI frames verify the floating layout, native attribution, day/night overlays, and NATO infantry internal marks preserved by the same luminance-red/black-to-alpha transform as the phone. The latest native-window capture was unavailable after the Mac locked; latest frames are unmodified simulator CLI screenshots. Clearing simulated location removed the own-watch marker and displayed NO FRESH FIX while keeping the cached basemap/overlay view. No physical touch routing claim is made.

Navigation-lane maps now receive complete L/R/BS geometry and shading with
landmark labels, visibility replacement and explicit whole-lane omissions.
Limits are not simplified and no crossing detector runs on watch. See
[shared contract and paired-simulator evidence](../docs/watch-companion-parity.md).

## Phone guidance

Navigate also shows a distinct read-only **Phone guidance** section with the
phone's target, confirmed lane status and named crossed limit. Source evaluation
and transport expiry gates prevent stale steering from appearing current. The
phone owns these decisions; watch GPS still owns grid/map/target numbers, and
quiet-inside boundaries remain separate. No watch alerts or background guidance
are enabled by this display. See [contract and paired evidence](../docs/watch-phone-guidance.md).
