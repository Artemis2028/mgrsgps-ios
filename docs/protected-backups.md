# Password-protected backups

Reference: Android `claude/encrypted-backups` at `d6c971b`,
`data/BackupCrypto.kt`, the backup reader and Settings password dialogs.
Ordinary ZIP backup export/restore remains available. Waypoints → Export →
Export protected backup asks for a password and exact confirmation, then
prepares a `.mgrsgps` file through the existing native Files presenter.
Passwords require eight UTF-16 code units, matching Android; they are never
trimmed or Unicode-normalized. Confirmation compares UTF-8 bytes rather than
Swift's canonically equivalent String equality. The prompt explains that a
forgotten password cannot be recovered.

Import backup accepts ZIP, `.mgrsgps` and generic data files, matching Android's octet-stream picker. The reader detects protection
from the bytes, including a protected file renamed to ZIP or with its extension
removed in Files. The default export filename explicitly includes `.mgrsgps`. It asks for the
password before applying records. An ordinary ZIP with a `.mgrsgps` extension
still parses by content. The app registers the protected type with Files;
an incoming `.mgrsgps` exposes a review/password action. Canceling the prompt
restores nothing. Failed authentication reports “Nothing was restored”; the
user can select the same file and retry. An incoming file remains available
after failure. Plain ZIP Open In retains the existing interchange review path.

## Envelope

`MGRSGPS-ENC1` (12 ASCII bytes), 4-byte unsigned big-endian iteration count,
16-byte random salt, 12-byte random nonce, AES-256-GCM ciphertext, 16-byte tag.
The entire 44-byte header is authenticated as AAD. New exports derive a 32-byte
key with PBKDF2-HMAC-SHA256 at 310,000 rounds. Import accepts 100,000–5,000,000
rounds; other counts fail before key derivation. Security-framework randomness
supplies fresh salt and nonce. CommonCrypto derives the key; [CryptoKit GCM](https://developer.apple.com/documentation/cryptokit/aes/gcm)
authenticates the header and body. Password bytes use Java's unnormalized UTF-8
semantics, including embedded NULs.

Protected containers are capped at 33 MiB. Ordinary ZIP containers keep their
existing 512 MiB mapped-input limit; both retain the ZIP parser's 32 MiB expanded
budget and all member/CRC/manifest/record limits. Authentication, inner archive
parsing and complete document validation all precede the first store mutation.
A successful unlock uses the existing ordered additive backup coordinator,
including lanes, settings and partial-failure/retry reporting. The envelope
never changes what is included in a backup.

Provider access, key derivation, encryption/decryption and parsing run on
workers. Cancel invalidates the transfer generation and reaches the worker;
CommonCrypto's native derivation call itself runs to completion, but a canceled
result is checked and discarded before presentation or publication. A restore
already committing finishes its ordered durable phases. Passwords live only
in prompt/transfer memory; prompt fields clear on submit/dismiss, transfer
closures release on completion/cancel, and no password enters settings,
Keychain, logs or backup metadata. Temporary key/password byte arrays are
cleared after derivation; Swift String copies do not provide guaranteed memory
zeroization. Plain archive bytes are not written to a temporary export file.

## Compatibility and validation

`scripts/GenerateBackupCryptoFixtures.java` uses the same JCA
PBEKeySpec/SecretKeyFactory/AES-GCM operations and wire layout as Android.
Its five synthetic fixtures cover ASCII, accented/CJK/emoji, decomposed Unicode,
embedded NUL and the UTF-16 minimum with four emoji. Swift authenticates every
fixture, imports its ordinary contract ZIP and matches deterministic ciphertext
byte-for-byte. Five fresh-random Swift exports also authenticate/decrypt in the
Java verifier. The actual native Files export was independently authenticated
and decrypted with JCA, retaining its manifest and track payload. These are independently generated JCA contract fixtures, not
captures from an Android device or a claim that the Android app was executed.

Core coverage includes wrong/empty passwords, header/body/tag tampering,
truncation, rejected work factors, fresh randomness, normalization differences,
size caps, nonzero Data slices and cancellation. App integration covers the
password-required transition, no publication on authentication/inner-ZIP failure,
retry with local edits/selection retained, content-based detection, read limits
and canceled protected reads. Physical Android/iPhone file-provider round trips
and storage-pressure checks remain separate validation gates.

Reproduce the independent verifier using Android Studio's bundled Java:

```sh
task_java="/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/java"
"$task_java" scripts/GenerateBackupCryptoFixtures.java \
  GridFixCore/Tests/GridFixCoreTests/Resources \
  GridFixCore/Tests/GridFixCoreTests/Resources/android-backup-contract.zip
swift test --package-path GridFixCore
"$task_java" scripts/GenerateBackupCryptoFixtures.java \
  GridFixCore/Tests/GridFixCoreTests/Resources \
  GridFixCore/Tests/GridFixCoreTests/Resources/android-backup-contract.zip \
  "${TMPDIR}gridfix-crypto-interop"
```

## Native results

The complete core suite passes 353 tests. A clean iOS 26.5 bundle,
`gridfix-protected-backup-native-final.xcresult`, passes 150 tests with zero
failures/skips: all 147 app integration cases, ordinary backup Files round trip,
protected backup export/wrong-password rejection/retry/relaunch and the existing
hidden-lane backup/route-card/PDF workflow. The first protected picker attempt
exposed a missing extension/disabled file. Protected export now supplies an
explicit `.mgrsgps` filename, and the backup picker accepts generic data as well
as ZIP/protected types while validating contents before publication.

Artifact review found a missing FileDocument writable type. It is now declared
explicitly. The subsequent clean `gridfix-protected-backup-type-labels.xcresult`
passes nine focused cases (all eight field-export integration tests and the
protected native workflow), and the content-type warning is gone. Password and
confirmation retain visible labels; exported empty/filled night prompts, native
Files save, error text and restored mixed-record screenshots were inspected.
The actual native export also authenticates/decrypts in Java JCA with its
manifest and recorded track intact. The final unsigned phone/embedded-watch
Release build passes.

The focused simulator bundle still reports one “Invalid frame dimension
(negative or non-finite)” runtime warning without a source location. The native
workflow completes and inspected screens remain readable; the warning remains
an investigation item, not an asserted iOS limitation. Physical Android/iPhone
provider transfers and storage-pressure checks remain open. This does not complete the broader parity/release goal.


## Individual protected exports

The sibling [protected interchange workflow](protected-interchange-files.md) now
wraps a single GPX/CSV/GeoJSON/KML/KMZ/ATAK file in the same envelope. Incoming
review distinguishes it from a backup after authentication, retains the queue
and requires the appropriate Import/Restore confirmation. The backup contract,
settings scope and original backup import path stay unchanged.
