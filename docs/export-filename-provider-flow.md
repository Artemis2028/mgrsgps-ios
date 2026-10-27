# Filename entry and native Files selection

Hosted104 on42def16 fails four Files workflows while library passes. Three
real native export pickers show Save but no filename editor; the fourth saves
GPX but its native import icon cannot be activated. Artifact video/hierarchy,
digest and terminal job outcomes are retained in ci-field-ui-activation.md.
This is not a full hosted pass or proof of the earlier boundary-drag repair.

MGRS GPS now supplies a filename form before direct file exports open Files.
It uses native Liquid Glass sheet/navigation controls and the app's red night
palette. The selected format/extension stays fixed; Unicode names are kept,
a matching typed extension is removed once, and invalid/path/control-character
or oversized names cannot continue. Cancellation at this step never opens Files
or creates a temporary export. Filename confirmation dismisses the form before
worker staging and settled UIKit presentation of the actual provider picker.
A file is complete before the provider can read it. Native Save/cancel and
original per-export temporary-file ownership/cleanup remain.

All direct field exports, backups/protected exports and route-PDF Save use the
same flow. The PDF Share action and preserved-original ShareLink retain the
system share interface, including its provider-owned Save to Files behavior.
The app does not rename or replace existing saved library data during export.

Android release reference: WaypointsScreen.kt shareGpx and GridFixApp.kt's
export callback write the completed file on Dispatchers.IO before ACTION_SEND
with FileProvider read access. SettingsScreen.kt uses CreateDocument for backup.
iOS keeps its existing compatible bytes/MIME/extension/backup contract and
provider selection. The extra filename form addresses observed iOS picker UI;
it is not a change to Android's interchange semantics or a claim that its own
system UI uses the same screens.

UI tests name the file in the app, choose a real Files location, save, then
reopen that exact fresh filename and check all records/password behavior. The
reopen helper chooses Files' real List option when initially in Icon Mode and
acknowledges List Mode before activating its real row. This avoids dependence
on the hosted icon thumbnail hit point; no file is injected into import review,
and no expected record counts or persistence assertions are reduced. Native
picker cancellation remains real; app-name cancellation/invalid-name guards are
also exercised.

Validation:

- `/tmp/mgrsgps-export-name-ui-repaired.xcresult` passes scoped native export
  tests and all three FieldExportWorkflowTests.
- `/tmp/mgrsgps-export-name-final.xcresult` passes346 native cases (four opt-in
  skips) and17 of19 UI workflows, including backup/protected backup, all three
  field exports, GeoJSON/KML/KMZ/ATAK, protected GPX/KML/track, queued protected
  imports, lane backup restore and night PDF sharing. The two failures are our
  PDF/ShareLink test-alignment mistakes, retained as failures.
- `/tmp/mgrsgps-export-reference-final.xcresult` passes all346 native cases
  again, both PDF UI workflows and preserved-original sharing after aligning
  those paths, plus two new reference UI cases. Thus all19 distinct existing
  export/recovery workflows are validated across the bundles; repeats are not
  counted as new cases.
- Actual app-owned filename screenshots are inspected in day/night, as are
  the original hosted failure video/frames and digest. Native Save/cancel,
  exact fresh file reopening, record counts and protection assertions stay.
- Final phone/watch/widget unsigned device Release passes in
  `/tmp/mgrsgps-export-reference-release-final.log`; all eight harness checks
  pass in `/tmp/mgrsgps-export-reference-harness-final.log`.

The first compile failed on a SwiftUI Section initializer and was corrected;
it was not a runtime failure. All local parents finish naturally; owned devices
and fake feeds are off. Full hosted confirmation, physical providers/Open In,
storage pressure and PDF printing remain open. The app's own filename control
is now reliable independently of Files' missing editor; the internal system UI
cause is not claimed proven or repaired.
