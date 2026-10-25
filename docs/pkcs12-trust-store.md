# PKCS #12 server CA import

`PKCS12TrustStore` handles certificate-only bags that iOS `SecPKCS12Import`
returns as an empty array. It verifies the PKCS #12 password MAC before decoding
or decrypting the authenticated safe; no trust anchors are returned on failure.
Extracted DER certificates still pass through Security.framework's X.509 and
server trust evaluation. Client identities continue to use native import.

The reader follows [RFC 7292](https://www.rfc-editor.org/rfc/rfc7292.html) for
MAC/legacy password derivation, and [RFC 8018](https://www.rfc-editor.org/rfc/rfc8018.html)
for PBES2/PBKDF2. CryptoKit supplies SHA-1/SHA-256/384/512 and HMAC; CommonCrypto
supplies PBKDF2 and CBC decryption. Legacy RC2-40, RC2-128 and 3-key 3DES are
import-only compatibility, never used to create new credentials. PBES2 supports
AES-128/192/256-CBC and 3DES with SHA-1/256/384/512 PBKDF2 PRFs. Unencrypted bags
still require a valid MAC. Unsupported algorithms, unauthenticated/signed-only
containers and indefinite-length BER fail explicitly.

Limits: 2 MiB input, 1024 UTF-16 password units, 1024-byte salts, one million
iterations per derivation, two million total digest-block iterations, 32 safe
contents, 128 bags, six nested safe-content levels, and 32 unique certificates
of at most 128 KiB each. Cancellation is checked between contents and during
legacy KDF iteration. The native package import runs this work off the main
actor. Passwords/derived keys are not logged or stored in ordinary preferences.

Golden files under `GridFixCoreTests/Resources/p12-ca-*` contain the same public
synthetic test CA only. No fixture contains a private key or a local-server
credential. `p12-ca-expected.cer` is the exact DER result. OpenSSL generated them
with `pkcs12 -export -nokeys -in synthetic-ca.pem -passout pass:fixture-password`:

| Fixture | Additional OpenSSL options |
| --- | --- |
| aes256 | `-certpbe AES-256-CBC -macalg SHA256` |
| aes192 | `-certpbe AES-192-CBC -macalg SHA256` |
| aes-empty | `-certpbe AES-256-CBC -macalg SHA256`, empty password |
| aes128-sha512 | `-certpbe AES-128-CBC -macalg SHA512` |
| 3des | `-certpbe PBE-SHA1-3DES -macalg SHA1` |
| rc2-40 | `-legacy -certpbe PBE-SHA1-RC2-40 -macalg SHA1` |
| rc2-128 | `-legacy -certpbe PBE-SHA1-RC2-128 -macalg SHA1` |
| plain | `-certpbe NONE -macalg SHA256` |
| unicode | `-certpbe AES-256-CBC -macalg SHA384`, password `fixtüré🔭` |
| empty | `-certpbe PBE-SHA1-3DES -macalg SHA1`, empty password |
| no-mac | `-certpbe NONE -nomac` (must reject) |
| excessive-iterations | `-certpbe NONE -iter 1000001` (must reject) |

Tests compare exact DER across algorithms and Unicode/empty passwords, reject
wrong passwords and altered files, reject missing integrity protection and
excessive work, and exercise malformed lengths and truncated containers. These
are independent OpenSSL fixtures, not round trips through a Swift encoder.

Additional golden stores come from JDK 21 `KeyStore.getInstance("PKCS12")` via
`scripts/GeneratePKCS12CAFixtures.java`. They cover PBES2 AES-256 with SHA-1 and
SHA-512 PRFs, and legacy RC2 with an empty password. Regenerate with
`java scripts/GeneratePKCS12CAFixtures.java GridFixCore/Tests/GridFixCoreTests/Resources`.
The generator only reads the public expected certificate; it never creates or
imports a private key. These fixtures independently check Java/Android's format
as well as OpenSSL's.

The `jdktrust` fixture additionally uses `-caname 'GridFix public synthetic CA'
-jdktrust anyExtendedKeyUsage`, matching the hosting kit's certificate bag
attributes. Unknown bag attributes do not change the extracted DER or its later
native trust checks. See [shared TAK fixtures](tak-shared-fixtures.md).
