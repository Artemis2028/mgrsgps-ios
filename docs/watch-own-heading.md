# Watch-owned compass readout — 29 October 2026

WatchModel now owns foreground CoreLocation heading updates alongside its own
location session. Navigate displays a separate WATCH HEADING when a true-heading
callback has calibrated accuracy in0...25 degrees, belongs to the current
foreground session and is no more than five monotonic seconds old. It also
requires the existing fresh precise watch GPS gate. Native true heading is
converted through the existing WatchSnapshot true/magnetic/grid and angle-unit
contract, including its WMM/manual-declination availability rules. No heading or
position comes from phone guidance, the cached scene or movement-course inference.

Leaving the foreground stops heading updates and clears the sample even when
optional wrist-lane background location remains active. Permission loss and GPS
failure clear the sample; old queued callbacks cannot cross a new foreground
session. Future/invalid/uncalibrated callbacks cannot produce a number. Unsupported
compass hardware and missing/expired true heading display unavailable rather than
zero. Some hardware can expose magnetic data before true heading; this initial
readout deliberately waits for native true heading instead of estimating it.

The installed watch SDK's CLLocationManager header explicitly marks
headingAvailable/startUpdatingHeading available on watchOS2+. Four core cases
cover full-circle/accuracy endpoints, invalid/nonfinite/un-calibrated data,
prior-session/future/expired callbacks and monotonic rollback. All613 core cases
pass. Unsigned phone/watch/widget device Release passes; parent processes reaped.
Evidence: /tmp/mgrsgps-watch-heading-core-final.log and
/tmp/mgrsgps-watch-heading-release.log.

This is the own-heading readout foundation, not completed steering or route
progression. A native40mm watch simulator run now shows the fake cached target, own simulated
GPS distance/bearing and WATCH COMPASS UNAVAILABLE together at ordinary text size.
No compass value is injected. Terminate/relaunch retains the fake target; clearing
GPS suppresses navigation numbers in night mode. The accessibility3 capture uses
the existing scrolling navigation layout; its lower heading row/touch reachability
was not verified. Genuine compass callbacks, Home/locked scene transitions and calibrated readings
remain gates requiring further native/physical testing. A late single-fix recovery attempt did not update
the displayed fix and is not counted as a pass. Both simulators are off, feeds
reaped, synthetic GPS cleared and original watch preferences restored byte-for-byte.
Evidence: /tmp/mgrsgps-watch-heading-day-fresh.png,
/tmp/mgrsgps-watch-heading-night-final.png and
/tmp/mgrsgps-watch-heading-night-large.png. Genuine calibrated readings require a
physical compass-capable watch. No injected heading or new WatchConnectivity,
background-steering, haptic, battery, physical or enrolled-TAK verification claim.
Independent watch route/steering owners and offline/terrain transfer remain open.


## Native GPS recovery follow-up

On the same40mm watch process, a3-second moving OS GPS feed produces fresh
location/navigation; stopping it and clearing location suppresses distance/bearing
after the normal10-second fix gate. One replacement simulator fix did not refresh
the displayed sample despite a longer wait. Restarting the moving OS feed restores
fresh distance/bearing in the same process, with no relaunch or app-state injection.
This closes repeated-feed recovery, not reliable single-fix CoreSimulator delivery.

A subsequent night relaunch also shows fresh distance/bearing and explicit
WATCH COMPASS UNAVAILABLE. Native callback diagnostics report age around0.001s,
accuracy5m, foreground/authorized/precise true. No heading is injected or generated;
true compass callbacks and Home/lock/physical gates stay open. Captures inspected:
/tmp/mgrsgps-watch-recovery-before.png,
/tmp/mgrsgps-watch-recovery-expired.png,
/tmp/mgrsgps-watch-recovery-single.png,
/tmp/mgrsgps-watch-recovery-repeated.png and
/tmp/mgrsgps-watch-recovery-night-fresh.png.

Native console /tmp/mgrsgps-watch-heading-recovery-night-console.log retains
callback evidence; first console used a buffered pipe, so it is not used to time
individual callbacks. Both feed parents and both console launch parents are
reaped; fake GPS cleared, watch off and original preferences restored byte-for-byte.
No phone/server connection, real compass, touch/large-text lower-row or background
steering validation claimed.


Steering subsequently uses a stricter2s sensor deadline aligned with Android;
the display-only5s retention cannot authorize steering or queued effects. See
watch-own-steering.md for the coordinated contract and deliberate mode differences.
