# Watch terrain cache foundation

Both watch codebases now have the same offline Terrarium cache and sampler contract.
Apple now integrates this layer with explicit cache-only phone export, acknowledged
foreground delivery/queued-file fallback, and a watch map-centre numeric readout. Wear
transport/readout remains implementation work. Offline raster packs and terrain
overlays/analysis remain open. See the iOS report `docs/watch-terrain-transfer.md`;
physical Apple queued-file delivery still requires validation.
The existing vector-scene versions and budgets are unchanged.

## Data and resource limits

A separate version-1 manifest binds a tile to its expected companion source identity,
positive revision and publication timestamp, z13/x/y, payload byte count, SHA256 and
nonempty attribution. Publication time is not a survey date or a freshness guarantee.
Source identity is supplied separately by the caller; future transport must derive it
from the actual companion connection, not trust the manifest to select an active source.
Source strings never become filesystem paths. Revisions/timestamps are integral JSON
numbers within the common exact-integer range 1…9007199254740991. Fractions, booleans,
unsupported versions/encodings, invalid geometry and missing provenance are rejected.
Manifest size is capped at 4096 bytes; each PNG at 4 MiB.

The decoder accepts 256×256, eight-bit RGB/RGBA, noninterlaced PNG. It verifies chunk
bounds, reserved bits, order and CRCs, rejects unknown critical chunks, animation and
transparency-key extensions, reconstructs all five PNG filters, and bounds the zlib
output to the exact raster size. Trailing data, partial rows and expanded payloads
are rejected. Raw RGB samples are read without display color/gamma correction or
premultiplied-alpha conversion. The [W3C PNG specification](https://www.w3.org/TR/png-3/#9Filters)
defines filter reconstruction and the zlib stream format.

Terrarium elevation is R×256 + G + B/256 − 32768 meters. Nonopaque RGBA pixels and
values outside −11000…9000 m remain unavailable. Valid zero and negative elevations
are preserved. Sampling uses exact z13 coverage, nearest source pixel, finite latitude
within ±85° and longitude within ±180°; +180° wraps to −180°. An absent, invalid,
corrupt, deleted or out-of-coverage tile returns no elevation, never a zero substitute.
Attribution and original publication metadata travel with each successful sample.

Each source/tile has a hashed filename and one atomic record containing manifest and
PNG, so validation failure cannot replace an existing tile. Lower revisions and same
revision/different metadata or content are rejected; an identical valid replay is
idempotent and does not refresh retention. A matching valid replay repairs corrupted
payload bytes. Each read verifies the stored payload hash, even on a decoded-memory
hit. Up to four decoded rasters are kept in memory (about 2 MiB of elevations).

The cache owns its directory. Installs are serialized within the process, including
across cache instances. Successful installs trim oldest record modification times to
16 tiles / 32 MiB; unrelated filenames are untouched. Eviction/filesystem failures
are surfaced to the caller. OS cache deletion remains an unavailable-data state;
this is not a guaranteed offline area download. No network fallback or background
location/steering owner is introduced.

## Validation, 29 October 2026

Five tests on each platform use byte-identical synthetic RGB/RGBA tiles and a shared
manifest. The RGBA PNG SHA256 is
`59c258ba2b1e33867213820615571eb9527b736193e7260c53e437e1a0202b46`.
Every opaque pixel is checked against an independent system image decoder and the
known synthetic elevation. Rows exercise all filters. Fourteen malformed fixtures
cover corrupt CRC, dimensions, interlace, critical chunks, transparency keys, filters,
short/long inflation, trailing streams/files, truncation, discontiguous IDAT, duplicate
palette and oversized chunk length. Other cases cover strict metadata, coverage,
source/revision conflicts, relaunch, corruption/repair, deletion, count/byte budgets,
newest-tile availability and preservation of unowned files.

All 636 Swift core tests and 68 Wear unit tests pass. Wear Debug/Release APKs,
Android test APK and Release lint pass. A native API34 Wear instrumentation case
uses the actual Android inflater, BitmapFactory and atomic filesystem, checks opaque
pixels, nil/partial alpha, source/coverage, reopening, rejected replacement and corrupt
payload repair. It runs against a temporary test directory without launching map UI,
requesting location or touching companion preferences. This is simulator runtime
proof, not physical wrist/battery/storage-pressure proof. Final unsigned Apple phone/watch/widget device Release passes. The final native
Wear case passes in 0.117 s; both read-only emulator parents exit cleanly without
snapshots. No GPS, heading or companion preference changes were made.

`tools/generate-terrain-fixtures.py` reproduces the corpus in explicit output folders.
Swift fixtures live in GridFixCore test resources; Wear fixtures are JVM test resources
and instrumentation assets only. No synthetic assets are bundled in production.
Local logs/parent ownership: `/tmp/mgrsgps-terrain-active.json`.

## Next integration gates

- Explicit user-selected, already-cached phone terrain export with retained provider
  attribution; no hidden downloads, vector budget increase or phone-coordinate fallback.
- Separate bounded file-transfer manifest/payload, source identity/revision handling,
  interruption, retry, unpair/re-pair and deletion semantics on both companion SDKs.
- Watch readout and coverage UI with day/night/round/40 mm validation and honest missing
  data; then terrain overlay/analysis and offline raster map packs.
- Physical storage/memory/battery/radio and source delivery checks. Apple positive native
  compass/steering and broader route/fault gates remain separately open.
- Real enrolled iOS/Android TAK exchange and renewal still need coordinated GO. TAK
  remains off; this work makes no TAK connection and changes no server/container/database.
