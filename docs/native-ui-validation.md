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

## Worker-prepared interchange commits

CSV/GeoJSON/GPX/KML/KMZ/ATAK confirmations now use the shared staged field and
waypoint commit phases. Validation, merge, encoding and full writes run on
workers; atomic main-actor publication rechecks store identity/revision and
rebases after concurrent edits. Android's tracks → waypoints/folders → graphics
order and cancellation between completed atomic phases remain intact. Storage
failures name the failed section and retain confirmed saved counts for retry.

The sheet displays importing progress and rejects duplicate confirmation,
editing and dismissal during a confirmed commit. Its owner finishes and reports work
through sheet disappearance; reading/preview remains separately cancellable.
Tests cover duplicate starts, cancellation/error reset, retained ownership,
cancellation after durable track publication, untouched later phases, invalid
plan rejection, suppression of a departed sheet’s late dismissal, local track
edits on retry and the existing failure/reopen/ID
fixtures through the production async coordinator.

A parsed GPX with 5,000 waypoints, 1,000 routes and 50,000 track points committed
locally in 0.940 seconds (485 main-actor pulses; largest gap 0.005 seconds), then
0.800 seconds (400 pulses; largest gap 0.004 seconds), while a local waypoint was
edited/selected. These are model measurements, not physical/UI performance gates.
Native CSV/GeoJSON preview/cancel/confirm/retry, malformed/night input, KML map/
relaunch, KMZ and ATAK Files workflows pass. The GPX route/track import, generated
waypoints/navigation, map overlays and track visibility/relaunch regression also
passes. Day/night preview attachments were exported from closed bundles and
inspected. All 119 app integration tests and the combined unsigned phone/watch Release
build pass locally; hosted
CI, physical providers/storage pressure and synchronous non-backup exports/other
library edits remain separate work.

## Snapshot-based field exports

Library GPX/CSV/GeoJSON/KML/KMZ/ATAK and single-track GPX now capture value
snapshots and decode/encode them on workers. Format policy and hidden-record
inclusion remain unchanged. Preparation has progress/cancellation, refuses
competing requests and rejects late results after cancellation or navigation.
Backup and field preparation share the library Files presenter exclusively;
reading/restoring a backup retains concurrent editing/rebase behavior.

All 127 app integration tests pass locally. Export tests reparse all six formats,
verify type/name/geometry rules, retain a captured track after actual stores edit
and delete data, propagate malformed required logs, cancel late encoders and
exercise overlapping requests and failure-callback retry. A 5,000-waypoint/
1,000-route/50,000-track-point GPX encoded in 1.406 seconds with 719 main-actor
pulses and a 0.004-second largest observed gap. This is a model observation,
not a physical-device/UI timing gate.

Native Files workflows pass large GPX export/reopen with all 5,000 waypoints and
1,000 routes; GPX from both the track detail and mixed-library menu, each reopening
as exactly one track in night mode; existing GeoJSON, KML, KMZ and ATAK package
round trips; and the night-mode backup export/delete/restore/relaunch regression.
The final large-GPX and backup checks pass again after presenter-busy controls
were unified. Day/night attachments were exported from closed bundles and
inspected. The combined unsigned iPhone/embedded-watch Release build passes.
See [field export preparation](export-preparation.md). Hosted CI, other synchronous
library edits, dense-map profiling and physical provider/storage/memory/battery
checks remain separate work.

## Worker-prepared field edits and hosted picker regression

Normal graphic/route saves, panel/detail graphic/route/track visibility and
deletion, library-row graphic/track visibility, track-folder moves and backtrack
graphic publication now stage their
archive edits on workers. Changed-field patches preserve concurrent geometry or
metadata; deleted originals are not recreated. New route editors retain their
identity across retry. Folder registration uses the staged waypoint merge and
reports a graphic already saved if its second store fails. Core tests cover
atomic/stale/owner/failure behavior and intact logs/history; app tests cover the
production path, partial folder failure, selection, ownership and concurrent
large-archive edits. The milestone passes 310 core and 133 app integration tests.

The first native matrix passes all 18 drawing/library/measurement/route-creation
workflows. A focused follow-up passes night-mode route edit/visibility/delete and
graphic/track visibility/delete with relaunch, plus strengthened drawing/area/
route tests that wait for save acknowledgement before terminating the app.
Snapshots and tests do not establish physical large-archive map performance.
See [field edit preparation](field-edit-preparation.md) for remaining synchronous
waypoint, mixed-folder/batch, recording-finalization and course-result paths.

