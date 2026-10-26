# Live track recording — Android 1.0.4 parity

Reference: `gridfix` main `94c4cc4`, `TrackRecorderService.kt`,
`TrackRepository.kt`, and the map's Stop recording dialog.

## Recording behaviour

Start from Map's record button or the Routes & Tracks library. Starting requires
the app to be in the foreground, location authorization, and Precise Location.
Recording does not require a fix already on screen. A banner on every tab shows
saved point count and distance; tap it for the recording panel. Close the panel
to keep recording. Save optionally names the track (up to 30 characters);
Discard requires confirmation. Explicitly saving an empty recording keeps an
empty track, matching Android. An interrupted recording with no points is removed.

Accepted fixes have finite, nonnegative accuracy at most 30 m. After the first
fix, save a point when movement is at least 5 m, or when more than 15 seconds
have elapsed and movement exceeds 1 m. The anchor is the last successfully saved
fix, not the latest received fix. Duplicate/reversed uptime is rejected. These
are Android's thresholds; waypoint/navigation's separate 25 m policy does not
filter the recorder. Batched Core Location updates are processed in order.

Core Location does not expose Android's elapsedRealtimeNanos on each location.
The adapter translates each timestamp to uptime using one wall-clock/uptime pair
per delivered batch. Filtering uses that translated uptime; wall-clock timestamp
order alone never decides whether movement is logged. Cached pre-start fixes,
invalid coordinates, unavailable accuracy, negative timestamps, and fixes more
than one second in the future are rejected. Core Location's orthometric/MSL
`altitude` is logged only with a finite positive vertical accuracy. Missing height
uses Android's -32768 sentinel and is omitted from GPX.

The live red trace is separate from finished track overlays. Its preview keeps
at most 4,000 points, dropping to the newest 2,000 when full, matching Android's
memory bound. Every accepted point remains in the durable log. Final distance
and count are recalculated from the stored seven-decimal coordinates. Existing
backup/GPX exports include finished tracks; Save the current recording before
exporting its data.

## Background and locked screen

A dedicated CLLocationManager is created on the main actor, independent of the
position/compass manager. Recording sets:

- `allowsBackgroundLocationUpdates = true`
- `showsBackgroundLocationIndicator = true`
- `pausesLocationUpdatesAutomatically = false`
- best-for-navigation accuracy, no distance filter, and fitness activity type

The app declares `UIBackgroundModes: [location]`. The ordinary scene background
handler stops only position/heading updates. It never stops the recorder. Stop,
discard, permission loss, and terminal write errors stop recording's manager
and disable its background updates. Temporary GPS errors keep waiting.

This uses the foreground-started continuous-location path supported with When
In Use permission; it does not request Always access. The system supplies its
background location indicator rather than Android's foreground-service
notification. Keep screen on is independent: manually locking the screen should
leave recording active. The app must have been unlocked once after boot before
its recording files are available.

Force-quitting, rebooting, OS termination, or revoking permission can end location
delivery. There is no promise to restart a recording automatically. On next launch
an interrupted log is finalized and reported in a recovery banner, matching
Android's orphan-finalization policy.

## Durable data and failures

`TrackRecordingJournal` uses `Documents/LiveRecording/session.json` and
`points.txt`. All journal operations run on one serial utility queue. Each
accepted row is written and synchronized before updating live state. Appends
are bounded to the backup-compatible 250,000 points / 16 MB per log; hitting a
limit stops recording and keeps the saved log. Metadata and point files use
Complete Until First User Authentication protection, as does the final archive,
so they remain accessible after the screen locks.

Stop first stops location delivery, drains already queued fixes, seals metadata,
and publishes the finished track to FieldDataStore. Only a successful archive
commit permits journal cleanup. An archive failure leaves the journal and offers
Retry saving. Repeating publication after an interrupted cleanup is idempotent;
a conflicting track ID with different bytes is never overwritten. A failed
append stops queued writes and preserves earlier rows. Recovery drops only an
incomplete final row; a malformed complete row or metadata file is preserved
and reported, with explicit discard available.

Finished tracks now use an atomic v2 index and independent point logs, removing
the former combined archive budget. The per-log application bounds above still
apply. This is an application limit, not an iOS restriction. See
[finished-track storage](finished-track-storage.md) for migration and export bounds.

## Verification

Core tests cover thresholds, monotonic ordering, clock changes, rejected-fix
anchors, bounded preview with all durable points retained, stop ordering,
partial tails, malformed logs, append/write failures, final publication retry,
ID conflicts, empty tracks, discard, and relaunch recovery.

