# Hosted114 library triage — 29 October 2026

Run40821076335 library artifact12877929225 was downloaded and verified against API
SHA-256294f4bb85fefa1e1fb6af45e163985ab28fa5fbafb511dbac5e314ea734c0044,
then extracted under /tmp/mgrsgps-ci114-library. Full bundle:60 cases,59 passes,
one failure, no skips. The final42-case console block all passes because XCTest
restarted after the earlier dense-map300-second timeout; it is not the full result.

The strong dense accessibility case exceeds its allowance during the first
hide/show cycle. Initial marker-count checks pass; no907/924 mismatch is reported.
Repeated marker queries take16–21 seconds on hosted hardware. A sampled app main
thread spends substantial time drawing CALayer glyph backing stores and
TacticalMapOverlay/TacticalGraphicCanvas labels; this is not proof of a deadlock
or the sole timeout cause.

Source inspection finds concrete avoidable work: TacticalMapOverlay.update
filters the same graphics and calls setNeedsDisplay on every SwiftUI/GPS
publication, even with unchanged geometry, draft, palette, viewshed and ruler.
Camera delegate callbacks also redraw without comparing camera state. The staged
repair compares all those data inputs and actual centre/zoom/direction/pitch,
viewport/inset/canvas frame before requesting another paint. Geometry and style
changes still redraw; direct vertex-preview edits keep explicit display requests.
No marker/graphic cap, item hiding, assertion weakening or allowance increase.
All native views and overlays remain available.

The exact dense marker/count/hide/show/camera/night case passes locally168.538s
with the same3-second moving GPS feed, retaining all native marker/count and
camera assertions. Independent unsigned phone/watch/widget device Release passes.
Xcode parent8245 finalized exit0 / TEST SUCCEEDED. Existing route insert/kink/
drag/save/edit/relaunch and fixed ring/sector/night workflows also pass57.350s/
56.005s, parent35612 exits0. Dense night, route drawing and night ring/sector
captures inspected; extreme-density label overlap remains explicitly recorded.
Every phone test/build/feed parent reaped, fake GPS cleared and owned phone
simulator off. This local result does not prove the hosted timeout resolved;
fresh full hosted confirmation remains open.

Evidence: /tmp/mgrsgps-ci114-library-job.log,
/tmp/mgrsgps-ci114-library-summary.json,
/tmp/mgrsgps-ci114-library/screenshots/ui-tests/35DB88DC-3C72-42D2-867F-350F2B0C2FA4.txt,
/tmp/mgrsgps-ci114-tactical-redraw.xcresult and matching log,
/tmp/mgrsgps-ci114-tactical-redraw-feed.log and
/tmp/mgrsgps-ci114-tactical-redraw-release.log.
Active owners/next step: /tmp/mgrsgps-ci114-active-work.json. TAK stays OFF;
no GO/connection/credential/infrastructure/merge/release action.
