# Password-protected interchange files

Android reference: `data/ProtectedFiles.kt`, `BackupCrypto.kt` and the export /
protected import controls on `claude/tak`, including the `eacf084` size/cleanup
review. This extends the existing protected-backup envelope to individual exports.

Waypoints → Export → Export protected file offers GPX, CSV, GeoJSON, KML, KMZ and
ATAK packages. The password and exact confirmation use the existing eight UTF-16
unit rule without trimming or normalization. Saved-track actions and track detail
also offer protected GPX. The source is captured before worker preparation;
encoding, archive construction and encryption run off the main actor. Cancelled
or superseded work cannot present a late export. Only encrypted bytes reach the
Files document; no intermediate plaintext export is written to disk. A password
is never persisted, and restarting the app cannot resume a password-bearing job
or create an empty destination: Files starts only after preparation succeeds.

The single-file ZIP uses the ordinary `MGRSGPS-ENC1` authenticated envelope.
The inner basename retains its real extension, including ZIP for an ATAK package.
The visible filename ends in `.mgrsgps`; Files may hide that extension in its
editable name field. This uses the existing registered type identifier for
compatibility, now described as a protected GridFix file. The writer refuses
payloads over Android's 16 MiB per-entry limit before sealing, so it cannot create
a file its own reader rejects. Containers retain the 33 MiB envelope cap, 32 MiB
expanded archive budget and bounded entry count. Inner KMZ/ATAK parsing keeps its
existing format/decompression budgets.

Import file and incoming-file review detect protection from bytes, including
renamed files. The password field stays in the review sheet after authentication
failure and permits retry. Unlocking authenticates and validates the complete
archive before decoding the inner format; it does not publish records. Cancel
keeps the library unchanged. Confirmed import retains the existing duplicate
review and stable retry IDs. A backup manifest instead produces a backup review
with a separate Restore confirmation and included-settings explanation. The
explicit Import backup action remains available; selecting an interchange export
there explains that Import file is required.

Directories, multiple entries, nested single-file paths, traversal, invalid CRCs,
oversized members and tampered envelopes are rejected. Backups may contain their
normal manifest and track entries; the full backup decoder still validates them.
No archive member is extracted to disk. Passwords exist only in prompt/worker
memory and are cleared from the prompt on submit/dismiss. Swift String copies
do not offer guaranteed zeroization; this is the same constraint as backups.

Incoming reviews keep their queue while a password/confirmation is open. Result
messages accumulate until Done rather than overwriting earlier file results;
the result panel scrolls within a bounded height and follows the night palette.
A DEBUG-only incoming fixture seeds a protected backup followed by a protected
GPX into that same review queue. It does not simulate external provider delivery;
actual Files save/reopen is tested separately, and physical Open In delivery
remains a validation gate.

`scripts/GenerateProtectedFileFixtures.java` independently uses Java
ZipOutputStream (DEFLATE/descriptors), PBEKeySpec and AES-GCM to generate six
synthetic files. Swift compares every decrypted inner name/payload exactly and
parses all six formats. Fresh Swift STORE/encrypted exports are authenticated
and decoded by Java in the reverse direction. Verification compares the stored
nested KMZ/ATAK payloads, since independently regenerating their ZIP timestamps
would change bytes without changing content. All fixture positions are fake;
no client identities or server credentials are included.

The new core tests also distinguish a backup, reject wrong passwords/tampering
and authenticated unsafe layouts, check matching reader/writer size limits and
safe basenames. Native integrations cover all six formats through a renamed
file, password-required and wrong-password paths, no publication before confirm,
backup/interchange distinction, cancellation and retry.

## Native validation

All 409 core tests pass, including six Java fixtures and fresh Swift exports
verified in Java. All 179 app integrations pass. The clean final iOS 27 bundle
`gridfix-protected-file-final-ui-20261025.xcresult` also passes five UI workflows:
protected GPX and night KML Files save/reopen, wrong-password retry, preview
cancellation, duplicate review, confirmed import/relaunch; protected single-track
GPX; queued incoming backup/export confirmation with both results retained; and
ordinary track-detail/menu export regression. Exported day/night password, error,
preview, incoming-results and single-track screenshots were inspected. Night
password navigation titles and fields explicitly use the field palette.

The existing protected-backup Files/wrong-password/restore/relaunch workflow also
passes in the preceding clean bundle. An earlier three-workflow attempt failed
on a duplicate password-presenter race and an incorrect test expectation that
Files' editable name always shows its extension. Password prompts now share one
presenter. Actual provider files have `.mgrsgps` names; Java independently
authenticated the actual native GPX and KML exports and decoded their one-entry
ZIPs. A separate track test exposed XCTest's invalid toolbar activation point;
the existing validated visible-frame helper now verifies the actual touch path.
Those earlier failed bundles are not claimed as passing.

The unsigned Release phone/watch/Live Activity extension build passes. Physical
Android/iPhone file-provider/Open In transfers, storage pressure, very large
accepted libraries and secure-field appearance on a physical display remain.
The seeded incoming queue proves the app's review/confirmation flow, not external
URL delivery. Cross-language verification uses fake positions and synthetic
fixture passwords only. Full hosted CI remains a separate gate.