App integration tests use an injected driver and clock for foreground/background
lifecycle, batched fixes, permission changes, delayed permission grants, transient
versus denied location errors, archive failures/retry, and corrupt-journal
preservation. A real-manager test checks background configuration and the app's
location background-mode declaration. On a physical device it also checks file
protection attributes; Simulator does not implement Data Protection classes.

`TrackRecordingWorkflowTests` uses **real Core Location callbacks** from a moving
simulator location feed supplied by `scripts/recording-test-route.py`, outside
the app. It checks background point growth, save/library/map, confirmed discard,
and process termination/relaunch recovery. CI feeds locations across test app
reinstalls and relaunches, revokes the screenshot step's Always grant, and verifies
that the real manager has only While Using authorization. The host observer
`scripts/recording_background_check.py` reads the actual append-only journal
twice while the app stays on Home. Acknowledgements go only into the UI runner's
temporary directory. The UI test cannot reactivate the app until the observer
confirms additional complete point records in the same recording session; a
replacement session, zero starting points or no growth fails the check. This
excludes fixes received during foreground transitions from the evidence.

A physical locked-screen walk remains required before release: with While Using
and Precise Location, start a track, walk with the phone locked for at least ten
minutes, unlock and confirm the trace/point count grew, save, and inspect GPX.
Repeat while using another app and with Low Power Mode. Revoke location access
mid-recording, then confirm earlier points recover. Repeat after a force quit
and after a reboot/first unlock. Simulator background tests do not establish
physical locked-screen GPS delivery, Data Protection, battery use, or OS-kill
behaviour.

## Apple references

- [Background updates with CLLocationManager](https://developer.apple.com/documentation/corelocation/cllocationmanager/allowsbackgroundlocationupdates)
- [Handling background location](https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background)
- [File protection for background apps](https://developer.apple.com/documentation/uikit/encrypting-your-app-s-files)
- [Core Location MSL altitude](https://developer.apple.com/documentation/corelocation/cllocation/altitude)

## Worker-staged archive finalization

The Android finishTrack source was rechecked at 56acca2: it computes the complete
log's statistics and updates its finished metadata through the repository. iOS
retains its journal-first ordering, but now prepares the complete finished-data
archive on a worker using FieldDataStore's scoped edit path. Only revision
verification, atomic rename and Main-thread publication return to the UI actor.
The journal is acknowledged only after that publication succeeds.

A concurrent library edit discards stale preparation and rebases the recording
onto the latest document. Repeating recovery after archive publication preserves
newer folder/visibility metadata when the point bytes already match. A conflicting
ID never replaces the saved log; archive failure leaves the journal pending.
Staging uses the existing lock-compatible file protection option. Physical
Data Protection and locked-screen delivery still require the checks above.

439 core tests pass, including staged/no-early-publication, concurrent graphic
retention, metadata-preserving retry, failed atomic publication and conflicting
log bytes with the journal retained. All 194 native cases pass with two unstaged
opt-in local TAK skips. The recorder's actual document publication is observed
on Main; existing permission, failure/retry and queued-fix checks still pass.

All three real-location recording UI workflows pass on the single iOS 26.5
test phone: background point growth/save/library/map, process relaunch recovery
and confirmed discard. The actual recording sheet and finished details were
inspected for readable text. Final phone/watch/widget simulator Release passes.
Evidence: `/tmp/gridfix-recording-staged-native.xcresult`,
`/tmp/gridfix-recording-staged-core.log`,
`/tmp/gridfix-recording-staged-release.log` and recording captures under
`/tmp/gridfix-recording-staged-screens/`. The host feed is stopped and owned
phone shut down after checks. Simulator Home/background is not a physical
locked-screen walk.


Local finished-library storage now uses an atomic v2 index and independent point
logs, rather than the bounded backup ZIP. See [migration, limits and validation](finished-track-storage.md).
The journal is still acknowledged only after successful publication.

## Background journal observation, 26 October

All three recording workflows pass on iOS 26.2 with While Using authorization.
The host observed the same session grow from 3 to 6 durable points during the
eight-second Home interval, before the app could reactivate. Saving, library
details and map overlay checks then passed. Relaunch recovery now exercises the
shared startup worker and still leaves recording inactive. Confirmed discard
also passes. Eight Python harness tests pass; these validate the observation
protocol and route helper, independently of the real Core Location UI evidence.

Evidence: `/tmp/gridfix-ios262-recording-observed.xcresult` (exit 0),
`/tmp/gridfix-ios262-recording-observed-background-check.log`. The earlier
foreground-only count comparison is no longer the background proof. The
physical locked-screen walk and Data Protection checks remain open.
