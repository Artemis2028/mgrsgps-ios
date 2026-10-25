# TAK certificate sign-in

The native iOS sign-in follows Android `claude/tak` commit `3fb1d85` and
`docs/tak-interop.md`'s enrollment contract. It supplements connection-package
import; packages without a client identity open sign-in with the server and
stream port filled in. An unfinished or failed sign-in preserves the previous
saved connection.

## Behavior

- Verify the HTTPS sign-in endpoint (default 8446) before sending a username,
  password or token. System-trusted certificates must match the hostname.
  A private CA/name mismatch shows the subject, certificate names and SHA-256
  fingerprint for explicit administrator verification. Expired/invalid chains
  cannot be approved. Every subsequent HTTP operation checks that same leaf;
  redirects are refused. This bootstrap policy is separate from the stricter
  existing CA/name/pin policy for the CoT stream.
- Authenticated `GET /Marti/api/tls/config` reads ordered O/OU subject entries.
  XML depth/size limits apply, with external entities/DOCTYPE refused.
- Generate a non-extractable RSA 2048 key in the app's device-only Keychain,
  accessible after first unlock. Only its public key and SHA256-with-RSA signature are exported.
  The PKCS#10 subject ends with CN equal to the exact username (UTF-8).
- POST the CSR to `/Marti/api/tls/signClient/v2?clientUid=…&version=1` using
  Basic authentication, `Content-Type: text/plain`, `Accept: application/json`,
  64-character Base64 lines, trailing newline and no PEM delimiters.
- Validate `signedCert` against this device's key and validate the client chain
  using only the returned `caN` certificates. Restore the native identity using
  the permanent key plus public certificate, without exporting the private key.
- Persist a new Keychain credential archive before atomically replacing the
  profile's credential reference. Roll back the new archive on profile-write
  failure. Retain the device key only after both saves succeed. Cancelled/failed
  enrollment removes its pending key. Replaced credentials/keys are removed
  after the new profile commits. No account password/token is persisted.
- Carry explicitly approved enrollment fingerprints to the TLS stream (default
  8089). A changed stream certificate is refused. The stream still validates
  its CA and dates. Enrollment never enables location/folder sharing or starts
  a connection; the user chooses Connect afterward.
- Paste ATAK `tak://com.atakmap.app/enroll?host=…&username=…&token=…` links into a
  secure field. Host/stream port, Unicode username and secret whitespace are
  preserved; malformed/duplicate required fields are refused without echoing
  the link. Sign-in/stream ports can also be entered separately.

## Validation, 25 October 2026

Local development checks use only the existing OpenTAKServer on this Mac:
`127.0.0.1:8446` and `127.0.0.1:8089`. No server/container/database changes.
The opt-in login is staged outside the repository into the single test
simulator, never in arguments or attachments, and removed by the test.

- Full GridFixCore suite: 413 pass, including link parsing, bounded XML/JSON,
  subject control, certificate dispatch and Android line wrapping.
- Native suite: 185 executed, one unrelated opt-in local-package test skipped,
  zero failures. Tests verify Keychain protection/non-extractability, RSA size, cancelled-key deletion,
  malformed/unrelated certificate rejection, exact bootstrap pin approval,
  changed-pin refusal, and expired/not-yet-valid rejection including a
  leaf-only chain. Existing strict stream trust regression remains covered.
- OpenSSL independently verifies the public CSR produced by the actual
  simulator key and reports O/OU/CN, including `CAFÉ field user` intact.
- First opt-in real enrollment passes wrong-password refusal, approved local
  certificate issuance, device-key match, saved-identity reconstruction,
  TLS connection/ping reception and reconnect, with position sharing OFF.
  The expanded final run also passes profile-write rollback (no orphan archive),
  retry and fresh-session reload. Package-import replacement has the same
  rollback/previous-credential preservation regression coverage.

Three native UI workflows pass day/night form/port validation, certificate
review/approval and real local wrong-password retry. Screenshot inspection
exposed an inherited accessibility identifier, missing keyboard dismissal and
disabled-label contrast; all are corrected. The final contrast/pin-format
three-case regression passes in `/tmp/gridfix-enrollment-readable-ui-20261025.xcresult`;
exported fingerprint, retry and day/night validation screenshots were inspected.
The final Release phone/watch/widget build passes in
`/tmp/gridfix-enrollment-final-release.log`. Hosted CI remains required. Physical devices, hosted production servers, official
TAK Server, account provisioning/revocation, renewal/expiry UX, crash-time orphan
key reclamation and sustained/background reliability remain open. Server-side
IN/OUT group access is an administrator responsibility; enrollment does not
change server permissions or guarantee the server relays a user's traffic.

Local evidence bundles: `/tmp/gridfix-enrollment-final-20261025.xcresult`
contains the green 185-test native suite and the earlier keyboard UI failure;
it is not an overall passing bundle. The corrected three-case UI bundle is
`/tmp/gridfix-enrollment-keyboard-ui-20261025.xcresult`. Public CSR verification
uses OpenSSL `req -inform DER -noout -verify -subject -nameopt utf8`; only public
CSR bytes leave the simulator. No private key or account password is exported.

A final seven-case TAK session regression also passes in
`/tmp/gridfix-enrollment-session-final-20261025.xcresult` after guarding a
late Keychain read from replacing a newly imported/enrolled connection identity.
The one-minute handoff watcher includes only the authorized local enrollment
and CoT endpoints. All owned development simulators are shut down after checks.
