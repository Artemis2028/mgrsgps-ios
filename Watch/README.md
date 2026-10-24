# GridFix for Apple Watch

Native SwiftUI companion, watchOS 10+. Swipe between **Position** and **Navigate**.

Position is a fixed instrument: zone, easting and northing fit together on the 40mm display. The right-side **FORMAT** button cycles **4D → 6D → 8D → 10D**, saving a local format override; **PHONE** resumes the latest synced phone precision. GPS accuracy (± metres) and age appear separately at the top: ten-digit formatting never claims one-metre GPS accuracy. Tap the zone / ⓘ row for connection/cache diagnostics and night controls. These secondary details scroll in a sheet; the primary grid does not scroll. Instrument numerals use fixed font metrics while labels adapt to text size.
Position uses the Android Glance font assets (Antonio bold/Fira Mono/Saira Semi Condensed) and bone/amber/lume palette. Phone night mode turns the app content red on black. Each page also offers a local Night mode toggle for disconnected use; Follow phone night mode removes that persistent local override. The system watch clock and system UI follow watchOS appearance; the app cannot promise that every system surface becomes red.

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

`WatchSnapshot` in GridFixCore is versioned, Codable and validated before application. The phone observes waypoint/settings changes and sends a **complete latest application context**, which WatchConnectivity coalesces while offline. Every snapshot includes settings plus the selected waypoint's ID/name/coordinates, or nil to explicitly clear selection (including deletion). No full library or phone location is transferred. The phone republishes after activation, reachability changes and watch installation/pairing changes. Switching watches reactivates the session.

The watch saves the last valid snapshot to local defaults, restores it after relaunch, and shows its age as **CACHED SYNC**. **PHONE REACHABLE / PHONE NOT REACHABLE** reflects WCSession reachability, not an assertion that Bluetooth, pairing or delivery succeeded. An offline watch cannot discover a phone-side clear until the next context delivery; the cached label makes this limitation visible. Without any sync, position still works, and Navigate asks the user to select a waypoint on iPhone. Transfer is one-way; there is no watch library editor or selection override.

## Verification limits

The official watchOS 27.0 (24R362) simulator runtime was downloaded with Xcode's supported CLI and installed. Validation used a dedicated **Apple Watch SE 3, 40mm** and dedicated iPhone 17 pair; the main development iPhone simulator was not changed. Native Device Hub screenshots verify all four grid formats, full zone/easting/northing and right-side controls on one non-scrolling screen. Ten-digit night mode also fits with SwiftUI accessibility3 text size. Instrument numerals have fixed font metrics; labels scale. Navigation keeps distance, absolute bearing and reference visible together.

Real WatchConnectivity delivered the selected synthetic waypoint, units/reference/precision/night settings and explicit selection clearing. Local 6D/day overrides continued to apply after receiving a 4D/night phone context; resetting Follow phone picked up those latest settings. Relaunch restores the cache. Watch CoreLocation delivered location while the dedicated phone simulator was shut down. Clearing simulator location suppressed both grid rows after the 10-second freshness limit and showed STALE FIX with the retained age/accuracy.

Simulator caveats: `simctl ui ... content_size` reports unsupported on this watch runtime, so the large-text case uses the explicit DEBUG SwiftUI environment. CUA can inspect native Device Hub and its toolbar, but coordinate taps return `noWindowsAvailable` and watch-app AX children are unavailable; actual precision/night button taps are **not claimed as automated**. DEBUG launch controls exercise the same persisted settings for layout/state coverage. Some `simctl io screenshot` PNG captures omit glyph pixels even from the system clock; saved native Device Hub window captures provide an independent full-display check.

WatchConnectivity's simulator service reported reachable again after the paired phone simulator was shut down, despite simctl listing the pair disconnected. The app reports the actual WCSession value; simulator evidence cannot validate a reliable physical out-of-range transition. Real device pairing/delivery latency, GPS reception/accuracy, permission changes, wrist wake/sleep and control ergonomics still need hardware checks. No fabricated demonstration location is built into the app.

Device checklist: install paired phone/watch builds; select, rename, move and delete a waypoint; explicitly clear selection; change units/reference/precision/night mode; put phone out of reach and relaunch watch; reconnect and verify latest state replaces cache; deny/reduce/grant location; verify stale numbers disappear after 10 seconds and acquisition stops on background. Test a small watch display and large Dynamic Type for readable scrolling.

Font licenses are bundled beside the original Android font files.

## Isolated simulator fixtures (DEBUG only)

Launch the dedicated phone simulator app with `-uiTesting -uiTestWatch` to seed a temporary store with **SYNTHETIC RALLY** at 24.4639,54.3873. Optional `-uiTestWatchClear`, `-uiTestWatchNight`, `-uiTestWatchPrecision4` and `-uiTestWatchMag` set explicit clear/night/four-digit/manual-magnetic contexts. These switches require the existing isolated `-uiTesting` store and cannot seed production data. Launch watch with `-watchNavigate` to select its second page. With explicit `-watchUITesting`, `-watchPrecision 4|6|8|10|phone` and `-watchNight day|night|phone` exercise local override/follow state, `-watchDetails` opens the diagnostics sheet, and `-watchLargeText` supplies SwiftUI’s accessibility3 text-size environment. These flags change actual local preferences/layout only; they never supply location or target data. The watch has no mock fix or target injection: simulated location must be delivered through the simulator’s location controls and targets/settings through the real WatchConnectivity context.
