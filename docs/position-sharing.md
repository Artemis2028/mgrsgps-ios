# Position callouts, QR handoff and USNG naming

Compared with Android `release/1.1.0` at `482b417`: `coords/Phonetic.kt`, `coords/Coordinates.kt`, `ui/QrDialog.kt`, `ui/screens/PositionScreen.kt`, `ui/screens/MapScreen.kt` and `data/SettingsRepository.kt`.

The Glance face spells the displayed grid with the same NATO alphabet and military digit words as Android. The callout wraps instead of shrinking a whole coordinate onto one line. Android's Position screen displays phonetic text; it does not start text-to-speech. No automatic spoken callout is claimed here.

The Position header offers QR sharing for a usable current fix. Opening it freezes that coordinate and the selected grid precision, so subsequent location updates do not change a code someone is scanning. Map waypoint details offer the same handoff with the waypoint's name and ten-digit caption, matching Android. This does not select a navigation target or change the waypoint.

QR payloads use Android's `geo:lat,lon?q=lat,lon(encoded-name)` format, six decimal degrees, locale-independent punctuation and Android Uri.encode-compatible escaping. Blank labels become `Waypoint`. The native Core Image encoder uses level L error correction. Its black-on-white card stays white in night mode, as on Android; explanatory text and controls use the night palette. No location is uploaded and no camera permission is requested to display a QR. Receiving camera/reader handling of `geo:` URLs requires a physical cross-device check; universal camera support is not promised.

Settings offers MGRS or USNG naming. Both use the same grid conversion and precision. The Android `gridSystem` integer (0 MGRS, 1 USNG) survives local persistence and full backup export/restore; older files default to MGRS. Grid entry accepts the optional case-insensitive `MGRS` or `USNG` prefix with whitespace/colon, including in terrain endpoint entry. A label-only edit to an existing displayed grid preserves its original full coordinate. Unequal easting/northing lengths remain invalid.

Verification includes fixed Android URI/escaping cases, invalid coordinate rejection, decoding the generated QR back to its exact URI, local/backup naming round trips, and simulator workflows for actual Core Location position sharing plus day/night waypoint sharing and USNG entry/relaunch. Screen captures are retained in ignored `screenshots/qr-sharing/` and `screenshots/qr-usng/`. Receiving-camera interoperability, glare/brightness and outdoor readability still require devices.
