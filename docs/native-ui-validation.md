# Native UI verification across runtimes

The hosted failures were investigated using run 40148795773's actual xcresult, accessibility trees and screen recordings, followed by the local iOS 26.5 (23F77) iPhone 16e runtime used by CI. Local builds use Xcode 27.1; hosted builds use Xcode 26.6, so a matching runtime is not a claim of identical toolchains.

Native nested format menus rendered their expanded choices on iOS 26.5 while leaving those choices out of the accessibility tree. Paste/export now use native choice dialogs. Field exports share one Files presenter and preserve each format's bytes, content type and filename; competing fileExporter modifiers on the same view had suppressed non-GPX presentation on that runtime. Track-only GPX also uses that presenter. Cancel remains quiet and genuine write errors are shown.

Map tools use a native list sheet and open the chosen worksheet after dismissal. Orientation shortcuts likewise commit their choice after dismissal; Settings can change orientation directly.

Point selectors use searchable native lists with coordinate captions and a checkmark. This avoids popup selection/activation ambiguity and keeps larger point libraries searchable. Selecting a field reference changes only that tool's input, never the navigation target.

Automation uses actual native input. A floating keyboard Done control can overlap the trailing portion of another Form input; the helper dismisses it and waits for the keyboard before choosing the next field. Native Select All and deletion replace text, with explicit empty-value and replacement-value assertions. Hosted Xcode 26 delivered Command-A without selecting existing text, producing appended folder and waypoint names; hardware shortcuts are no longer used for replacement. Files Save is scoped to the native picker, using its observed identifier or accessible label. The share popover is dismissed outside its outer content; ActivityListView's frame describes only its action rows.

For local builds in this Documents workspace, sampled simulator processes stalled in dyld while opening a generated GridFixCore package framework from the workspace's build directory. Building with derived data at `/tmp/gridfix-native-field-derived` removed that stall. No macOS privacy settings were changed. This is an observed local validation workaround, not an iOS feature limitation.

The first install on a fresh simulator reset an earlier location grant. Real-driver tests require precise While Using permission after installation. Their assertions are retained and were rerun with that setup. Real simulator Core Location feeds remain external to the app.

Landscape XCTest element captures can contain clipped/black regions despite correct geometry. An independent full-frame `simctl io screenshot` on iOS 27 verified the actual two-column Position layout, full grid, readouts and all four tabs. Geometry/rotation assertions exercise iOS 26.5; screenshots do not replace physical worn-device, rotation-lock or iPad window checks.

## Local milestone results

The iOS 26.5 runtime passes all 84 app integration tests with zero failures or skips after the post-install permission setup. Native UI checks pass for coordinate entry/edit/save/relaunch, route creation, library visibility/folder edits, CSV retry import, GeoJSON and KML/ATAK native Files round trips, PDF preview/share/save, projection, planning, resection/intersection, measurement editing and all three terrain workflows. Point-search filtering and cancel preserve the original reference and leave the parent worksheet interactive. The combined phone/embedded-watch unsigned Release build passes.

Shortcut reachability is tested in portrait separately from pinned landscape geometry, opposite-side rotation and relaunch persistence. The landscape shortcut gesture sequence remains an automation limitation on this simulator: app-level swipes leave the Map tools list at its initial scroll position. It is not counted as a passing landscape touch test. Physical landscape interactions remain a device check. Hosted CI must independently pass with its Xcode 26.6 toolchain before these local fixes are called a CI resolution.

The position/compass milestone increases the app integration suite to 89 passing tests. Real Core Location expiry/recovery now has its own host-controlled native workflow, separate from continuous route feeds; it verifies the 10-second QR gate, retained 31-second STALE grid, night presentation and resumed moving fixes. Glance details scroll so the larger night bar cannot hide the last readouts. Orientation regressions continue to pass. See [position fix quality](position-fix-quality.md) for sensor and hardware limits.

## Hosted run 40158734078 interaction failures

The actual hosted xcresult, accessibility trees and videos show nine failures among 56 UI tests. Library paste/export and track-folder menus could remain open instead of presenting the next action; a terrain source popup similarly failed to commit Waypoint. Library/track actions and terrain source selection now use native scrolling choice sheets. Library and track actions execute after dismissal, and track actions re-read the current record by ID. Existing actions, disabled backtrack rules and destructive confirmation are preserved.

Videos also show taps inside the padded waypoint summary and map QR control failing to activate. Explicit rectangular content shapes now cover the full label, including padding. Regression gestures additionally tap outside the visible QR glyph and near the waypoint summary's trailing edge.

Pinned orientation tests still verify landscape while the physical simulator is upright, the opposite landscape mode, relaunch persistence and Auto. They align the physical XCTest device with the pinned window before touching the next control, avoiding an observed coordinate-space mismatch. This is an automation adjustment, not removal of the pinning assertions.

With the production interaction changes, all 95 native app integration tests pass locally. A focused iOS 26.5 run using continuous external Core Location updates passed field fixes, KMZ Files round trip, backtrack, folder rename, pinned orientation, waypoint QR, invalid/night projection, terrain LOS/profile/viewshed, and coordinate/map/folder visibility. GeoJSON export initially exposed a premature existence assertion; waiting for the format dialog now passes the complete Files save/reopen/counts workflow. Track moving additionally exposed a folder row whose whitespace did not activate. Its full-width rectangular target passes selection from the right-hand whitespace, removes the row from Recon and shows it in Base without changing hidden state. The QR corner and waypoint summary edge gestures pass too.

