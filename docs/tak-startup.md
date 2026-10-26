# Saved TAK startup

Normal cold launch prepares the local TAK profile and per-endpoint sharing
history on the shared startup worker before constructing live services. Payload
reads and JSON decoding no longer run on the UI actor. Short source metadata
checks still happen before installing the snapshot.

The default production root remains Application Support, with the existing
device-local, backup-excluded directory and file protection. First-install
identity creation precedes the source snapshot, so one normal launch retains
one durable UID. Existing callsign, endpoint, pin, visibility, credential reference
and folder-sharing choices survive unchanged. The worker reads no Keychain
credentials and starts no connection or location service. Sharing one's position
remains off on launch; connecting remains explicit.

Both the profile and the selected endpoint's sent-item journal are checked for
replacement, removal and creation after preparation. A change retries the
workspace preparation before publishing its single service graph; queued links
remain queued. A snapshot for a different root is refused. Unreadable profile
bytes remain untouched at startup and show the existing preferences error.
Unreadable sharing history retains the existing folder-sharing-disabled state,
preserving its bytes rather than forgetting previously sent remote items.

Ordinary preference/history writes and import/enrollment transactions retain
their existing behavior. This change does not add automatic connection,
enrollment, repair of damaged files, or network tests.

## Validation, 26 October

All 274 native cases pass with four unstaged local opt-in checks skipped.
Six new cases cover first-install UID stability, retained identity/trust/history
without GPS/network starts, creation/replacement/removal of sharing history,
corrupt history, changed/damaged/wrong-root profiles and a worker-side concurrent
profile edit with exactly one disconnected service graph and retained URL.
All three real Core Location recording UI cases also pass, including recovery
through the shared startup worker; the host again observes 3 to 6 durable points
while the app stays on Home. The final unsigned device Release build passes.

Evidence: `/tmp/gridfix-tak-startup-final.xcresult` and
`/tmp/gridfix-tak-startup-release.log`. No TAK server was started or contacted.
The earlier independently verified enrolled Android/iOS simulator exchange
remains separate evidence; physical lock-screen behavior, renewal and crash
recovery still need their own checks.
