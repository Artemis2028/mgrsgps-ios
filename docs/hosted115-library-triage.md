# Hosted115 library triage — 29 October 2026

Hosted115/run40833071308 is now fully terminal failure on5b37bd2. Library job
123311471931 artifact12883469487 SHA256
004bf1adac820434e2521d73031d025b145f7bbabb121564923a71c23dd820b8
was verified before extraction to /tmp/mgrsgps-ci115-library. The complete main
bundle contains60 cases:58pass/two failures, both300s execution timeouts.

The dense accessibility workflow reaches its first GoTo input after its hide/show
and full SDK-visible-marker checks, then times out. No marker count mismatch is
reported. Its retained recording is incomplete (no MP4 moov atom), so no visual
result is claimed from that recording. The timeout spindump is usable: the app
main thread repeatedly runs MapScreen.visible/WaypointMapSnapshot.visible and
Foundation case-insensitive folder comparisons, including inside GeometryReader
re-evaluation. The old lookup scans up to100 folder names for each of5,000 points,
repeatedly during view updates. This is concrete product work on the main thread,
not evidence that the device cannot expose the full visible marker set.

Staged product repair resolves each distinct waypoint folder once per visibility
calculation. Foundation's exact comparison, first matching folder precedence,
unknown-folder visible default and input order are retained; there is no marker
cap, omission of otherwise visible data or persisted cache. Two regressions cover the complete
5,000-point/100-folder result and mixed-case/duplicate/unknown folder semantics.
All631 core cases pass, including the dense visibility case in0.004s.

The protected native Files backup workflow completes wrong-password rejection,
successful restore and saved-record checks, and even logs a pass at307.140s, but
its300s deadline already fired during final relaunch. Full result correctly marks
it failed. No password/restore assertion mismatch is reported. The native helper
now checks an already-existing control directly and only enters the unchanged8s
existence wait if it is absent. Repeated wait-for-existence calls otherwise impose
a polling interval even on stable controls. Exact focus/text/file and persistence
checks remain unchanged; no time allowance increase or assertion removal.

Both exact local iOS26.2 workflows pass with ordinary3s fake OS GPS: complete
dense marker/count/hide/show/camera/night160.622s and protected native Files
wrong-password/export/delete/restore/relaunch144.814s. Original300s per-test limits
and every persistence/count assertion remain. Xcode90713 finalizes TEST SUCCEEDED
exit0. Final dense-night/wrong-password/restored captures exported and inspected;
extreme-density label overlap remains recorded. Feed27832 stopped/reaped130,
fake GPS clear, owned phone off, cleanup44550 exit0/reaped. Final unsigned
phone/watch/widget device Release68799 passes/exit0/reaped. All parents terminal.
Fresh hosted confirmation is still required; the local timings are not a hosted
performance guarantee. Ownership: /tmp/mgrsgps-ci115-active-work.json.
Evidence: /tmp/mgrsgps-ci115-library-job.log, library-summary.json,
/tmp/mgrsgps-ci115-library/screenshots/ui-tests/7BA605D4-A860-4E2D-A173-5107EB1FDE34.txt
and /tmp/mgrsgps-ci115-library-diagnostics/. No hosted-green claim.
TAK stays off; enrolled exchange/renewal remains a separate coordinated gate.
