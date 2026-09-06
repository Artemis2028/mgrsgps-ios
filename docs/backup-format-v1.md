# MGRS GPS backup format v1 — the cross-platform data contract

*Read from `data/Backup.kt` in the Android app at 0.9.19. This is the spec this app must read **and** write byte-compatibly. Get it wrong and nobody migrates between phones, and the mistake gets harder to fix the more UI is built on top of a wrong guess.*

**Read this before writing any persistence code.** Several fields are traps.

## The container

A plain zip. Two kinds of entry:

| Entry | Required | Content |
|---|---|---|
| `gridfix-backup.json` | **yes** | The whole document, pretty-printed at indent 2, UTF-8 |
| `tracks/<trackId>.txt` | no | One recorded track's points, plain text |

Restore ignores every other entry and every directory entry. A zip without `gridfix-backup.json` is rejected with "not an MGRS GPS backup". Each entry is capped at **64 MB** on read and silently skipped if larger, so a writer must not produce one giant entry.

## The document

```jsonc
{
  "app": "GridFix",          // written but not checked on restore
  "version": 1,              // written but not checked on restore
  "exportedAt": 1788514222663,
  "waypoints": [...], "folders": [...], "graphics": [...],
  "settings": {...}, "tracks": [...], "courseHistory": [...]
}
```

Every top-level array is read with `optJSONArray` — **a missing section is not an error**, it restores as empty. Be equally forgiving on read; always write all seven keys.

### waypoints

| Field | Type | Missing on restore → |
|---|---|---|
| `id` | string | **required, throws** |
| `name` | string | **required, throws** |
| `lat`, `lon` | number | **required, throws** |
| `createdAt` | int millis | 0 |
| `folder` | string | `"Base"`, then the collapse rules |
| `symbol` | string | `"flag"` |
| `affiliation` | string | `"none"` |
| `echelon` | string | `""` |
| `designation` | string | `""` |
| `kind` | string | `KIND_WP` |
| `rotation` | number (degrees) | 0.0 |

`rotation` is written as a Double even though the model holds a Float.

### folders

`[{"name": "...", "visible": true}]`. `name` required, `visible` defaults true. Names pass through the collapse rules on restore.

### graphics

```jsonc
{ "id": "...", "name": "...", "type": "phase_line",
  "points": [[24.4539, 54.3773], ...],
  "folder": "Base", "affiliation": "none", "createdAt": 0, "echelon": "" }
```

> **Trap.** `points` here is **`[latitude, longitude]`** — the opposite order from GeoJSON, which is `[longitude, latitude]`. This app uses both: this order in the backup, GeoJSON order in `TacticalGraphics.swift`. Swap them and every graphic lands in the wrong hemisphere, and near the equator it looks almost plausible.

`id`, `name`, `type` and `points` are required and throw if absent.

### settings

Every key optional with a default. The defaults **are** the app's defaults, so a reader must use exactly these:

| Key | Default | Key | Default |
|---|---|---|---|
| `nightMode` | false | `angleUnit` | 0 |
| `keepScreenOn` | true | `northRef` | 0 |
| `mgrsDigits` | 10 | `pacePer100m` | 65 |
| `latLonFormat` | 1 | `face` | 1 |
| `units` | 0 | `orientation` | 0 |
| `disclaimerAccepted` | false | `declinationOverride` | **null** |

`declinationOverride` is written as JSON `null` when unset and must be read with an explicit null check, not as "0.0 means unset" — zero declination is a real value, and reading null as zero silently pins the compass to the meridian.

The integer codes match `DistanceUnit`, `AngleUnit` and `LatLonFormat` in `GridFixCore/Formatting.swift` by design, so a restored preference means the same thing on both platforms.

### tracks

Metadata only: `id`, `name`, `startedAt`, `endedAt`, `distanceM`, `pointCount`, `folder`. Points live in the companion entry.

`tracks/<id>.txt`, one point per line:

```
%.7f %.7f %d %.1f\n      →  lat lon timeMillis altitudeMetres
```

Space-separated. On read, a line with fewer than 3 fields is skipped and a missing 4th field becomes the **no-altitude sentinel `-32768.0`**. That sentinel is what makes GPX export omit `<ele>` rather than write a fake sea-level height, so carry it rather than substituting 0.

A track whose points entry is absent is skipped entirely, metadata and all.

### courseHistory

`[{"name", "points", "started", "total", "splits": [millis, ...]}]`. The key names shorten: `startedAt` → `started`, `totalMillis` → `total`, `splitsMillis` → `splits`.

## Restore semantics — additive, id-keyed

The part a naive implementation gets wrong.

- **Waypoints and graphics merge by `id`.** An id already on the device wins; only unseen ids are appended. Restoring the same backup twice is a no-op, and restoring an older backup never clobbers newer edits. The return value is the count *added*, not the count read.
- **Folders merge by name.** A folder new to this device arrives with its backed-up visibility; a folder already present **keeps the device's own visibility**, not the backup's. Then every folder referenced by a newly added waypoint is created if missing.
- **Settings are applied wholesale**, not merged.
- **Tracks** are keyed by id like everything else.

A restore is a union, never a replacement. Do the same or a user with two phones loses edits on whichever one they restore into.

## Folder collapse rules — apply on read, always

Frozen since 0.9.9; `GridFixCore/Folders.swift` implements them identically to Android's `Folders.kt`:

- `""`, `"Waypoints"` and `"Graphics"` all collapse to `"Base"` (after trimming).
- Matching against folders already in use is **case-insensitive**: `"recon"` and `"Recon"` are one folder, and the spelling already on the device wins.
- The collapse itself is case-*sensitive*: lowercase `"waypoints"` is a real folder name and stays one.

Every folder field in the backup — on waypoints, graphics, tracks and the `folders` array — passes through `Folders.canonical` on restore.

## What this app still has to build

1. ~~Zip read and write.~~ `ZipArchive` (STORE write; DEFLATE read via zlib) ships in GridFixCore.
2. ~~Document encode/decode against this spec.~~ `Backup.encodeManifest` / `decodeManifest` / `exportZip` / `importZip`.
3. ~~The additive, id-keyed merge~~ for waypoints and folders (`WaypointStore.merge`). Graphics / tracks / course / settings restore wiring is still thin.
4. A round-trip suite that is **fixture-driven, not self-referential**: a reference backup zip produced by the Android app, committed here, that this app must read into the same object graph and re-emit equivalently. Unit tests today round-trip this app's own writer — necessary but not sufficient.

## Version policy

`version` is written as 1 and **not checked on restore**. Fine while there is one version; a problem the first time the format changes, because an old app would read a v2 file and silently drop what it did not understand. Before this app ships a writer, restore should refuse a `version` greater than it knows, naming the app version needed. Cheap now, impossible later.
