# Settings presence audit — 29 October 2026

Claude's28 October note describes newer Android restores preserving current
settings when an older backup omits a key. Source review confirms iOS already
implemented that policy in0d84a55. The later “open follow-up” entries were stale;
this audit corrects the inventory instead of duplicating production code.

Backup.Document retains the parsed settingsKeys set. Complete programmatic
settings values use nil presence and remain full replacements. Parsing sparse
settings preserves only actual keys through ZIP export/reimport; editing a
parsed setting adds that changed key without filling unrelated absent keys.
Backup.mergingSettings overlays supplied keys on current values, so explicit
false/zero values win and explicit null clears the manual magnetic override.
An empty settings object retains current values. A null settings section is
rejected as malformed.

All four production restore entry points use BackupCoordinator.restore:
RootView incoming-file restore, WaypointsView restore/review, and the Settings
backup/restore sheet. The coordinator passes document.settingsKeys to the
worker-prepared AppSettings restore. Revision checks reject stale prepared
settings, then rebase against current values rather than overwriting a local
edit made while the restore worker ran. Local Live Activities consent remains
separate from the imported Android settings.

Current evidence, without rerunning unchanged tests:

- All three BackupSettingPresenceTests pass in the557-case core run at
  /tmp/mgrsgps-automatic-names-core-final.log.
- StagedBackupIntegrationTests.testSparseBackupPreservesNewerSettingsAndRebasesAfterLocalEdit
  passes in the357-case native run at
  /tmp/mgrsgps-auto-names-native-final.log. It changes a local setting after
  preparation, proves rejection of the stale file, restores through the real
  coordinator, and verifies durable values after reopening.
- Production source: Backup.swift's document key presence and mergingSettings,
  AppSettings.RestoreSnapshot.prepare, and BackupCoordinator's staged restore.

No new settings behavior, wire keys, credentials or permissions were introduced
by this audit. Hosted111 is still validating the pushed c712229 source; it must
finish before another source push. Independent watch crossing/haptics/background
navigation, physical paired-device checks, long-log migration/streaming and
remaining documented distribution gates stay open implementation/validation work.