Hosted run 40168664266's actual closed xcresult reports 163 passed / 1 failed,
with zero skips. Its lone failure is BackupWorkflowTests at saved-file selection.
The hierarchy shows the system document picker on an empty Recents tab, and its
video shows the preceding export saved under On My iPhone. This is a native Files
test navigation assumption, not evidence of a restore data failure. The artifact
exceeded the connector's 512 MiB limit and was retrieved through GitHub CLI.
Round-trip tests now explicitly use Browse → the local provider and scroll its
virtualized File View before selecting the exact saved filename. The backup
regression deliberately visits Recents first. Record/restore assertions remain.
The first helper revision exposed offscreen file cells in the populated local
simulator; scoped browser scrolling fixes that without deleting prior files.

That hosted integration/UI step took about 58 minutes before the added large-data
and edit/export coverage. The outer CI budget is now 90 minutes so all assertions,
separate real-location workflows and diagnostic upload retain their gates.
Local passes do not establish that the updated hosted run is green.

The corrected native Files helper passes all six backup/large-GPX/GeoJSON/
KML/ATAK/KMZ cases in the closed `gridfix-field-edit-picker-scroll.xcresult`
bundle (six passes, zero failures/skips). It uses a slow drag confined between
the Files navigation bar and tab bar, holds before release to stop momentum,
then taps the validated current cell frame. A preceding KMZ run caught a cell
moving behind the navigation bar after a fast swipe; its visibility assertion
prevented a misleading tap. A clean local rebuild was required to stop callers
executing older incremental helper bodies. No saved exports were removed and no
restore/count assertions were weakened to obtain the pass.

Route-edit and track-detail night screenshots and the area-measurement sheet were
exported and visually inspected. The current core suite passes 331 tests,
including an explicit-hide/concurrent-hide-and-rename regression and 20 new
Android navigation-lane geometry/guide/model cases. The final unsigned
phone/embedded-watch Release build passes. Lane UI, persistence and active
guidance remain pending; see the [overnight audit](android-overnight-2026-10-25.md).

After the explicit library-row visibility fix, the closed
`gridfix-field-edit-final-ownership.xcresult` passes all 133 app integration
tests and both native night-mode field-edit/relaunch cases: 135 passed,
zero failures/skips. Individual Hide applies the requested visibility even if
another edit already hid the record; mixed batch swaps remain swaps.

## Navigation lanes beyond release/1.1.0

The separate three-line lane mode now has worker-owned persistent records,
map drawing and draggable segment handles, linked graphic limits, day/night
shading and L/R/BS labels, checkpoint/route assignment, a lane library and
Navigate state/cues. Confirmed background crossings/reentry request iOS
notifications; repeats stay foreground haptics. Quiet-inside perimeters remain
independent. See [navigation lanes](navigation-lanes.md) for behavior and gaps.

The complete core suite passes 340 tests; all 137 app integration tests pass.
The closed `gridfix-lane-final.xcresult` reports 140 passed / zero failed/skipped,
including native lane creation/editing/persistence/deletion and the existing
route-drawing regression. After display refinements,
`gridfix-lane-display-native.xcresult` passes both native lane workflows again.
Its exported day/night screenshots show separated L/R/BS labels and limits
reaching the backstop; the hidden-library night sheet remains readable.
A final draw-only native run passes, and its actual saved lane file contains a
three-point line with a 13.0 m perpendicular bend. The unsigned phone/embedded-
watch Release build passes. These checks do not prove physical haptic feel,
locked-screen notification delivery, battery or storage-pressure behavior.
Lane record backups, route-card limits, watch synchronization and later Android
cue switches remain implementation work.

## Lane backup and route-card milestone

The complete core suite now passes 347 tests and all 143 app integration tests
pass. These include Android-compatible optional lane JSON/ZIP records, legacy
archives without lanes, malformed sections, additive retries, existing-local-ID
precedence, serial atomic lane publication, canceled confirmed restore and real
filesystem failures before/after the lane phase. Route-card requests capture
lane/target/graphic values; checkpoint limits override route limits, hidden
lanes still apply and changed inputs invalidate prepared PDFs. An 84-leg PDF
retains every table marker exactly once, repeats page headers, includes one
final total and keeps every extracted character inside the page bounds.

The clean `gridfix-lane-backup-native-final.xcresult` passes four native tests
with zero failures/skips: the existing night-mode mixed-record backup round
trip, hidden whole-route lane export/delete/restore/relaunch and route-card/PDF
preview, plus both existing native PDF workflows. Files selection handles
Browse reopening directly inside the local provider with virtualized filenames;
no files were removed and count assertions remain intact. Actual PDFKit pages
were rendered and the short, first, continuation and final-page layouts were
visually inspected. Native night library, per-leg limit and PDF-preview
screenshots were also inspected for readable text and controls. The unsigned
phone/embedded-watch Release build passes.
Watch lane synchronization, protected backups and later Android cue switches
remain implementation work; this does not prove physical lock-screen delivery.
