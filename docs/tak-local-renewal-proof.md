# Coordinated local certificate-renewal proof

The older26October enrolled simulator exchange and90-second fake-position delivery
have recorded evidence in tak-server-interoperability.md. The later manual-renewal
lifecycle tests use a synthetic accepted-result seam. They do not prove a new
server-issued certificate/key, uninterrupted native TLS, or renewed-key reload.
The current enrolled two-app exchange and live renewal remain open verification
gates as required by the active task.

`TAKLocalRenewalTests/testOptInNativeRenewalPreservesOpenTLSAndReconnectsWithNewDeviceKey`
is prepared for that missing certificate lifecycle round. It is not yet a live
pass. Ordinary CI/local runs skip it without an explicitly staged one-shot file.
No server or client connection is started by preparing or compiling this harness.

## Before a live round

Rafael must explicitly authorize a coordinated local round. The current instruction
is “The local server stays off until an authorized coordinated test”; this document
is not a GO. Existing local server availability must be provided externally under
that authorization. Codex must not start, restart, rebuild or modify containers or
the database. Do not stage the live fixture while running routine offline checks.
Only prepared iOS endpoints127.0.0.1:8446(enrollment) and127.0.0.1:8089(CoT) are used.
Neither endpoint is read from a credential file, environment variable or argument.

Use a disposable ad-hoc-signed simulator test host. Simulator Keychain tests need
`CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-`; unsigned apps are not valid
credential-storage proof. After GO and administrator review of the known local
server certificate, stage `Documents/tak-local-renewal-proof-login.json` in that
host's app container, outside the repository, as a regular0600file of at most16KiB.
Required JSON fields are username, password and expectedServerSHA256. The last is
the reviewed server leaf fingerprint (32 colon-separated hexadecimal bytes), not
the client certificate or a CA fingerprint. No account values belong in source,
arguments, chat/handoff notes, screenshots or diagnostics. Existing secrets are not
read or copied during offline preparation. The filename is ignored by Git too.

Invalid metadata/permissions or malformed input fails before network use; unrelated
invalid files/directories are not deleted. A validated private fixture is consumed
before verification/network traffic and has deferred cleanup on ordinary errors.
If the simulator/test process crashes, verify/remove any residual staged file
locally before archiving a device. No private key is exported.

## Live assertions

The observer forwards native transport traffic/trust unchanged and records only
connection counts and public certificate bytes for boolean comparisons, with no
credential or certificate-byte attachments. The live case:

1. Verifies the expected server leaf before authenticated enrollment.
2. Creates a real device-only key/certificate, saves/reloads its native identity,
   connects and receives server data. Position/folder sharing stays off.
3. Requests a second real enrollment for the same session UID and captured server.
4. Installs it as renewal, proving a different device key/certificate/archive,
   public date metadata and no PKCS12/password archive fields.
5. Keeps the open transport's start/stop counts and receives new server data on
   that same connection after replacement. UID/callsign/sharing policy remain.
6. Verifies old archive/key removal, reconnects using the renewed native identity,
   and verifies a new session reload uses that identity too.
7. Disconnects and deletes only this test's uniquely owned credential archives,
   keys and temporary profile directory. The account password is never persisted.

The case does not enable GPS sharing or send a physical position. Its certificate
round is separate from the subsequent real iOS/Android fake-position/map exchange
and native Renew-button interaction. Those remain coordinated gates. The existing
peer preparation/UI tests require their own explicit one-shot staging; neither is
silently chained or authorized by this harness.

## Offline validation and remaining work

Three guard tests exercise private/regular/bounded/pinned fixture requirements,
meaningful secret whitespace and fixed localhost endpoints. Existing native
Keychain protection/key-deletion and synthetic renewal lifecycle cases are also
run with ad-hoc signing. A disposable simulator is confirmed unstaged before the
live case is selected to prove its skip; no live credentials are supplied.
Initial ad-hoc run98836 passes15offline cases (native Keychain/certificate lifecycle
and the first two guards), with the live case skipped. Final run57158 passes all
three guard cases, including actual native symlink metadata rejection, with the
live case skipped again and zero failures. The extra fixture/privacy assertions compile; they are not a live renewal pass.
Final ad-hoc build-for-testing also passes after adding post-receive transport
count checks (a silent reconnect cannot count as open-socket continuity) and a
strictly newer receive requirement after explicit reconnect. Parent63200exit0/reaped;
log`/tmp/mgrsgps-tak-renewal-proof-final-build.log`. All parents98836/17744/57158 are reaped.
The disposable01CA14E5clone was shut down/deleted after completion; no live fixture
was staged and no account credentials were read. Evidence:
`/tmp/mgrsgps-tak-renewal-proof-verified.xcresult` and
`/tmp/mgrsgps-tak-renewal-proof-active.json`.

Passive socket inventory on29October reported no visible listeners on the two prepared
ports; it made no connection. No server/container/database changes, merge, publish
or release. CI118 onbc563bd is preserved while this test-only follow-up is held
locally. Next after authorized live execution: inspect results for an actual pass
rather than a skip, coordinate independent Android confirmation with Claude,
restore test device state and keep wider physical/background/revocation gates open.
