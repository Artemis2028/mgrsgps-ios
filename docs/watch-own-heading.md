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
was not verified. Fresh GPS recovery after clearing, genuine compass callbacks,
Home/locked scene transitions and calibrated readings remain gates requiring
further native/physical testing. A late single-fix recovery attempt did not update
the displayed fix and is not counted as a pass. Both simulators are off, feeds
reaped, synthetic GPS cleared and original watch preferences restored byte-for-byte.
Evidence: /tmp/mgrsgps-watch-heading-day-fresh.png,
/tmp/mgrsgps-watch-heading-night-final.png and
/tmp/mgrsgps-watch-heading-night-large.png. Genuine calibrated readings require a
physical compass-capable watch. No injected heading or new WatchConnectivity,
background-steering, haptic, battery, physical or enrolled-TAK verification claim.
Independent watch route/steering owners and offline/terrain transfer remain open.
