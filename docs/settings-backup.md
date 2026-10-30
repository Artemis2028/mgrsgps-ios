# Backup and restore from Settings

Android release/1.1.0 `482b417`, SettingsScreen.kt, exposes Back up now and
Restore directly from Settings. iOS previously provided those operations only
through waypoint actions. Settings now opens a native Backup & restore page
with ordinary backup, protected backup and native Files restore. Existing
waypoint entry points remain available.

Both entry points call BackupCoordinator.snapshot. It captures saved waypoints,
folders, graphics, finished tracks/bytes, practice history, display/navigation
settings, navigation lanes and the optional quiet-boundary extension. It refuses
a partial backup when a saved library is unavailable. BackupTransfer still owns
worker encoding/protection/provider reading and ordered additive restore;
BackupPasswordSheet and the existing filename/Files presenter are reused.
No new archive format or encryption is introduced. Offline maps and active
recording/navigation sessions stay separate, as the page explains.

Only preparation/reading can be cancelled. A restore already committing keeps
its ordered progress/error reporting; Done and interactive dismissal are disabled
until that phase finishes. A cancelled filename/provider flow does not claim a
saved file. Passwords are transient and are cleared when the prompt ends.

Validation,27 October:
- `/tmp/mgrsgps-settings-backup-final.xcresult`: all46 scoped native backup,
  transfer, protected-file, lane and boundary integration cases pass. The two
  new snapshot cases check every saved section through protected ZIP round-trip
  and refusal/preservation of unreadable field/lane/boundary files.
- Its ordinary Settings round trip and protected night round trip both pass:
  real native filename/Files save, deletion of the three Recon records, restore,
  exact counts and relaunch. The protected case refuses a wrong password before
  successful retry. Day/night result and error captures inspected. This bundle
  remains failed overall at its earlier largest-text reveal helper.
- `/tmp/mgrsgps-settings-backup-native-swipe.xcresult`: the final global
  AccessibilityXXXL night action/reveal/protected-prompt-cancel case passes.
  Complete Create protected backup and Restore controls are visible in the
  inspected display capture. Native scrolling handles the active content surface.
- The two existing waypoint backup workflows pass in
  `/tmp/mgrsgps-settings-backup-ui.xcresult`, including additive native restore,
  protected retry/relaunch and quiet-boundary preservation with monitoring off.
- Ten Python harness checks pass. Final unsigned phone/watch/widget Release
  succeeds in `/tmp/mgrsgps-settings-backup-current-release.log`.

Earlier evidence is retained: the first native build used the wrong boundary
initializer label, then the new fixture's empty backstop was correctly refused
(five failed assertions after the rejected restore). The fixture now has a valid
backstop and is validated before restore. Press/drag reveal candidates repeatedly
entered Guide settings; gutter coordinates, window coordinates and an extra
button-style candidate did not fix that. The unneeded production styling change
was removed. The final test uses native swipes and retains fully-visible/hittable
action requirements. No data/count/password assertions were weakened.

All local parents ended naturally; the owned simulator and fake feed are off.
This milestone remains outside live hosted109 on a002f17; full hosted, physical
provider/storage and wider accessibility checks remain open. No TAK changes.
