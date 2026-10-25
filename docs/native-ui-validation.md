# Native UI verification across runtimes

The hosted failures were investigated using run 40148795773's actual xcresult, accessibility trees and screen recordings, followed by the local iOS 26.5 (23F77) iPhone 16e runtime used by CI. Local builds use Xcode 27.1; hosted builds use Xcode 26.6, so a matching runtime is not a claim of identical toolchains.

Native nested format menus rendered their expanded choices on iOS 26.5 while leaving those choices out of the accessibility tree. Paste/export now use native choice dialogs. Field exports share one Files presenter and preserve each format's bytes, content type and filename; competing fileExporter modifiers on the same view had suppressed non-GPX presentation on that runtime. Track-only GPX also uses that presenter. Cancel remains quiet and genuine write errors are shown.

Map tools use a native list sheet and open the chosen worksheet after dismissal. Orientation shortcuts likewise commit their choice after dismissal; Settings can change orientation directly.

Point selectors use searchable native lists with coordinate captions and a checkmark. This avoids popup selection/activation ambiguity and keeps larger point libraries searchable. Selecting a field reference changes only that tool's input, never the navigation target.

Automation uses actual native input and public keyboard shortcuts. A floating keyboard Done control can overlap the trailing portion of another Form input; the helper dismisses it and waits for the keyboard before choosing the next field. Select All replaces text without depending on the cursor position. Files Save is scoped to the native picker, using its observed identifier or accessible label. The share popover is dismissed outside its outer content; ActivityListView's frame describes only its action rows.

For local builds in this Documents workspace, sampled simulator processes stalled in dyld while opening a generated GridFixCore package framework from the workspace's build directory. Building with derived data at `/tmp/gridfix-native-field-derived` removed that stall. No macOS privacy settings were changed. This is an observed local validation workaround, not an iOS feature limitation.

The first install on a fresh simulator reset an earlier location grant. Real-driver tests require precise While Using permission after installation. Their assertions are retained and were rerun with that setup. Real simulator Core Location feeds remain external to the app.

Landscape XCTest element captures can contain clipped/black regions despite correct geometry. An independent full-frame `simctl io screenshot` on iOS 27 verified the actual two-column Position layout, full grid, readouts and all four tabs. Geometry/rotation assertions exercise iOS 26.5; screenshots do not replace physical worn-device, rotation-lock or iPad window checks.

## Local milestone results

The iOS 26.5 runtime passes all 84 app integration tests with zero failures or skips after the post-install permission setup. Native UI checks pass for coordinate entry/edit/save/relaunch, route creation, library visibility/folder edits, CSV retry import, GeoJSON and KML/ATAK native Files round trips, PDF preview/share/save, projection, planning, resection/intersection, measurement editing and all three terrain workflows. Point-search filtering and cancel preserve the original reference and leave the parent worksheet interactive. The combined phone/embedded-watch unsigned Release build passes.

Shortcut reachability is tested in portrait separately from pinned landscape geometry, opposite-side rotation and relaunch persistence. The landscape shortcut gesture sequence remains an automation limitation on this simulator: app-level swipes leave the Map tools list at its initial scroll position. It is not counted as a passing landscape touch test. Physical landscape interactions remain a device check. Hosted CI must independently pass with its Xcode 26.6 toolchain before these local fixes are called a CI resolution.

The position/compass milestone increases the app integration suite to 89 passing tests. Real Core Location expiry/recovery now has its own host-controlled native workflow, separate from continuous route feeds; it verifies the 10-second QR gate, retained 31-second STALE grid, night presentation and resumed moving fixes. Glance details scroll so the larger night bar cannot hide the last readouts. Orientation regressions continue to pass. See [position fix quality](position-fix-quality.md) for sensor and hardware limits.
