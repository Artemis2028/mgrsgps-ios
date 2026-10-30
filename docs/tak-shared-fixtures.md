# Shared Android/iOS TAK regression fixtures

`GridFixCoreTests/Resources/TAKInterop` is the unmodified 14-event sample set and
`expected.json` from Android `claude/tak` (`12cbe99`, moved to the TAK test source
set in `38d0170`). These files also match the handoff folder byte-for-byte.
Manifest SHA-256: `fbc66598539814ca538f589657d75545ee09be1c49798b781695e1a9c4350842`.
They contain fake positions and sample public identities; no credentials.

`TAKInteropFixturesTests` reads the shared own UID, reference time, coordinate
tolerance and expectations. It checks contact/marker affiliation, exact Unicode
names, creators, every line/area vertex, closed shape, delete target, ignored
presence/echo/ping and refused DOCTYPE. Stale timestamps match the manifest at
Android's millisecond precision; Swift may retain more fractional digits.
Each event also runs through one-byte stream reads, including the split É,
and a concatenated set verifies XML declarations and event ordering.

Expectations are not regenerated with the Swift writer. Future contract changes
must be agreed with the Android peer before replacing both fixture sets.

The hosting kit's `-caname … -jdktrust anyExtendedKeyUsage` truststore was checked
locally against an independently OpenSSL-extracted DER certificate: the existing
reader returns the exact certificate. That local server CA is not committed.
A permanent certificate-only `p12-ca-jdktrust.p12` uses the existing public
synthetic test CA, the same OpenSSL flags and fixture password. Its friendly name
and Oracle trusted-key-usage bag attribute are accepted without changing trust
validation or allowing a private key into the fixtures. It joins the exact-DER
algorithm regression test. This check makes no network connection or Keychain
import, and changes no server, container, database or host trust settings.

Validation: all 401 core tests pass on macOS and on the iOS 27 simulator
(`/tmp/gridfix-all-core-ios-20261025.xcresult`). The focused six parser/CA tests
also pass separately on iOS. The exact local kit-file check passes separately;
its machine-specific temporary test and local certificate are not committed.
