# Watch companion feature contract

Wear OS and watchOS share this functional scope. Native controls may differ to fit round and rectangular screens.

| Capability | Shared behavior |
| --- | --- |
| Current grid | Watch GPS, MGRS zone/square and both coordinate rows together on one primary screen |
| Coordinate format | Local 4/6/8/10-digit selector on the right; independent Follow phone reset |
| Fix quality | Source, reported horizontal accuracy and fix age; stale/unauthorized fixes cannot produce navigation numbers |
| Selected waypoint | Name, numeric bearing and distance; explicit phone selection clearing removes the cached target |
| References | Phone distance/angle units and true, magnetic or grid reference; unavailable magnetic reference is explicit |
| Phone connection | Cached target/settings remain usable with their age and honest connection status |
| Map | Read-only interactive map with pan/zoom/recenter, fresh watch position, cached visible waypoints and field geometry, sync age and explicit omission/simplification counts |
| Route leg labels | Complete routes use ordinary numbers; simplified routes use original leg ranges, with a named range summary in map info. Legacy simplified caches remain unnumbered |
| Navigation lanes | Cached complete side limits/backstop/shading and landmark labels; lane/folder hide/delete replaces the scene; separate live phone-guidance status with expiry; opted-in foreground wrist crossing alerts using own precise fresh GPS, named limits and explicit rearm after suspension |
| TAK layer | Separate read-only contacts, markers, lines and areas; complete replacements, bounded geometry, explicit omissions and expiry retained across relaunch |
| Night mode | Local Day/Night/Follow phone choice, independent of the precision override |

Digit count describes coordinate formatting, not GPS accuracy. Both platforms display reported GPS accuracy separately. Foreground wrist lane alert owners are implemented on both platforms; watchOS and Wear foreground runtime checks pass (see watch-wrist-lanes.md). Optional screen-off wrist lane alerts are now implemented on both platforms; see watch-background-alerts.md and the Wear background-lanes report. A foreground watchOS own-heading/target-steering owner is now implemented with policy/build and unavailable-compass layout validation (see watch-own-steering.md); positive native compass/haptic/physical validation remains open. Wear steering, automatic watch route progression and broader background navigation remain implementation work; physical locked-screen delivery/GPS/battery validation is still open.

Small-screen simulator checks cover a 40 mm Apple Watch and a 192 dp round Wear OS device. Apple phone/watch application-context delivery has been exercised with a paired simulator. Wear OS rendering, freshness and populated scene/phone-guidance Data Layer delivery have been checked with the paired emulators; physical Data Layer delivery remains to be verified. Simulator evidence does not replace field, battery, permission or radio testing.

Current map implementation differences:

- watchOS uses Apple Maps and opens its interactive map full-screen from the third Map page. Wear OS uses OSM browse tiles with attribution and an MGRS grid toggle. Neither transfers phone MBTiles, downloaded map areas, contours, DEMs or viewsheds.
- Both retain a bounded copy of field overlays. Basemap caches are controlled separately and do not guarantee offline coverage.
- watchOS additionally receives the iOS phone's displayed quiet-inside perimeter. The Android reference has no matching custom perimeter store; Wear renders its ordinary tactical boundary/area graphics.
- Wear reuses Android's tactical renderer. watchOS now shares the iOS phone's military marker artwork (496 NATO assets, 20 task symbols, affiliation frames, echelons and imported characters). Native utility glyphs use the same SF names as iOS. watchOS also shares all 30 iOS tactical control-measure drawings, projected by MapProxy and continuously updated with the camera. See [marker evidence](watch-symbol-artwork.md), [tactical rendering evidence](watch-tactical-graphics.md) and the watch README for exact limits.

## Navigation-lane map milestone

Both watch maps now display separate cached lane geometry: dashed L/R side
limits, a solid BS backstop and faint interior shading. Names are available
when zoomed in and in the scrollable map-info view. Limits follow linked line
edits; hiding/deleting a lane or its folder removes the whole lane from the
next complete scene. Missing linked geometry, oversized lanes and any dateline-
crossing lane part are omitted as a single counted item. No limit is thinned
or sent as a partial boundary. Both sides preserve intermediate backstop bends.

