# GridFix for Apple Watch

Native SwiftUI companion, watchOS 10+. Swipe between **Position** and **Navigate**.
Position uses the Android Glance font assets (Antonio/Fira Mono) and bone/amber/lume palette. Phone night mode turns the app content red on black. The system watch clock and system UI follow watchOS appearance; the app cannot promise that every system surface becomes red.

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

The displayed grid and navigation numbers require precise location, nonnegative accuracy ≤25 m and fix age ≤10 seconds. Receipt age is anchored to system uptime so a clock adjustment cannot revive an expired fix. Invalid/stale fixes suppress grid/bearing/distance rather than present them as current; the last reported accuracy and age remain visible. At the target's uncertainty radius, the app replaces bearing with “Within fix uncertainty.” Distances use shared Vincenty math and phone units. Bearings show TRUE, MAG or GRID explicitly; magnetic uses the phone's manual override or a valid bundled WMM. Expired/missing models suppress magnetic bearings.

The first version deliberately displays numeric bearing to the waypoint. It does not rotate a target arrow or claim a compass heading. Apple Watch heading availability varies with hardware and simulator; compass and haptic behavior require paired-device testing before future guidance features.

## Phone → watch contract

`WatchSnapshot` in GridFixCore is versioned, Codable and validated before application. The phone observes waypoint/settings changes and sends a **complete latest application context**, which WatchConnectivity coalesces while offline. Every snapshot includes settings plus the selected waypoint's ID/name/coordinates, or nil to explicitly clear selection (including deletion). No full library or phone location is transferred. The phone republishes after activation, reachability changes and watch installation/pairing changes. Switching watches reactivates the session.

The watch saves the last valid snapshot to local defaults, restores it after relaunch, and shows its age as **CACHED SYNC**. **PHONE REACHABLE / PHONE NOT REACHABLE** reflects WCSession reachability, not an assertion that Bluetooth, pairing or delivery succeeded. An offline watch cannot discover a phone-side clear until the next context delivery; the cached label makes this limitation visible. Without any sync, position still works, and Navigate asks the user to select a waypoint on iPhone. Transfer is one-way; there is no watch library editor or selection override.

## Verification limits

The installed Xcode has watchOS 27 SDKs; no watchOS simulator runtime/device was installed during implementation. Compilation and portable payload/reference tests are possible, but simulator screenshots, real pairing delivery, installation, crown/swipe usability, reduced-accuracy authorization, wrist wake/sleep and actual GPS freshness must still be checked on a watch runtime/device. No fabricated demonstration location is included.

Device checklist: install paired phone/watch builds; select, rename, move and delete a waypoint; explicitly clear selection; change units/reference/precision/night mode; put phone out of reach and relaunch watch; reconnect and verify latest state replaces cache; deny/reduce/grant location; verify stale numbers disappear after 10 seconds and acquisition stops on background. Test a small watch display and large Dynamic Type for readable scrolling.

Font licenses are bundled beside the original Android font files.
