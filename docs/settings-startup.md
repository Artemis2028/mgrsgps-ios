# Settings startup before live services

Normal launches now read and decode `settings-v1.json` in the shared startup
worker. Constructing `FieldAppStartup` no longer opens settings on the main
executor. The worker prepares appearance, orientation, coordinate precision,
guide/lane choices, hidden map tools and the local Live Activities preference
alongside waypoints, maps, course state and saved navigation.

Before constructing services, startup verifies settings source metadata (including
missing-file state). Creation, replacement or removal invalidates the prepared
snapshot and retries the shared load. The main executor installs the decoded
values and existing normalization rules; it performs source metadata checks,
but does not reread or decode the settings file. Direct synchronous constructors
remain available to fixtures and existing non-startup callers.

The temporary loading view is red on black while the saved appearance is unknown,
so a night launch cannot show a white loading card. The main UI receives the saved
appearance and orientation together with its complete service graph. Early OS
links remain queued; opening the recording panel still does not start recording.

Settings schema, field defaults, invalid-value normalization, launch-face override,
backup policy and the existing malformed-file fallback are unchanged. Startup
leaves malformed source bytes intact; this is not a new read-only settings
recovery workflow. Ordinary preference writes and other runtime-session startup
sources remain separate work.

## Validation

- Five new native cases cover worker execution/deferred reading, retained local
  and backed-up choices without rewriting, created/replaced/removed sources,
  malformed settings fallback and replacement retry before one service publication.
- Full native suite: 264 cases, four unstaged opt-in local checks skipped, no
  failures, in `/tmp/gridfix-settings-startup-final.xcresult`.
- The same run passes day/night cold-library retention, an actual OS recording
  link queued during the held startup, and pinned landscape/flipped orientation
  through the worker cold-launch path followed by Auto rotation.
- Exported night loading/recording and retained day-library screenshots were
  inspected; the loading view has red text on black and the saved screens retain
  their chosen appearance.
- Final phone/watch/widget Release passes in
  `/tmp/gridfix-settings-startup-release.log`.

Only one owned iOS 26.2 phone was used; the feed/link helpers stopped, location
was cleared and the phone shut down after the run. No TAK server was needed.
