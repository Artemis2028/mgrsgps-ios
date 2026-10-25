# Live TAK interoperability requirement

The user explicitly requested that iOS and Android exchange data through the
same TAK server. ATAK file import/export already exists; live server transport,
remote map items and sharing controls still need implementation on iOS.

## Existing local environment

OpenTAKServer runs in Docker through the Homebrew-installed Colima runtime,
with the local project at `/Users/apollo/AI Proj/ots-docker`. The existing
containers were observed running: OpenTAKServer API, TLS/plain EUD handlers,
CoT parser, RabbitMQ, PostGIS, nginx, MediaMTX and web UI. Published ports are
bound to 127.0.0.1. No new stack was created and no configuration was changed.
Claude is preparing the shared setup; leave that work intact.

The Android emulator uses `10.0.2.2:8089`; that address is emulator-specific.
The iOS simulator can use the Mac's localhost. Physical iOS/Android devices
will need a reachable server address; the current loopback bindings do not
provide that access. Do not widen the bindings as part of the app port.
The user has a server CA/client-certificate connection package and a Python
`tester.py` second client. Use the prepared test credentials without printing
passwords/private keys or installing a new system trust root.

## Source and required behavior

Android's TAK transport uses streamed UTF-8 CoT XML over TCP or certificate-based
TLS. The observed committed source is now `6fc4733`; recheck the final source
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
main-app parity work. No claim of completed live interoperability is made yet.
