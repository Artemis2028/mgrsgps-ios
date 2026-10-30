# Hosted114 map triage — 29 October 2026

Run40821076335 map artifact12877602246 was downloaded and verified against API
SHA-25693e69413be560fa2a770bd156b38a12856cf4ce6526afce06f44655c15eb26dd,
then extracted under /tmp/mgrsgps-ci114-map. The full bundle reports51 cases:
50 passes, one failure, no skips. The failure is
MapLayerWorkflowTests/testManualPanCancelsFitRequestedWhileSavedGeometryWasLoading
at finishSavedGeometry's overlay-count wait, line57.

The actual pan already passed its changed-grid assertion. The screen recording
shows the details HUD expanded with the loading gate, then the saved route drawn
after Finish saved map load. While the new counts were not yet exposed to AX,
mapReadout saw its requested label missing and tapped the summary unconditionally.
That closed the existing expanded HUD. The final screenshot and hierarchy both
show Details collapsed, so the subsequent hidden count could never satisfy the
predicate. This is not evidence that a pending camera fit undid the pan.

The shared mapReadout/mapStatusButton helpers now inspect the summary's exposed
Details expanded value before tapping. A transient missing child in an expanded
HUD is allowed to publish without a collapse gesture. Initially collapsed HUDs
still open with the same user gesture; accessible-map variants keep their
existing fallback. Product map/camera/loading code is unchanged. Camera/grid,
complete overlay count and loading-completion assertions, fixtures and allowances
are retained.

All four local cases pass on the owned iOS26.2 simulator with a static fake
position: portrait/landscape/night disclosure67.929s, manual-pan cancellation
17.700s, newer GoTo33.422s and pending ShowAll14.162s. Xcode parent25845 finalized exit0 / TEST SUCCEEDED after its diagnostic collector.
The completed bundle exported successfully; retained-pan/new-GoTo captures were
inspected with full overlay counts. Every parent reaped, fake GPS cleared and
owned simulator shut down. The refused early export is retained as diagnostics;
no duplicate run/cancellation occurred. This is not fresh hosted-green
proof; library114 remains live and no push/cancellation/duplicate dispatch occurs.

Evidence: /tmp/mgrsgps-ci114-map-job.log,
/tmp/mgrsgps-ci114-map-summary.json,
/tmp/mgrsgps-ci114-map-before-readout.png,
/tmp/mgrsgps-ci114-map-failed.png,
/tmp/mgrsgps-ci114-map-disclosure.xcresult and matching log.
Active ownership: /tmp/mgrsgps-ci114-active-work.json. TAK stays OFF; no GO,
connection, infrastructure, credential, merge or release action.
