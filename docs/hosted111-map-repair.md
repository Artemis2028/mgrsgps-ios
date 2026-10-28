# Hosted111 map repair

The terminal map job123094138868 on c712229 passes40/51 UI cases and fails11.
Artifact12857117832 SHA-256
33d955593de4c7d2af419a3bf03769b3035053c2c556f89547988a01c6199504
is verified and extracted at /tmp/mgrsgps-ci111-map. Raw log:
/tmp/mgrsgps-ci111-map-job.raw. No full-run green claim.

The first repair follows production gestures instead of obsolete assumptions:

- Map tool lookup waits for the plus to acknowledge Expanded before querying
  or scrolling its contents. Closing waits for disappearance after animation.
- MapLayerWorkflowTests starts/resets portrait. The failed hosted hierarchy
  shows later cases unexpectedly running at844x390 after the landscape case.
  Layers actions now acknowledge the destination sheet before proceeding.
- The ruler workflow closes the options rail after changing night mode, leaving
  Reset available. Its distance and separate-monitoring assertions are retained.
- Military-target night setup acknowledges the Settings sheet; the hosted
  failure hierarchy was still on Position after the first Settings tap.
- The offline-lifetime negative check reads map-layers directly on Position.
  Calling the stateful mapTool helper there added a pointless menu-opening wait
  while synthetic download responses were deliberately held.

The first matching iOS26.2 rerun is /tmp/mgrsgps-ci111-map-repair-262.xcresult,
log at the same stem. All11 cases pass with zero failures in587.070s: seven map-layer workflows, ruler reset/night separation, military-target night selection, and both complete offline-download/update/rename/relaunch lifetimes (149.364s night,160.949s day). Representative portrait/landscape, ruler and ready-offline screenshots were inspected. No synthetic response timeout change was needed.

Dense-map product follow-up: raiseAnnotations only needs the first hosted marker
container. Eager compactMap queried every native annotation on every map update;
it now short-circuits lazily. This preserves all saved/visible markers and all
selection/drawing behavior. The unchanged5,000-waypoint/1,000-graphic workflow
must be repeated before claiming a dense-map repair. Do not raise its time limit,
shrink the fixture, or hide accessibility nodes to make it pass.

Still to verify/repair: navigation-lane edit/backup and protected GPX native Files
timeouts, dense map response, runtime invalid-frame warnings, and full hosted
confirmation after local fixes. Physical-device gates remain separate.

The three hosted timeout cases also pass unchanged on iOS26.2 in
/tmp/mgrsgps-ci111-dense-lane-files-262.xcresult: linked lane edit/hide/relaunch/
delete127.145s, hidden route-lane native backup restore/strip-PDF134.174s, and
protected GPX wrong-password/preview-cancel/import/relaunch115.324s. That bundle's
one remaining failure was the dense map; its subsequent product repair and final
passing scope are recorded in dense-map-accessibility.md. None of these test
execution allowances was raised. Earlier hosted invalid-frame warnings lack a
source location and remain a separate diagnostic gate.
