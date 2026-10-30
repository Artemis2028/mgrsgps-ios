# Saved navigation startup

Normal app startup prepares the saved navigation-session snapshot on the shared
worker before constructing live navigation services. The existing strict
less-than-2-MiB session limit now has a metadata preflight before the file is
read. Decoding and route-point/index validation run on the worker.

The main-actor handoff checks source-file identity/size/modification metadata,
including missing-file states. A newly created, removed or replaced source
triggers another preparation before app services are published. Direct setup
callers retain the existing synchronous initializer; a prepared snapshot for
another directory is refused. Invalid, oversized or unreadable sessions remain
preserved and cannot start GPS or feedback until explicitly cleared.

Saved route identity, vertices, checkpoint index and haptic preference are
retained. Every restored route starts paused, including one that was active
when the app closed. Navigation GPS and cue playback require explicit resume;
reading a saved active flag never restarts them. Field-library readiness still
gates resume and route validation.

## Validation, 26 October 2026

- Full native suite passes 259 cases, with four unstaged opt-in local checks
  skipped and zero failures. New coverage checks source creation/replacement/
  removal, corrupt/oversized/invalid route data, wrong-directory snapshots and
  app-bootstrap preservation. The interrupted-route case prepares on a worker
  and verifies unchanged bytes, paused progress, retained haptics and no driver
  start or feedback playback.
- Actual simulator navigation passes import, ordered automatic advance, pause,
  cold worker startup at point 2, explicit resume, background completion and a
  further relaunch retaining Route complete:
  `/tmp/gridfix-navigation-startup-final.xcresult`. Paused/completed screenshots
  were inspected. Tests completed successfully; only the identified stalled
  supplementary simulator-diagnostics child was terminated afterward to finalize
  the parent result.
- Final phone/watch/widget Release passes:
  `/tmp/gridfix-navigation-startup-release.log`.

Settings/other session startup sources, older library actions, dense rendering
and physical field/locked-screen behavior remain separate work. This does not
change steering patterns, quiet-inside perimeter monitoring or lane alert policy.
