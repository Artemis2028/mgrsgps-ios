# Backtrack source integrity and long logs

The Android reference is `release/1.1.0` (`482b417`),
`app/src/main/java/app/gridfix/android/data/TrackSimplify.kt`.
`simplifyTrackToBudget` keeps both ends, chooses the largest segment deviation
first, uses the lower split index on ties, wraps longitude and limits the
reverse route to 64 vertices at a 20-metre requested tolerance. Exhausting the
budget does not guarantee that tolerance. Those rules are unchanged on iOS.

Backtrack previously checked only that its track ID still existed after worker
calculation and folder publication. Replacing that ID could publish geometry
from the older recording. A replacement during the final ordinary edit could
also be rebased under the old source-derived route.

The action now captures immutable bytes, current metadata and the store's
identity/revision. Calculation runs on a worker with cancellation forwarding.
A source change during calculation retries from the latest snapshot, including
its name and folder. After folder publication, and again after route staging,
a changed source fails visibly for retry. No suspension occurs between the
last source check and atomic publication; the prepared edit's revision and
on-disk source checks also remain in force. A cancelled calculation or staging
cannot publish late output. The original log and selected navigation target
remain unchanged; creating a reverse route does not start guidance or GPS.

Local decoding validates every row while retaining one GeoPoint array for the
exact random-access simplifier. It no longer builds a full TrackPoint array,
a reversed coordinate copy or a full-length Boolean keep array. Reverse index
access and a budget-sized set retain original order and priority. Cancellation
is checked during decoding, coordinate validation and segment scans.
This is still linear coordinate memory, not constant memory. Very large dense
tracks, worst-case simplification CPU and physical device memory remain
validation work. Local logs remain independent of external backup/watch caps.

## Validation, 27 October 2026

All 499 core cases pass in `/tmp/mgrsgps-backtrack-core-final.log`. Added
coverage checks actual rows despite incorrect metadata counts, dateline and
out-and-back geometry, malformed interior rows, local logs beyond 250,000
points and cancellation. Existing priority, budget, ordering and endpoint
fixtures remain green.

All 316 native cases pass (four unstaged opt-in skips) in
`/tmp/mgrsgps-backtrack-source-verified.xcresult`. Added integration tests hold
real worker calculation/staging while replacing, deleting or cancelling the
source, then check durable results. Same-ID replacement during folder
publication cannot save the old geometry; failed storage preserves the source.
The 300,003-point native check produces three vertices in about 0.659 seconds
with 332 MainActor pulses, keeping the exact log and target. This is simulator
responsiveness evidence, not a physical device benchmark.

The same final bundle passes all three selected UI workflows: mixed-library
backtrack, details-screen backtrack and day/night graphic choices/route cards.
Route/map and palette screenshots were inspected. The xcodebuild parent exits
0 naturally. Unsigned device Release passes in
`/tmp/mgrsgps-backtrack-source-release.log`. The owned simulator and feeds are
off after validation. Full hosted confirmation remains open; hosted101
40429934209 is confirmed live on39da6e4, so these follow-ups stay local without
cancelling it. No infrastructure or real-server test is needed for this work.
