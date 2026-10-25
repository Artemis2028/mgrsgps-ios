# Android overnight additions — 25 October 2026

Audited after fetching `Artemis2028/gridfix` on 25 October. The release branch
still points to `482b417da93c521be480730f663fab262d26c206`; these additions are
development work beyond that baseline, not a new merged release. The GitHub PR
search returned only the existing draft Wear OS PR #1. Source and the Android
`reports/overnight-2026-10-25.md` were inspected; reported Android test/emulator
results were not independently rerun in this audit.

## References

| Branch | Audited tip | Additions |
| --- | --- | --- |
| `claude/1.1.0-fixes` | `b817a21` | Incoming-file lifecycle fix; atomic publication of restored/imported track logs |
| `claude/nav-lanes` | `045db7d` | Three-line navigation lanes, guidance, map editor, persistence, route-card/backup integration |
| `claude/hide-map-buttons` | `4c8216d` | Persistent map-tool visibility, active-mode escape controls, backup preferences |
| `claude/encrypted-backups` | `d6c971b` | Optional password-protected backups |
| `claude/polish` | `e6bb5c5` | Lane library, tab navigation, singular counts, Locate zoom, unique MARK names |
| `claude/tak-spike` | `38e64d5` | Debug-only TAK prototype and overnight report |

The first five branches are stacked. TAK branches from encrypted backups;
it does not contain the sibling polish commits. Do not compare only `main`
or assume one branch contains every addition.

The Android checkout also contains **uncommitted** lane-settings work on
`claude/lane-settings`: a not-yet-entered state, configurable side/backstop/
entry cues, a waiting reminder (off/2/5/10 minutes), and configurable GPS-loss
alerts reduced to once per minute. These are provisional source changes, not
part of the pushed baseline. This audit leaves that checkout untouched.

## iOS work added to the parity backlog

1. **Navigation lanes.** Add a model distinct from `BoundaryArea`: left and
   right polylines plus a backstop, each drawn or linked to an existing line.
   Resolve draw order/direction against the backstop; preserve bends, extend
   the forward end of side limits and both ends of the backstop. Attach to one
   checkpoint or an entire route, with checkpoint scope taking precedence.
   Port the pure geometry/debounce cases, including reversed lines, sharp turns,
   limits extending beyond the backstop, deleted links and checkpoint changes.
   Provide map shading/labels/editing, a library section with visibility/delete,
   Navigate status, per-leg route-card/text/PDF labels, and optional backup data.
   Hidden lanes continue guiding; hiding is a map display preference.
2. **Password-protected backups.** Keep ordinary ZIP support and implement the
   existing Android envelope byte-for-byte, with cross-platform fixtures before
   adding UI. Optional password plus confirmation on export; detect protected
   files before restore and request their password. Authenticate/decrypt and
   validate the complete archive before any store publication. Run key
   derivation off the main actor. Never persist passwords.
3. **Map-button preferences.** Allow unused tools to be hidden, persist and
   back up the preference, retain reachable controls for active recording,
   drawing and measurement, and offer a visible reset in Settings. Adapt to
   iOS's split tool layout rather than copying Android's deck literally.
4. **Polish and regression coverage.** Check incoming Open In while app is
   backgrounded, restored/imported track durability, singular counts and
   repeated same-minute waypoint names. Locate should zoom a wide map to
   walking scale while preserving an already closer zoom. iOS tab selection
   must still work after returning from Settings.
5. **TAK: experimental follow-on.** Android currently proves localhost mutual
   TLS position/marker exchange in debug builds only. It is not production
   server connectivity. A future iOS implementation needs explicit per-server
   opt-in, Keychain-backed identity, certificate/hostname validation, bounded
   parsing, stale/delete handling and an honest background-execution policy.
   Existing ATAK file import/export does not satisfy live TAK connectivity.

### Lane behavior and platform limits

The pushed Android guide confirms crossings on two distinct new fixes, beyond
5 m plus reported accuracy; return requires 3 m inside on two fixes. Fixes
worse than 50 m do not change state. Backstop overshoot wins over side exits.
Side cues repeat every 2.5 seconds; overshoot every 4 seconds. Optional early
warning is off by default, with 25/50 m choices. Reentry has a single tick.
The uncommitted startup/reminder changes must be reconciled before freezing a
new compatibility baseline.

**Keep the user's existing quiet-inside perimeter separate.** Its silence must
not inherit lane reminders, approach warnings or azimuth steering. Lane mode
is a separate explicit navigation choice; do not silently replace the current
boundary monitor or the existing route-following guide. Editing uses draggable
vertices/segment handles, without an “Add kink” action.

iOS may receive background location updates when authorized, but an iPhone
cannot promise Android's indefinitely repeating screen-locked vibration
cadence. Status and notifications must expose that limit; simulator execution
does not validate physical locked-screen delivery.

### Protected-backup wire contract

`BackupCrypto.kt` at `d6c971b` uses ASCII `MGRSGPS-ENC1`, then a 4-byte big-endian
PBKDF2 iteration count, 16-byte salt, 12-byte IV, AES-256-GCM ciphertext and a
16-byte tag. The complete header is authenticated as AAD. Key derivation is
PBKDF2-HMAC-SHA256, 310,000 iterations for new files; accepted range is
100,000–5,000,000. New passwords require at least eight characters under
Android's UTF-16 length semantics; Unicode encoding needs explicit interop
tests. Android reads at most the normal backup limit plus 1 MiB of sealed
bytes. Wrong passwords and tampering must fail before restore with no partial
publication. The encrypted file extension is `.mgrsgps`; the inner data remains
the ordinary ZIP contract.

