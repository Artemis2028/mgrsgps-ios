# Hosted117 library triage

Run40863515930 on ea06859617b150a38055268e50f9c0ec1b67dc86 is fully terminal:
map succeeds, field fails, library fails. Library xcresult records60cases:
57passed,3failed,0skipped. A following folder-course attempt also fails app
termination after the dense timeout; its automatic retry passes, so it is not an
additional final failed case. Artifact12899745867 (`mgrsgps-ios-117-library`),
archive SHA256:
`7bb6c050f0edf3562c453d51b935c8d4fbd08f9324bb4c066f80ec084282f79c`.

## Recorded failures

- Dense map accessibility reaches the300s allowance while activating map options;
  final failure317.078s. Before that, two complete marker-count queries take roughly
 14s each. No marker-count mismatch is reported. Spindump samples show app main
  thread activity in Core Animation/MapLibre rendering rather than establishing a
  permanent application deadlock. This remains a performance/interaction gate.
- Large library search/grid/night fails74.019s because a usable options rail was
  not acknowledged. Actual recording shows the Map tab selected while library
  content is still visible at60s, then the dense map at68s with the plus still
  closed. This does not support treating the rail as already open. No speculative
  weakening of rail visibility or timeout was made.
- Protected settings backup reaches300s while entering the password after native
  Files reopening. It reaches the actual secure prompt around297s; no wrong-password
  acceptance, data-loss or restore mismatch is demonstrated by this timeout.
  Spindump shows active SwiftUI layout. Password values are omitted from this report.

The field117 helper repairs remain separately validated (full imported name and
lane switch/reminder persistence/night). They do not by themselves prove these
library failures resolved.

## Independent product follow-up and local checks

Waypoint-caption collision/contrast work keeps every native marker, coordinate,
tap target and full AX name. A cold-day capture exposed public SDK visibility
queries returning nil despite5000attached views; label layout now uses owned
attached views and actual geometry. The final behavioral source passes four
layout cases and the unchanged full dense/count/visibility/camera/night case in
150.303s, with actual day/night captures inspected. See map-waypoint-labels.md.
This is a local dense-case pass, not a hosted performance guarantee.

The other two exact failed library cases now pass locally on clean source
(temporary numerical probe removed), with hosted300s default/600s maximum
execution allowances: search/grid/night44.573s and protected backup133.329s.
Parent73259exit0/reaped, log/tmp/mgrsgps-ci117-library-local.log,
result/tmp/mgrsgps-ci117-library-local.xcresult. Existing assertions for full counts,
password rejection, durable restore and night behavior remain. All three final
failed library cases have corresponding local passes; this does not change the
failed117result or establish hosted confirmation. No push cancelled117 and no duplicate was dispatched.
All positions are synthetic. TAK stays off; enrolled exchange/renewal requires
coordinated GO. No server/container/database, credentials, merge or release action.