Each companion keeps at most eight lane groups, 160 vertices per limit and
256 per complete outline, within its existing whole-packet budget (48 KiB on
watchOS, 80,000 bytes on Wear OS). Normal field paths retain their existing
simplification policy; lane limits are complete or omitted. Legacy packets
without lanes remain valid and replace an older lane scene with no lanes.
Watch GPS remains the only source of the own-position marker. Overlay age and
omission counts remain explicit; cached shading is not a live boundary warning.

The Wear phone worktree integrates Android polish at `e6bb5c5` on top of the
release baseline (merge `761d907`), preserving the companion Application/Data
Layer service. The separate user Android checkout was not edited. Phone map
sync observes the real lane repository alongside graphics/folders/tracks.
The iOS bridge observes the real lane store and resolves a captured snapshot
on its existing generation-checked worker.

Validation: 358 core tests and all 150 iOS app integrations pass. New tests
cover extended/bent geometry, metadata, legacy replacement, missing links,
whole-lane count/byte/vertex limits, dateline rejection, store edits/visibility
and linked-line deletion. Android passes 385 phone and 24 Wear unit tests;
phone/watch debug and release builds and Wear release lint pass. Watch simulator
screenshots show day/night lanes and a real simulated Core Location marker;
expiry removes only the stale own-position marker. Actual WatchConnectivity
revision 27 delivered one lane with two waypoints/five field items; revision 31
persisted a complete zero-lane/zero-feature/zero-waypoint replacement. Wear
emulator day/night/zoom/info checks used a scene exported by the production
phone adapter's unit fixture, not a claim of paired Data Layer delivery.

Phone navigation-lane status synchronization is now implemented; see
[phone guidance](watch-phone-guidance.md). Independent watch crossing
detection/haptics, background watch navigation, offline packs/terrain,
and physical radio/GPS/battery/touch checks. All test simulators/emulators owned
by this work were shut down after the runtime checks; future runs should boot
only the device or pair they need.

## Phone guidance milestone

Both companions now show a distinct read-only Phone guidance section sourced
from the phone runtime owner. The shared packet covers all five confirmed lane
states, names and crossed limits, explicit stop and source/transport expiry.
Watch GPS/target metrics and quiet-inside monitoring remain separate. The
Wear phone branch now incorporates Android review `eacf084`; Claude confirmed
the additive evaluation fields and reserved those lines to avoid parallel edits.
See [contract and validation](watch-phone-guidance.md).

## TAK remote-layer milestone

Both maps now retain a separate remote scene, without server configuration,
watch connections or outbound sharing. Complete items are retained or omitted;
watch expiry never renews an unchanged stale time. Actual paired Apple delivery,
hide/clear and phone-off expiry pass. Wear round-screen day/night and cache
relaunch/expiry pass with an explicit standalone fixture. The user subsequently
paired the dedicated Android simulators: real Data Layer receipt/rendering, clear
and phone-emulator-off expiry now pass too. Subsequent paired populated-local
preservation and actual phone-guidance active/unavailable/stop/expiry also pass;
see [paired validation](wear-paired-validation.md). The paired Wear named-left/right/backstop and return-inside round now passes,
including phone-on-Home delivery and exact bent-limit preservation. Physical
radio/background/wrist checks remain. See [contract, budgets and evidence](watch-tak-layer.md).


## Receipt-bound phone guidance expiry, 27 October

Both watches now retain source/receipt/monotonic deadlines in their local cache.
Replay, app relaunch and wall-clock rollback cannot extend the original budget.
Legacy caches require a new phone packet; wire format and independent watch GPS
are unchanged. 504 Swift core and 39 Wear unit cases, Apple Release/paired Debug,
Wear Debug/Release/lint and Android phone Debug pass. Actual WatchConnectivity
and paired Data Layer deliver fresh decisions, then cached expiry survives
relaunch/disconnection. Runtime review also fixes Wear's prior-tick uptime
causing a transient false expiry on new delivery. Physical clock/wrist checks
and the recorded Wear host-process abort during cleanup remain separate.
See [behavior and exact evidence](watch-guide-expiry.md).

Original leg-range labels are implemented and validated on both watches; see
[exact packet, renderer and runtime evidence](watch-route-leg-ranges.md).