## Watches

The current Wear OS draft remains based on `482b417`, so it does not yet know
about these lanes. Both companion snapshot contracts/renderers need lane
overlays and visibility, followed by navigation status if phone guidance is
active. Show GPS-loss/stale-state honestly and preserve existing large grids,
precision controls, waypoint metrics and interactive maps. Do not promise
watch background guidance or offline packs from this source audit.

## Port progress

The first core milestone now exists in `NavigationLaneGeometry.swift`,
`NavigationLaneGuide.swift` and `NavigationLane.swift`: local-plane geometry,
direction/order normalization, bend bisectors, forward extensions, outline,
crossing confirmation/hysteresis, warning rearming, cue cadence, drawn/linked
lines, checkpoint-over-route resolution, route-leg summaries and Android's
JSON point-pair representation. Twenty new tests cover the Android numerical
scenarios and model/wire contracts; the complete core suite passes 330 tests.
This is based on pushed `91cb68f` behavior, not the uncommitted lane settings.
State owns fix timestamps; cue cadence owns monotonic playback time in seconds.

The next milestone adds worker-owned lane persistence, map creation/editing and
shaded overlays, linked graphics, the lane library, checkpoint/route guidance,
early-warning settings and background crossing-notification requests. See
[navigation lanes](navigation-lanes.md) for behavior and validation. Lane backup
records and route-card screen/text/PDF integration are now implemented in the
following milestone. Watch snapshots and the uncommitted Android settings remain
pending. Core tests do not establish physical
locked-screen delivery.

This is an expanded implementation inventory, not a completion claim. See
[the original release parity checklist](ios-parity-release-1.1.0.md) for the
existing port and its outstanding validation/release work.

Lane backups now round-trip the optional Android `navLanes` section, validate
the whole document before publication and restore additively after graphics.
Existing local IDs win; failed later phases report durable earlier work and
retry without duplication. Route-card screen, text and PDF share captured
per-leg limits, including checkpoint precedence and hidden lanes. Long labels
wrap across variable-height PDF rows. The complete core suite passes 347 tests
and the app integration suite passes 143 tests. Four native Files/PDF workflows
pass in a clean iOS 26.5 run; unsigned phone/embedded-watch Release builds pass.
Physical locked-screen delivery remains unverified.

The protected-backup milestone now implements the Android envelope with
CommonCrypto PBKDF2 and CryptoKit AES-GCM, worker-based preparation, native
password/confirmation prompts and content-based restore detection. Independent
JCA fixtures match deterministic Swift ciphertext; fresh Swift exports also
authenticate/decrypt in Java. Ordinary ZIP backup support is retained. See
[protected backups](protected-backups.md) for source references, limits and
validation scope. Physical cross-device/provider checks are still required.

Map-tool preferences now use the Android key/string contract in local settings
and backups. iOS groups its draw libraries and terrain controls under the
matching keys, retains active finish/recording access and exposes an always-
reachable reset. Direct ruler and coordinate Go to controls complete the seven
settings. See [map-button preferences](map-tool-visibility.md) for grouping and
validation. Watch lanes, later cue switches and the remaining polish/TAK work
remain separate tasks.

## Follow-up source check after watch-map work

`origin/claude/lane-settings` now points to committed `4db6b21` (previously the
local provisional work): lane cue switches, not-yet-entered startup, waiting
reminders/calmer GPS-loss alerts, L/Z time display and duplicate-import prompts.
These additions are confirmed backlog items; they are not yet iOS parity or a
new released baseline. Wear's companion phone branch integrates pushed polish
`e6bb5c5` and now exports lane maps. Both watch renderers show complete cached
lanes; phone lane-status transfer remains pending. See
[watch contract and evidence](watch-companion-parity.md).


### Lane-settings port update

The committed `4db6b21` startup/reminder/cue-switch behavior is now ported to iOS,
including backup defaults and the one-minute lane GPS-loss cadence. See
[navigation lanes](navigation-lanes.md) for the source-aligned policy and exact
validation scope. The L/Z rows and duplicate-import prompt from the same commit
remain implementation gaps. Complete cached lane overlays are implemented on
both watches; live phone-guidance status and watch background guidance remain
open. The earlier audit paragraphs describe the state at their source snapshot,
not the current implementation status.

### New review commit discovered during the interchange pass

Android has committed `eacf084` (merged into the current TAK development checkout
at `86eb25f`). This is newer than the `4db6b21` lane-settings port. Its indexed,
worker-based duplicate check, including track name/count/length matching, is the
reference for the current iOS import-review work. iOS is not changing the other
checkout's uncommitted TAK files.

Still to port/audit from that review: lane geometry orientation and objective
handling, refusal of self-returning/meeting limits, entered-state retention on
same-lane reshaping, returning behind a crossed limit to not-yet, warnings obeying
cue switches, dragged-point sanitization, preserving absent settings from old
backups, and the offline/lasso/protected-export fixes. Existing iOS protections
must be inspected individually before deciding which changes are actually
missing. These are implementation/audit work, not platform limitations.
