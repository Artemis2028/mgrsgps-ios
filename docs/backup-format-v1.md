# GridFix backup v1 — Android 1.0.4 contract

Inspected `gridfix` main `94c4cc4`, especially `data/Backup.kt`,
`TrackFiles.kt`, `ImportedTracks.kt`, and route waypoint repository logic.
This replaces the historical 0.9.19 notes; that reader's permissive validation
and 64 MB per-entry policy no longer describe the current Android app.

## Container and validation

A ZIP contains `gridfix-backup.json` and `tracks/<trackId>.txt` point logs.
The reader supports STORE and DEFLATE, including Java `ZipOutputStream` data
descriptors. It uses the central directory and checks CRCs, bounds, duplicate
names, unsafe paths, and unsupported/encrypted entries. Limits are 512 files,
32 MB decompressed total, 16 MB per entry, and 4 MB for the manifest. Writers
must stay inside the same limits. iOS writes STORE archives readable by Android.

The JSON root identifies `app` as `GridFix` or `MGRS GPS`, with `version: 1`.
Other apps and unsupported versions are rejected before data is written.
Missing sections are empty; missing settings do not reset device preferences.
All records are validated before restore. Limits include 10,000 records per
section and 250,000 points. Duplicate record IDs and invalid coordinates fail
validation instead of silently dropping records.

## Manifest

The root contains `app`, `version`, `exportedAt` (milliseconds), `waypoints`,
`folders`, `graphics`, `settings`, `tracks`, and `courseHistory`.

Waypoints contain required `id`, `name`, `lat`, `lon`; optional `createdAt`,
`folder`, `symbol`, `affiliation`, `echelon`, `designation`, `kind`, `rotation`,
`visible`, `metadata`, `sourceRouteId`, and `sourceRoutePointIndex`.
Metadata preserves MilGPS colour/symbol, elevation, and timestamp. Explicit
route ID plus zero-based point index owns a generated waypoint. A name alone
never establishes ownership.

Folders are `{ "name": "Recon", "visible": true }`. Every folder name passes
through `Folders.canonical`: trimmed empty, `Waypoints`, and `Graphics` become
`Base`. Existing folder matching is case-insensitive; the collapse itself is
case-sensitive.

Graphics require `id`, `name`, `type`, and `points`; optional fields are
`folder`, `affiliation`, `createdAt`, `echelon`, and `visible`. Points are
**[latitude, longitude]**, the opposite of GeoJSON. Routes use `type: "route"`
and require at least two vertices. Other types use their minimum geometry size.

Settings defaults and integer codes match Android:

| Key | Default | Key | Default |
| --- | --- | --- | --- |
| nightMode | false | angleUnit | 0 |
| keepScreenOn | true | northRef | 0 |
| mgrsDigits | 10 | pacePer100m | 65 |
| latLonFormat | 1 | face | 1 |
| units | 0 | orientation | 0 |
| disclaimerAccepted | false | declinationOverride | null |

A null declination override means automatic; zero means an explicit 0° override.
Orientation/disclaimer preferences are preserved even though their complete
product behaviour remains on the iOS parity roadmap.

Tracks contain `id`, `name`, `startedAt`, `endedAt`, `distanceM`, `pointCount`,
`folder`, and `visible`. IDs must be canonical lowercase UUIDs. Point logs use
POSIX `%.7f %.7f %d %.1f` lines: latitude, longitude, timestamp milliseconds,
and MSL elevation. Three-column historical logs are readable. Missing elevation
uses -32768; values at or below -32767 mean unavailable and GPX omits `<ele>`.
Bad coordinates, malformed rows, and negative log times are rejected. A missing
file for a nonempty track is rejected. Point count and distance are recalculated
from the log rather than trusted from metadata. GPX segment boundaries produce
separate saved tracks to avoid fabricated legs across gaps.

Course results use `name`, `points`, `started`, `total`, and `splits` (all times
milliseconds). Restore merges by `(started, name)`, existing data wins, and the
newest 30 results survive.

## Restore and persistence

Restore is additive. Existing waypoint/graphic/track IDs keep the device's
record, and existing folders keep their visibility. Route vertex ownership also
deduplicates waypoint imports. Valid backed-up settings apply as a whole.

`BackupCoordinator` validates first, commits field data, restores waypoints and
folders, then applies settings. A later write failure reports saved sections;
retry is safe. `FieldDataStore` atomically writes graphics, finished track logs,
and history before publishing changes. If its existing archive is unreadable,
it preserves the file and blocks overwriting it. Live recording and background recovery use a separate append journal until a
finished track can be committed; see [track recording](track-recording.md).

## Verification

`AndroidDataParityTests` reads `Resources/android-backup-contract.zip`, generated
by `scripts/GenerateAndroidBackupFixture.java` with Android's streaming ZIP API
and inspected 1.0.4 fields. It deliberately supplies incorrect track statistics
to verify recalculation. This is a synthetic contract fixture, not a capture
from an Android device. Tests cover restore/export/reopen, duplicate restores,
route ownership, malformed archives, CRCs, write failures, history, GPX segments,
altitude, and dateline overlays. `App/Tests/BackupIntegrationTests.swift` also
restores this fixture through the app's stores and settings on iOS.
