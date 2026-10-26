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
active/unavailable/stop/expiry gates. Named lane crossings remain owner/adapter
and standalone rendering evidence on Wear; the earlier watchOS paired round
separately covers a named crossing. Physical locked-phone, request-triggered cold
start, radio/battery and wrist behavior remain open. Watches still do not execute
their own crossing detectors or background steering haptics. Current source
unit/build evidence remains 458 phone and 34 Wear tests plus Debug and unsigned
TAK-enabled Release; this round changes no app source or server configuration.
