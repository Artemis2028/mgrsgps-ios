# Quiet-boundary edits and monitor checkpoints

Boundary geometry validation, JSON encoding and replacement-file staging now run
on workers for ordinary saves, deletes and monitor start/stop checkpoints.
Startup and confirmed additive restore already prepare on workers. A FIFO MainActor
gate serializes every boundary write from preparation through atomic publication;
source metadata checks, the final rename, small staging-directory cleanup and
observable-state publication remain on Main. Existing limits stay at 100 boundaries, 256 vertices per boundary
and 2 MiB for the document. Lock-compatible file protection is preserved.

A changed external source is refused, including replacement while a new file is
staged. Confirmed deletion also checks the original area so a stale confirmation
cannot delete a newer edit. A failed publication keeps the prior file and memory;
a confirmed save/restore survives view dismissal and caller cancellation. Drawing
keeps its draft until the save succeeds. A late completion dismisses only the
same still-visible draft, and point/name editing is disabled during that save.
The saved-boundary panel exposes write progress and keeps Stop available.

Stop immediately invalidates pending starts, stops its location driver and alerts,
and clears active runtime state. Its off checkpoint is queued afterward. A stopped
start cannot publish its staged active marker or re-arm alerts. A restart waits for
queued writes; a completed newer start keeps its active interruption marker. No
monitor starts before the active marker has published. If iOS terminates the
process before an off checkpoint finishes, reopening can conservatively show the
old interruption notice; it still never resumes GPS or alerts automatically.

The user-requested quiet-inside behavior is unchanged: heading/route steering
remain separate; confirmed exit, outside silence, reentry/rearming and the
background notification policy are unchanged. This is an iOS persistence change,
not a new Android wire or interchange format. Android release/1.1.0 remains
`482b417`; the optional quiet-boundary backup extension keeps its existing contract.

## Validation

- `/tmp/mgrsgps-boundary-worker-native.xcresult`: 69 selected native integration
  cases pass (22 boundary, 14 service startup and 33 navigation). New cases hold
  an independently staged file to verify stop during preparation, immediate stop
  and queued restart, cancelled confirmed edit plus queued restore, and external
  replacement during staging. The maximum 100-by-256-vertex ordinary edit/delete
  case permits MainActor progress and reopens every remaining vertex. Existing
  failed-write retry, corrupt-file preservation, interrupted relaunch, precise
  permission loss, background driver configuration and independent guide checks
  also pass. This is a scoped run, not a full-suite claim.
- `/tmp/mgrsgps-boundary-worker-ui.xcresult`: all four simulator boundary
  workflows pass, including straight drawing/point movement/save/relaunch,
  direct line dragging, actual Core Location background exits and interrupted
  restart, and night editing with accented names/Keep/confirmed deletion/relaunch.
  The background screenshot records two exits. Day library, drawing, night edit
  and night empty-library screenshots were inspected. App text stays readable;
  native keyboard/navigation-title colors remain system-managed.
- `/tmp/mgrsgps-boundary-worker-release.log`: unsigned device Release succeeds
  for phone, watch and widget. Eight Python harness checks pass in
  `/tmp/mgrsgps-boundary-worker-harness.log`. The UI runner and Release parent
  finish naturally with exit 0. The fake feed is stopped, simulated location is
  cleared and the only owned simulator is shut down. Full hosted103 is still
  running on the preceding `bc52ed8`; this local candidate does not cancel it.

Physical locked-screen delivery, Focus/sound settings, process suspension,
storage pressure and resource profiling remain device checks. Independent watch
boundary alerts/background guidance and the real enrolled TAK exchange/renewal
remain separate open work. No server or credentials were changed.
