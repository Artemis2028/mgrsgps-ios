# Hosted111 library triage

Run40767120285 on c712229. Field job123094138445 passes, including its dedicated
fix expiry/course/background boundary/route/practice stages. Map123094138868 is
still live; do not cancel it with a push.

Library123094139120 fails three of59 UI cases (56 pass). Artifact12854607937
has verified SHA-256
3a2fe318441d9f11098c991bec54de0d2b969bbc0984f03c718395308751f757;
extracted at /tmp/mgrsgps-ci111-library. Raw job log:
/tmp/mgrsgps-ci111-library-job.raw. The xcresult summary was inspected, rather
than relying only on the final runner launch's40-pass subtotal.

Two BackupWorkflowTests failed at line124: saving a boundary now collapses the
map options, so the old direct-control existence assertion was obsolete. The
test now verifies return to the map/closed editor; subsequent boundary-list
visits select Map first, then disclose its controls. Both full workflows pass
locally in /tmp/mgrsgps-ci111-backup-repair.xcresult: ordinary137.552s and
protected169.443s, including native Files, wrong-password rejection, delete,
restore, boundary geometry/inactive monitoring, and relaunch. Restored-boundary
night screenshot inspected. No product assertion or backup behavior weakened.

A third failure remains OPEN:
LargeLibraryWorkflowTests/testLargeLibrarySearchGridSelectionAndNightCards
exceeds its300s allowance. Search/selection/grid cases finish in33s; after opening
the map with5,000 waypoints, each native accessibility query takes about13s and
the night toggle arrives too late. Do not fix this by raising the test allowance
or hiding the fixture. Dense annotation/accessibility performance needs a product
repair and a repeated full large-library workflow. The result also records
invalid-frame warnings, requiring diagnosis rather than a dismissal as simulator
noise. No full hosted-green claim.
