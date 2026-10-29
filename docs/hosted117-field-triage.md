# Hosted117 field triage

Run40863515930 on ea06859617b150a38055268e50f9c0ec1b67dc86 has a terminal
field job failure. Map and library jobs remain in progress at this report's
initial write; no cancelling push or duplicate run was issued.

The field xcresult records 420 cases: 409 passed, 2 failed, 9 skipped on iPhone16e,
iOS26.2. Artifact12895884316 (`mgrsgps-ios-117-field`), archive SHA256:
`0ae816986b93fb0adc8db39149c9af2c4383b140a6bcd0a58e13be792aacac3d`.
Downloaded evidence is `/tmp/mgrsgps-ci117-field/build/ui-tests.xcresult`, with
summary and completed-job log under `/tmp/mgrsgps-ci117-field-*`.

## Long filename native round trip

`FieldExportWorkflowTests/testLongImportedFilenameWrapsWithoutLosingItsExtension`
failed115.444s after a second tap attempted to resolve the old Files cell.
The actual native recording at110s shows the app's Import GPX review already open:
the entire long basename and .gpx extension wrap visibly, with correct3waypoint,
1graphic/route,1track counts. This is evidence that import arrived before the
helper tried to activate the stale picker again; it does not make the failed test
pass. Capture `/tmp/mgrsgps-ci117-long110.png`.

The proposed helper change accepts the concrete visible `interchange-counts`
review destination as dismissal acknowledgement alongside Files disappearance.
It retains the full-name, wrapping, viewport, count and later import assertions.
Other import paths still require actual Files dismissal. No document/provider
bypass or larger timeout was added.

## Lane cue settings

`LaneCueWorkflowTests/testLaneCueSwitchesReminderPersistenceAndNightReadability`
failed31.348s waiting for the in-the-lane tick value0. The recording and AX dump
show side-limit/backstop switches0, but tick still1 after the row-relative gesture;
the row is near the bottom of the sheet. Capture `/tmp/mgrsgps-ci117-lane29.png`.
This does not establish a product state mutation bug or a successful tick toggle.

The proposed test change brings each switch farther inside the viewport and
activates its actual native child switch, preserving the same5s state assertion,
all four switches, reminder selection, cold persistence and night checks.

## Local verification

A disposable clone of the iOS26.2 iPhone16e passed both exact workflows with these
helper changes: long filename52.418s and lane-cue42.646s. Parent89392 exited0 and
was reaped; log `/tmp/mgrsgps-ci117-field-local.log`,
result `/tmp/mgrsgps-ci117-field-local.xcresult`, device
8F2E5CC2-70C1-47B0-9D4B-BDE016A1C64D. The fake simulator location was cleared and the disposable clone shut down and
deleted only after the parent completed. These are local exact-case passes; the
failed hosted field job remains failed, and no full hosted pass is claimed.
No source behavior, credentials, server, container or database changes. TAK is off;
real enrolled iOS/Android exchange/renewal still needs coordinated GO.
