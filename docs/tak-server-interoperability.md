# Live TAK interoperability requirement

The user explicitly requested that iOS and Android exchange data through the
same TAK server. ATAK file import/export already exists; live server transport,
remote map items and sharing controls now have a native iOS implementation; broader interoperability validation is in progress.

## Existing local environment

OpenTAKServer runs in Docker through the Homebrew-installed Colima runtime,
with the local project at `/Users/apollo/AI Proj/ots-docker`. The existing
containers were observed running: OpenTAKServer API, TLS/plain EUD handlers,
CoT parser, RabbitMQ, PostGIS, nginx, MediaMTX and web UI. Published ports are
bound to 127.0.0.1. No new stack was created and no configuration was changed.
Claude maintains the shared setup. Do not change, restart or rebuild its containers or database. Development tests may use only this local server and fake positions; never connect to another server.

The Android emulator uses `10.0.2.2:8089`; that address is emulator-specific.
The iOS simulator can use the Mac's localhost. Physical iOS/Android devices
will need a reachable server address; the current loopback bindings do not
provide that access. Do not widen the bindings as part of the app port.
The handoff and coordination file is `/Users/apollo/AI Proj/tak-local/FOR-IOS.md`.
The prepared package is `local-ots-ios-simulator.zip` in that folder, with
`ios_standin.py` as the reference peer. The authorized iOS endpoint is
`127.0.0.1:8089`, using the existing `gridfix_ios` identity/group access.
Its client certificate expires 24 November 2026. Never commit the package,
print passwords/private keys, or install a host system trust root.
The server certificate names `opentakserver`, so localhost needs explicit
certificate-name/fingerprint approval. A pin cannot bypass CA or validity
checks, and a changed pinned certificate must be refused.

## Source and required behavior

Android's TAK transport uses streamed UTF-8 CoT XML over TCP or certificate-based
TLS. The observed committed source is now `5804dbe` (including flexible ISO 8601 parsing); recheck the final source
and handoff before porting. It has connection status/backoff, server identity
verification, presence/ping versus optional position sharing, folder-based
marker/drawing sharing, UID replacement/delete/expiry, bounded stream parsing
and bounded remote items. iOS must use compatible types, identifiers, geometry,
time/stale policy and affiliation handling; sharing must stay opt-in.

Validation must exercise Android → server → iOS and iOS → server → Android,
using the Python peer for independent capture/injection where appropriate.
Test presence without position disclosure, explicit fresh position sharing,
waypoint/drawing update and removal, stale expiry, reconnection, changed server
identity and malformed/bounded messages. Use the existing TLS handler and
connection package; a local socket mock alone does not prove interoperability.
Physical locked-screen connectivity and background behavior require separate
checks under iOS permissions/scheduling. Live Activities are optional status
surfaces and do not grant transport execution time.

Live TAK work is now an explicit follow-on scope item alongside the ongoing
main-app parity work. Bidirectional teammate position exchange is proven locally; complete live parity is not yet claimed.

## Implementation checkpoint, 25 October 2026

Implemented: bounded CoT writer/parser/UTF-8 framing, separate expiring remote
scene, connection-package review/import, native Network.framework TCP/mutual TLS,
app-scoped CA verification, explicit hostname-mismatch/fingerprint approval,
persisted certificate pin and changed-pin refusal. No application sends happen
before a verified connection is ready. The transport enforces bounded queues,
a connection deadline and 45-second receive silence detection; session backoff
is 1–60 seconds. Presence/pings are 60/15 seconds, shared position 10 seconds.
Position sharing and folder sharing start off, and connecting requires an
explicit user action. A receive-only session pauses in the background and
reconnects on return. An explicitly started position-sharing session uses a
separate Core Location manager and may continue while locked under iOS rules.
This is not a claim of uninterrupted physical-device connectivity.

Credentials and their passwords are held in a non-synchronizing,
AfterFirstUnlockThisDeviceOnly Keychain item. Endpoint/callsign/pin, selected
folders and sent-item history live in a protected, backup-excluded local
folder. Install UIDs are not copied by GridFix backup/restore. Sent history is
separate per server; reconnect withdraws items unshared while offline.
Visible selected-folder waypoints and supported point/line/area graphics share
within the 3-second reconciliation cadence and resend every five minutes.
Rings, sectors and text stay local. Remote contacts/markers/drawings have their
own visibility switch, list, map focus, military affiliation rendering, and
read-only map overlay; they never enter saved waypoints automatically.

### Local interoperability evidence

The native iOS UI workflow imported
`/Users/apollo/AI Proj/tak-local/local-ots-ios-simulator-der-ca.zip`, reviewed the
actual certificate names/SHA-256 fingerprint and explicitly approved the pin.
It connected using the prepared client identity, received `MGRS-ADA5`, listed
it as a contact and focused its marker on the native map. Screenshots from
`/tmp/gridfix-tak-local-ui-fixed-20261025.xcresult` were exported and inspected.
The test then enabled a clearly labelled synthetic position at
35.1388, -78.9914 under callsign `IOS-LOCAL-TEST`. Claude independently confirmed
that exact native iOS teammate on the Android map, with screenshot evidence at
`/Users/apollo/AI Proj/tak-local/android-sees-ios-2026-10-25.png` and confirmation
in the shared handoff. This proves position exchange in both directions;
waypoint/drawing update, delete and reconnect rounds against Android remain.

All **388 core tests** and a full **169-test native integration suite** pass.
Four session tests also pass after the final sharing-journal guard, including
no GPS demand/default positionless presence, explicit sharing/background stop,
refused-certificate reconnect suppression, stale callback rejection, distinct
backup-excluded install identities, and offline folder withdrawal across session
recreation. Certificate tests cover names, SAN display, changed pins, CA,
validity/expiry and malformed metadata. Core tests include every-byte UTF-8 and
hostile declaration splits, stale caps, geometry caps, scene expiry, folder
visibility, change planning, and resend/deletion behavior.
Simulator integration uses local ad hoc signing (`CODE_SIGNING_ALLOWED=YES
CODE_SIGN_IDENTITY=-`) so Keychain access is tested; unsigned test apps produced
-34018 and are not a valid credential-storage check. Hosted CI was updated to
use the same simulator signing configuration. No distribution identity is used.

### Package compatibility and server changes

The original CA-only PKCS #12 bag returns success with zero items from iOS
`SecPKCS12Import`. **Reading certificate-only PKCS #12 stores remains an
implementation gap**, not a completed generic ATAK package capability. Explicit
DER/PEM server CAs are supported; Claude supplied the separate local DER package
whose preference explicitly names `ca.cer`. The app does not silently substitute
a random ZIP certificate or the client chain's CA. Certificate enrollment is
also still unimplemented and is reported explicitly on import.

Apple correctly refused the original ten-year server leaf's validity period.
Claude reissued a 365-day leaf from the same CA and restarted only the TLS
handler/nginx under their server-side management. Codex did not alter server
containers or database, and did not bypass validity/CA/name checks. The
`opentakserver` name still deliberately mismatches localhost, preserving the
explicit review/pin test. Certificate changes are coordinated in the handoff.

Incoming drawings exceeding 500 vertices are rejected whole rather than
truncated into misleading geometry. Supported Android drawing types and
coordinate/time variants otherwise follow the shared contract. Physical
locked-screen connectivity, broader malformed-network tests, full Android
sharing/deletion/reconnect validation, trust management UI, and watch TAK layer
synchronization remain to be checked or implemented.
