# Hosted115 field triage — 29 October 2026

Hosted115/run40833071308 field job123311472208 is terminal failure on exact
5b37bd2. Map and library jobs remain active and were not cancelled or replaced.
Artifact12882338555 SHA256
f3f3af2cd81fbce057dc8648c655c95348b4f025359a69f633df0a377f567fc6
was verified before extraction to /tmp/mgrsgps-ci115-field.

The full main result contains417 cases:407 pass, nine skip, one failure.
The failed FieldEditWorkflowTests graphics/track night workflow expects the
first graphic visibility switch to become0 after its label-wide coordinate tap.
The tap is recorded but the value remains1. The final AX tree exposes a parent
switch326pt wide and a nested native switch63pt wide; both remain1. The recording
also shows the visible switch still on. No fault/retry or durable mutation error
is reported. The later route edit workflow passes in the hosted job. This evidence
identifies unacknowledged switch interaction, not a proven persistence defect.

The staged test uses the existing setNativeSwitch helper for the three visibility
changes in this workflow pair. It targets the nested native switch and reads the
value before another bounded attempt, never toggling an acknowledged change back.
Initial/final value checks, hidden/deleted counts and relaunch persistence checks
remain intact. Product field mutations, fixtures and timeout allowances unchanged.
Both local iOS26.2 workflows pass on the final staged test: graphics/track night
hide/delete/relaunch56.177s and route edit/hide/delete/relaunch65.730s. Xcode71350
finalizes TEST SUCCEEDED/exit0. Hidden-graphic/edited-route and deleted-library
captures were exported from the completed result and inspected. Feed90036 was
stopped/reaped130, fake GPS cleared and the owned phone simulator shut down;
cleanup26568 exited0. No duplicate build or broad rerun was started. See
/tmp/mgrsgps-ci115-field-switch-repair.xcresult and matching log/attachments.
No hosted-green claim; map/library115 remain active on the original head.

Evidence: /tmp/mgrsgps-ci115-field-job.log,
/tmp/mgrsgps-ci115-field-summary.json,
/tmp/mgrsgps-ci115-field-failed-switch.png and the full recording
/tmp/mgrsgps-ci115-field/screenshots/ui-tests/B7A6AD04-2B07-4E0A-A153-081471FE1347.mp4.
TAK stays off; real enrolled exchange/renewal remains a separate coordinated gate.
