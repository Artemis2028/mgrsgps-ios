# Pace count entry

Android reference: release/1.1.0 `482b417`, SettingsScreen.kt `PaceSetting`
and SettingsRepository.kt `setPacePer100m`. Android accepts up to three decimal
digits and applies values from 30 through 200 immediately.

MGRS GPS now offers numeric entry with that range, a paces suffix and a short
calibration explanation. Partial/out-of-range drafts leave the previous setting
in use and show it explicitly. Unicode decimal input is normalized to ASCII.
Existing/imported settings outside this editing range are preserved; backup
compatibility remains unchanged. Route cards use the accepted setting.

The number keyboard has a Done action. The initial green UI run still had a
large-text validation message obscured by the keyboard; screenshot inspection
caught this. Final tests dismiss the keyboard and require the entire validation
message to fit within the visible viewport before capture.

Validation, 27 October 2026:
- `/tmp/mgrsgps-pace-keyboard-final.xcresult`: one native normalization/range
  case and three UI workflows pass (day/night persistence and exact route-card
  total, plus global AccessibilityXXXL night input/validation/relaunch).
- `/tmp/mgrsgps-ci108-local-before.xcresult`: existing Settings persistence
  obstruction/retry workflow passes unchanged with this source, along with
  the two field workflows that failed on hosted108.
- `/tmp/mgrsgps-pace-keyboard-release.log`: unsigned phone/watch/widget Release
  build succeeds. Ten harness checks pass in
  `/tmp/mgrsgps-pace-entry-harness.log`.
- Display-level captures inspected, including the complete largest-night
  validation message and the Recon route total of 211 m / 211 paces at100/100m.

Scoped evidence does not establish whole-app largest-text support or physical
calibration accuracy. Hosted108 tested the earlier pushed7fbeab5 source; it
contains none of this pace-entry change.
