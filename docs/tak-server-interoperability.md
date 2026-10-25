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
TLS. The observed committed source is now `57f41f8` (including flexible ISO 8601 parsing and announcement-first ordering); recheck the final source
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
main-app parity work. Bidirectional teammate, shared waypoint/drawing, delete and reconnect exchange is proven locally; complete live parity is not yet claimed.

## Implementation checkpoint, 25 October 2026

Implemented: bounded CoT writer/parser/UTF-8 framing, separate expiring remote
scene, connection-package review/import, native Network.framework TCP/mutual TLS,
app-scoped CA verification, explicit hostname-mismatch/fingerprint approval,
persisted certificate pin, changed-pin refusal and explicit confirmed trust reset. No application sends happen
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
in the shared handoff. This proves position exchange in both directions.

Subsequent native rounds used the **original PKCS #12 CA package**, without the
DER workaround. iOS shared hostile waypoint `IOS OP CAFÉ` and a closed
four-corner `IOS TEST AREA` with position sharing off. Claude confirmed the name,
affiliation, accent and rectangle on Android, then confirmed both disappeared
on unshare and stayed gone after reconnect. The passing native UI bundle is
`/tmp/gridfix-tak-sharing-unique-ui-20261025.xcresult`; Android screenshot
`android-sees-ios-folder-2026-10-25.png` is in the handoff folder.

For Android → iOS, Claude shared `ANDROID OP CAFÉ` (35.1384, -78.9925) and
`ANDROID TEST LINE` with three vertices. The real native app listed and focused
both on the map, then removed both after their relayed delete events while
retaining `MGRS-ADA5`. It disconnected/reconnected using the saved pin and
required a newly received stream timestamp, rather than merely cached markers.
`/tmp/gridfix-tak-inbound-ui-20261025.xcresult` passes; exported point/line
screenshots were inspected. Claude independently confirmed relayed delete UIDs.
A final rendering-only preview regression, explicitly labelled as disconnected,
verifies clearer focus framing and non-clipped labels in day/night and readable
remote-list rows. This preview is not used as interoperability evidence.

One failed sharing round exposed OpenTAKServer's **unique callsign** database
constraint. New test UIDs had reused an earlier test callsign; the server silently
refused registration and relay. Test callsigns now derive from their install UID,
and the settings explain the unique-callsign requirement. The initial
announcement-order diagnosis was disproven by Claude's fresh-UID registration
experiments; it was not adopted as a protocol requirement. Both clients now
announce themselves before pings as a deterministic ordering improvement.
No server database cleanup or trust bypass was used.

All **393 core tests** and a full **171-test native integration suite** pass.
Session checks include
no GPS demand/default positionless presence, explicit sharing/background stop,
refused-certificate reconnect suppression, stale callback rejection, distinct
backup-excluded install identities, and offline folder withdrawal across session
recreation, first-event announcement order, and explicit trust reset that stops
location/disconnects without reconnecting silently. Certificate tests cover names, SAN display, changed pins, CA,
validity/expiry and malformed metadata. Core tests include every-byte UTF-8 and
hostile declaration splits, stale caps, geometry caps, scene expiry, folder
visibility, change planning, and resend/deletion behavior.
Simulator integration uses local ad hoc signing (`CODE_SIGNING_ALLOWED=YES
CODE_SIGN_IDENTITY=-`) so Keychain access is tested; unsigned test apps produced
-34018 and are not a valid credential-storage check. Hosted CI was updated to
use the same simulator signing configuration. No distribution identity is used.

### Package compatibility and server changes

The original CA-only PKCS #12 bag returns success with zero items from iOS
`SecPKCS12Import`. The new [bounded trust-store reader](pkcs12-trust-store.md)
verifies its password MAC before extracting certificates and supports common
legacy RC2/3DES and modern PBES2/AES formats. Independent OpenSSL and Java
KeyStore fixtures verify exact DER, SHA/PRF variants, empty/Unicode passwords,
tampering rejection and work limits. Meaningful password whitespace is retained
by the preference importer. Native identity import still uses Security.framework.
The original local package is now proven end-to-end in the real iOS app.
Explicit DER/PEM CAs remain supported, and the app never substitutes a random ZIP
certificate or a client-chain CA. Signed-only/unauthenticated PKCS #12, unsupported
algorithms and indefinite-length BER fail explicitly. Native [certificate enrollment](tak-certificate-enrollment.md) now supports
username/password or token sign-in with a device-only RSA key. Packages without
a client identity open sign-in; they do not overwrite the saved connection
before a new identity is valid and durable.

Apple correctly refused the original ten-year server leaf's validity period.
Claude reissued a 365-day leaf from the same CA and restarted only the TLS
handler/nginx under their server-side management. Codex did not alter server
containers or database, and did not bypass validity/CA/name checks. The
`opentakserver` name still deliberately mismatches localhost, preserving the
explicit review/pin test. Certificate changes are coordinated in the handoff.

Incoming drawings exceeding 500 vertices are rejected whole rather than
truncated into misleading geometry. Supported Android drawing types and
coordinate/time variants otherwise follow the shared contract. Physical
locked-screen connectivity, sustained/reliability and broader malformed-network
tests, official TAK Server and ATAK/iTAK client interoperability, enrollment renewal/crash recovery,
and watch TAK layer synchronization remain to be checked or implemented.
Polar points remain readable in the remote list but are labelled outside Web
Mercator map coverage; they are not projected into nonfinite screen coordinates.

## Shared peer fixtures, 25 October follow-up

The Android peer's 14 shared sample events and `expected.json` now run verbatim
against the Swift parser, both directly and through fragmented/concatenated
streams. The hosting kit's friendly-name/Oracle trusted-key-usage CA store also
passes exact-DER comparison; a public synthetic equivalent stays in regression
coverage. No contract or production parser change was needed. See
[fixture provenance and validation](tak-shared-fixtures.md). This extends parser
coverage; it does not replace the real two-app tests or the physical checks above.

## Certificate enrollment follow-up

Android `claude/tak` 3fb1d85 is the source reference. The real native simulator
now enrolls against the prepared local 8446 endpoint, refuses a wrong password,
checks certificate/key ownership, reloads the device key and reconnects to the
8089 TLS stream without sharing a position. Profile-write failure rolls back
the new credential archive and preserves the previous connection. See the
[sign-in implementation and validation record](tak-certificate-enrollment.md)
for exact coverage and remaining checks. The strict stream CA/name/pin policy
is unchanged; enrollment has its own explicit private-CA bootstrap review.
