# Paired Wear populated-library and guidance validation

26 October 2026, dedicated API 37 phone and 192 dp round API 34 watch.
Both Google node graphs identify the expected connected peer. Current matching
Debug APKs were installed without clearing app data. No server was used.

## Populated local scene and independent TAK layer

A synthetic GPX was opened through the phone's real FileProvider/import flow:
one waypoint `PAIRED LOCAL CAFÉ`, one two-vertex route and one two-point track.
All three reached the watch's actual Data Layer cache. The native phone Navigate
action selected the waypoint; its matching target reached the watch too.

The explicit debug-only phone TAK preview sent four remote items through the
real `/gridfix/tak/v1` path. The watch persisted all four complete items and its
inspected info screen listed TEAM ONE, OP CAFÉ, ROAD and NAI 2. A phone clear
then arrived as an empty remote scene. At both stages, assertions compared the
complete populated local map, selected-target/settings and inactive-guide
payloads against their baseline, excluding only normal publisher revision/time
fields. Local digit/night/grid overrides also stayed unchanged. No watch cache
was injected and no local item was hidden to make this pass.

Evidence: `/tmp/gridfix-wear-populated-baseline.xml`, `-show.xml`, `-clear.xml`,
and `/tmp/gridfix-wear-populated-remote.png`.

## Actual phone-guidance lifecycle

Real emulator GPS callbacks and the native phone Haptic Guide toggle produced
active/available packets from PocketGuideService for the selected target. The
watch displayed `Turn right · two short taps`, phone age and the read-only/no
watch-alerts caption. No guide decision or receiver cache was injected.

Disabling the phone's actual location provider produced an active/unavailable
packet, and the watch replaced steering with `Phone guidance unavailable`.
The provider was restored. Stopping with the native toggle sent revision 66,
inactive and without a target; the watch displayed `Phone guide off`. Starting
again delivered fresh active/available revision 69. Force-stopping the phone
prevented further delivery; at 29 seconds the watch displayed `Phone guidance
expired · open phone` while its own GPS remained fresh.

Evidence: `/tmp/gridfix-wear-guide-{start,active,unavailable,stop,before-kill}.xml`,
`/tmp/gridfix-wear-guide-expired-ui.xml`, and inspected screenshots
`/tmp/gridfix-wear-paired-guide-{active,unavailable,stop,expired}.png`.

An earlier app-ops attempt did not withhold this emulator's callbacks and did not
establish unavailability; the successful check uses the verified disabled
provider. A first stop assertion ran behind the OS location warning; after
dismissing it, the native toggle and receiver assertion passed. No product
assertions were weakened. App-ops and the provider were restored. The remote
preview was cleared; the labeled synthetic local records remain in the dedicated
test phone for later regressions. Both apps, the owned fake-location feed and
both emulators were stopped afterward.

## Scope

This closes paired simulator populated local/remote preservation and guidance
active/unavailable/stop/expiry gates. Named left/right/backstop crossings and return-inside states now have paired
Wear service evidence below; the earlier watchOS paired round separately covers
a named crossing. Physical locked-phone, request-triggered cold
start, radio/battery and wrist behavior remain open. Watches still do not execute
their own crossing detectors or background steering haptics. Current source
unit/build evidence remains 458 phone and 34 Wear tests plus Debug and unsigned
TAK-enabled Release; this round changes no app source or server configuration.


## Named lane crossings through the paired service, 27 October

The same dedicated API 37 phone / round API 34 watch pair now verifies named
lane states from the real PocketGuideService through actual Data Layer delivery.
No guide packet, receiver cache or navigation repository was injected. A small
synthetic backup was chosen through Settings → Restore; it additively imports
one objective and one lane, leaving settings and the existing local library.
The generic Open-with ZIP handler routes to text import rather than this backup
workflow; that first attempt imported nothing.

The lane has three vertices per left/right/backstop line, including bends, and
labels Bear Creek, Ridge Road and Power Line. The phone's native Navigate button
selects the objective; its native Haptic Guide button starts guidance. Real
emulator GPS callbacks produce the following received, active/available states:

| Phase | Watch state | Named crossed limit | Phone status rendered on watch |
| --- | --- | --- | --- |
| Inside | INSIDE | None | In the lane · silent |
| West crossing | OUT_LEFT | Bear Creek | Turn right · two short taps |
| Return inside | INSIDE | None | In the lane · silent |
| East crossing | OUT_RIGHT | Ridge Road | Turn left · one long pulse |
| Return inside | INSIDE | None | In the lane · silent |
| Beyond backstop, phone on Home | OVERSHOT | Power Line | Turn back · three long pulses |
| Return inside, phone on Home | INSIDE | None | In the lane · silent |

Each assertion requires a newer guide revision, active=true, available=true,
the correct lane/objective names and the exact crossedLine (absent inside).
At the background crossing, dumpsys reports NexusLauncher as foreground. This
proves simulator Home/background delivery, not physical screen-lock behavior or
felt haptic patterns. The watch explicitly displays read-only/no watch alerts.
Night crossing screenshots and the actual map were inspected.

The received map retains every original local feature as an exactly equal decoded
feature object and all three vertices of each new limit, with the exact
three labels. The paired map renders the lane with watch GPS and existing
waypoint/route/track overlays. A native guide stop delivers inactive/unavailable
and removes lane/target guidance fields. Native confirmed lane deletion sends a
complete zero-lane scene while retaining all four local features. Native
objective/empty-folder deletion and original target reselection then restore the
original three map features, original target and local digit/night/grid overrides.
The test feed is stopped, apps force-stopped and both owned emulators shut down.
User pairing and account setup are retained; no server or container is touched.

Evidence: `/tmp/gridfix-wear-lane-{inside,left,inside-after-left,right,inside-after-right,backstop-home,inside-home,stopped,deleted,cleaned}.xml`,
`/tmp/gridfix-wear-lane-{left,right,backstop-home,map}.png`,
`/tmp/gridfix-wear-lane-feed.log`,
`/tmp/gridfix-wear-named-lane-manifest.json`, and the phone UI restore/delete logs.
`gridfix-wear-lane-receipt.py` controls only the host fake-location feed and reads
actual receiver preferences; it does not write app decision/state data.

This closes the paired named-left/right/backstop and return-inside Wear gate.
NOT_YET still has owner/adapter and standalone evidence, rather than a new paired
case in this round. Physical locked-phone/cold-start/radio/battery/wrist checks
and independent watch crossing/background haptics remain separate. Source and
build counts stay at 458 phone / 34 Wear tests; this round changes no app code.