Follow-up hosted run 40160268079 exposed additional worksheet and batch-action failures. Batch selection now also uses a choice sheet and presents destructive confirmation after dismissal; cancelling keeps the selection. Date-navigation automation stops scrolling once its controls are reachable instead of blindly overscrolling and dismissing the worksheet. The Sun/moon/date/declination/practice/LOS workflow and batch visibility/cancel workflow pass locally. Native alert automation waits for the confirmation before choosing Delete. Short numeric input replacement explicitly places the caret at the trailing value edge when iOS offers no Select All action; every replacement still asserts the cleared and final values.

A fresh local runner verified mixed deletion, relaunch persistence and preservation of Base records. It also exposed a genuine worksheet problem: the floating keyboard Done control covered the azimuth input. Field fixes now reserve a separate bottom bar and scroll the focused known-point/name section into view without an extra scroll animation. The native regression asserts that Done does not intersect the input, in addition to verifying the typed value and calculated result. Show/save/relaunch and reference-search/cancel pass with this layout; the final value-edge selection helper also passes invalid negative azimuth, corrected input, poor-cut warnings and night presentation. Day/night keyboard screenshots were inspected and keep both the known point and azimuth visible above Done.

Two earlier local incremental attempts logged old test gestures and failure line numbers after the source changed. Reinstalling only the UI test runner, rebuilding its intermediates, and disabling compilation caching produced the updated gestures. Those stale attempts and an interrupted animated-focus experiment are not accepted as passing results; the final source is checked separately.

Inspected screenshots cover the native selection sheet, moved hidden track, night projection validation, night QR, terrain viewshed and Sun/moon tables. The combined unsigned phone/embedded-watch Release build passes. Hosted Xcode 26.6 remains an independent gate. CI retains every suite and expands its budget to 75 minutes because the observed UI step alone took 39 minutes with early failures.

## Backup preparation and further picker checks

The backup milestone passes 290 core tests and 103 app integration tests locally. Its native Files workflow exports a ZIP in night mode, deletes a mixed folder, restores that actual saved file and verifies reopened records while keeping Base data. Read/write workers, late provider cancellation, overlapping generations, edits during reads, ordered partial failures and retry are covered in [backup preparation](backup-preparation.md). Atomic persistence still needs large-library performance work.

Run 40161958989 was cancelled with its UI result bundle unfinished; attachment export consequently failed because Info.plist was absent. Its available logs exposed two further picker failures: Name sort never opened and Platoon had an invalid activation frame. Both now use the native choice-sheet pattern. Favourite/name order/removal/relaunch and the full unit-symbol/echelon/save/reopen/day/night-map workflow pass on iOS 26.5. Saved-base projection/save/edit/relaunch also passes with the current native input helpers. Screenshots of the symbol editor, library and restored night-mode data were inspected. The combined unsigned phone/embedded-watch Release build passes; these results do not establish a full hosted CI pass.

## Worker-prepared restore publication

Restore merging, encoding and full file writes now run on workers, with store-instance/revision checks and atomic rename before main-actor publication. Stale preparations rebase after edits, folder/selection changes and new finished tracks. Once committing, in-process cancellation does not abandon ordered phases. Existing backup/failure tests use this production async path; tests additionally cover publication thread, stale token rejection, replacement failure and rebasing. The milestone passes 296 core and 107 app integration tests plus the native night-mode backup Files/delete/restore/relaunch workflow.

A recorded model benchmark restores an accepted 5,000-waypoint/1,000-route/50,000-track-point backup while the main actor edits and selects a local waypoint. One local run took 0.848 seconds with 432 main-actor timer pulses and a 0.004-second largest observed gap; a subsequent run took 0.874 seconds with a 0.004-second gap. These measurements do not cover rendering a large SwiftUI library, physical storage latency or locked-device behavior. See [backup preparation](backup-preparation.md).

Screenshot review also found that hidden records lost too much text contrast. Library names now retain their normal ink and use explicit eye-slash markers, including mixed selection, rather than fading the complete record. Map visibility flags are unchanged. The native backup/night and mixed visibility/cancel workflows pass; their screenshots were inspected. The combined unsigned phone/embedded-watch Release build passes.

## Cached library listing and batched map markers

The library now builds search keys, folder/catalog metadata, ordering and mixed
result IDs on a coalescing background worker. Superseded query/source generations
cannot publish stale results or drive selection; GPS-only reorder samples keep
the accepted list usable. Reused name keys require byte-identical names because
Swift's canonical string equality is broader than Android's code-point ordering.

Local evidence on iPhone 16e / iOS 26.5: 300 core tests and 112 app integration
tests pass. Focused native runs pass all eight LibraryWorkflow tests, all three
LibrarySearchWorkflow tests, the night Files backup export/delete/restore/relaunch
workflow, and the new 5,000-waypoint/100-folder/1,000-route workflow. The large test
checks favourites, name/folder and displayed MGRS search, selection replacement
across filters, map entry, night toggle and return to readable results. The first
fixture runs exposed count-format/selection-mode assertion mistakes, which were
corrected without removing those behavior checks. Day and night attachments were
exported from closed result bundles and inspected.

The large test also exposed a real map stall: individual `addAnnotation` calls
repeatedly rebuilt the growing view hierarchy. A process sample identified the
main thread inside MapLibre insertion. The coordinator now batches annotation
removals/additions while retaining unchanged markers. The same full-data native
workflow passes afterward. Dense map accessibility queries remain expensive;
this does not establish physical map/battery performance. The unsigned combined
phone/embedded-watch Release build is checked separately. Full hosted CI remains
a distinct gate; these focused results are not a claim that hosted CI is green.

The existing coordinate-entry → map marker selection → navigation → folder
hide/show native regression passes after marker batching. The final unsigned
combined phone/embedded-watch Release build passes as well.
