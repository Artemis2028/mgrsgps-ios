# Hosted116 field triage

Run40847219380 uses exact source2c650e8cc3b5777b626e4df7c3e44c83b441e302.
Map job123357564304 passes. Field123357564578 fails; library123357564734 remains
active at this checkpoint. No cancelling push or duplicate dispatch.

The field artifact12889667980 is SHA256 verified:
`00c6af85dba283ebe8637c8043b8177b635fe46272c841b019281df11f32081b`.
It contains417 cases:405 passes,3 failures and9 opt-in skips.

- Route edit/visibility/delete/night relaunch stops at the map disclosure AX-value
  acknowledgement. Its usable recording shows the options rail open; the helper was
  still demanding the toggle's accessibility value; no usable-rail assertion ran.
- Intersection/resection/show/save/relaunch exceeds300s while changing the second
  azimuth. The trace repeatedly spends60s waiting for animation completion before
  native tap/long-press input events.
- Day enrollment form/invalid port also exceeds300s with repeated animation-idle
  waits during port entry. Invalid port0 prevents verification/network access.

The latter two recording attachments are ASCII placeholders, not usable movies.
No visual proof is claimed from them. Their retained spindumps show the app's main
runloop servicing events/idle rather than a locked main thread. One sampled map
update reapplies grid paint through an unchanged night-mode assignment; redundant
MapLibre styling is an avoidable source of transition churn, not established as the
sole cause of hosted timeouts.

The local follow-up makes enabled/night/light grid paint assignments idempotent,
while installation of a new map style still explicitly applies colors. The native
map helper now requires the actual visible, hittable rail after the same5s disclosure
wait. It retains all selected-action/result/edit/visibility/delete/resection/grid/
invalid-port/relaunch assertions and the original300s case limit. No SDK quiescence
bypass, native-text injection or larger time allowance is introduced.

All3 cases pass on iOS26.2: route65.572s, intersection/resection121.730s,
and day invalid-port form30.791s. Unsigned phone/watch/widget Release passes. Xcode5381
finishes TEST SUCCEEDED/exit0 after its600s post-test simulator diagnostic collector
ends; no parent cancellation or duplicate test was used. Final resection/grid/range,
invalid-port and night hidden-route captures were exported and inspected. Finite fake
GPS feed98458 is stopped/reaped and cleared. The separate exact dense library case also passes156.535s; both native parents are
terminal/reaped, the final fake GPS feed is stopped/cleared and the owned phone is off.
No fresh-hosted-green claim is made.
Ownership/evidence: `/tmp/mgrsgps-ci116-field-active.json` and
`/tmp/mgrsgps-ci116-field-repair.log`.

TAK stays off. This form test enters only fake localhost plus invalid port0 and makes
no server connection. No credentials, containers/database, merge or release action.
