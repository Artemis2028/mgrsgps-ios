# Optional watch background lane alerts — 29 October 2026

watchOS has an explicit Screen-off alerts option, off by default. Starting a
cached lane with that option requires precise watch location and notification
permission. It owns a foreground-created CLBackgroundActivitySession and a
continuous location manager configured for background location. Its freshness
clock belongs to the model/session, not a displayed SwiftUI view. Ordinary
foreground-only sessions still disarm when the watch app leaves the foreground.
Stopping, losing authorization, changing execution mode or replacing lane
geometry releases the owner. A process restart never auto-arms from saved data.
Invalid fixes/errors clear pending crossings and playback immediately.

The lane stays quiet before entry, inside and on return. Confirmed outside
states produce one named system notification per state/ excursion; fresh GPS
recovery can renew the already-confirmed outside warning. No one-second stream
of repeated system alerts. Each notification includes Stop wrist alerts, and
stopping clears its pending/delivered requests. The existing foreground native
haptic cadence remains separate, as do phone guidance and quiet-inside polygons.

Apple documents foreground-started continuous background location sessions in
[Enabling Background Sessions](https://developer.apple.com/documentation/watchkit/enabling-background-sessions).
Its [play documentation](https://developer.apple.com/documentation/watchkit/wkinterfacedevice/play(_:))
says direct watch haptic calls have no effect while inactive/background outside
an active workout. This navigation feature uses location and system notifications;
it does not create a workout or unrelated extended runtime. Background notices
use the system sound/haptic behavior and respect notification permissions,
Focus and watch settings; they do not reproduce distinct custom direction
patterns. Physical delivery, wrist lock, battery and haptic feel remain gates.

Validation:

- All597 core cases pass; twelve focused watch policy cases pass, including
  foreground consent, real-owner requirement, background entry/crossings,
  duplicate notice suppression, quiet returns, stale/gap and scene-change rules.
- Current watch simulator build and unsigned phone/watch/widget Release pass.
  The generated watch Info.plist contains the required location background mode.
- A40mm paired watch/phone simulator uses explicitly synthetic cached geometry
  and actual Core Location callbacks. The native crown sends the app behind the
  clock; callbacks continue with foreground=false. Confirmed Creek/left and
  Road/right system notifications are displayed. Notification opening returns
  to Inside in the same repaired process11446. These are OS-delivered notices,
  not injected lane decisions. The bent Power line backstop also produces its
  named turn-back notice. The notification Stop action returns to the clock;
  reopening retains process11446 and shows Wrist alerts off. With Screen-off
  alerts disabled, starting inside and pressing the crown disarms the session;
  reopening the same process shows Paused and requires an explicit Start.
  Current background stale/poor-fix rules are covered by core policy tests;
  physical GPS interruption and notification behavior remain runtime gates.
- Runtime found a real notification-response crash: the async delegate thunk
  completed UIKit state restoration off the main thread. The retained report
  is /Users/apollo/Library/Logs/DiagnosticReports/GridFixWatch-2026-10-29-065642.ips.
  Explicit completion-handler delegates now invoke completion on MainActor.
  Opening the repaired notification preserves the PID/session and no new crash.
- The fake GPS feed is stopped/reaped, both owned simulators are shut down,
  both simulated locations are cleared, and the watch preference backup was
  restored byte-for-byte. No server or real positions. Captures are retained
  under /tmp/mgrsgps-watch-background-fixed-*.png; native callback diagnostics
  record age/accuracy/execution state, never coordinates.
- Full core log: /tmp/mgrsgps-watch-background-core-full.log. Final focused
  log: /tmp/mgrsgps-watch-background-notice-core-final.log. Repaired simulator
  build: /tmp/mgrsgps-watch-background-response-fix-build.log. Repaired device
  Release: /tmp/mgrsgps-watch-background-response-fix-release.log. All parents
  are terminal. Held locally while hosted113 validates pushed a54ac75.

Wear OS's matching background owner is now implemented in Wear4faf220 and passes
a real native API34 component runtime (55.583s), including background GPS/cadence,
notification Stop and stale/quiet holds. Its visual toggle/notification and
physical-wrist checks remain open; see the Wear checkout's
docs/watch-background-lanes.md. Independent
heading/route guidance and offline/terrain transfer remain separate open work.
