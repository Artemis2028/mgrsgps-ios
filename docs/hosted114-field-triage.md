# Hosted114 field triage — 29 October 2026

Run40821076335 tests pushed5f73683. Field is terminal failure; library/map
were still live at discovery, so no push/cancellation/duplicate run was issued.

Field artifact12877500391 was downloaded and verified against API SHA-256
29139db5630fcca2c134e96947ff9e60d16bda07220bf0bee9ca73a891c887ed,
then extracted under /tmp/mgrsgps-ci114-field. The complete main bundle has410
cases:401 passes, nine skips, zero failures. The separate practice bundle has15
cases:14 passes and one failure. Other fix freshness, course/speed, boundary
background and route background job steps pass.

The night target-write-failure test stops in startFolder, line13: practice-folder
never appears after the From folder gesture. It has not reached the fault/retry
under test. The failed screen recording and AX hierarchy both retain Random
points selected. The tap used the valid segment frame centre (276.5,188.3), but
the selection was never acknowledged. This is evidence of an unacknowledged
native control gesture; it does not establish a target persistence defect.

Practice setup now uses the suite's existing selectNativeSegment helper: verify
selected state, then use the native element activation if the first gesture
was not acknowledged. It never repeats an already-selected segment. All original
fault, retry, checkpoint preservation, lock, end and relaunch assertions and
fixtures/allowances remain. The helper failure message now names a native segment
instead of assuming every caller is a coordinate-format picker.

Local day/night target-save recovery workflows both pass on the owned iOS26.2
simulator with a static fake position (59.292s /55.275s, Xcode exit0). They retain
fault/retry/lock/end/checkpoint/relaunch assertions. Reopened day/night captures
inspected. Every parent reaped, fake GPS cleared and simulator off. These local
runs include the separately validated concise-practice UI; they are not an
unchanged build of pushed5f73683 or fresh hosted-green proof. No product state
injection or new server/transport claim. Full hosted confirmation remains open.

Evidence: /tmp/mgrsgps-ci114-field-job.log,
/tmp/mgrsgps-ci114-main-summary.json,
/tmp/mgrsgps-ci114-practice-summary.json,
/tmp/mgrsgps-ci114-practice-failed.png,
/tmp/mgrsgps-ci114-practice-selection.xcresult and matching log.
Active ownership: /tmp/mgrsgps-ci114-active-work.json. TAK stays OFF; no GO,
connection, infrastructure, credential, merge or release action.
