# Navigation lanes

Reference: Android `claude/nav-lanes` geometry/guide/model at `91cb68f` and
the lane-library behavior on `claude/polish` at `e6bb5c5`. This expands the
original release/1.1.0 scope at the user's request. The Android checkout's
uncommitted startup/reminder/cue-switch work is tracked separately.

## Drawing and editing

Map → Navigation lanes → Draw navigation lane opens Left, Right and Backstop
steps. Tap the map or Add point to trace straight segments. Hold and drag a
vertex or midpoint handle to move/add a bend; there is no “Add kink” command.
Undo removes the last point; Remove point removes the selected point. Each
drawn limit supports up to 500 vertices.

Use existing line links a saved editable line graphic instead of copying its
points. Moving that graphic moves the limit. Its name supplies the landmark
label; edit the graphic itself to move a linked limit. Draw a replacement line
detaches that limit and starts a new owned line. A lane's own drawn limits do
not create separate tactical graphics.

Review names the lane and landmarks, sets its folder, and attaches it to one
checkpoint or a whole route. Saving checks geometry and normalizes reversed/
swapped sides before publication. The camera then fits the complete lane.
The library supports show, edit, map visibility and confirmed deletion, keeping
linked graphics intact. Waypoints exposes the lane library once lanes exist;
its edit action opens the map after dismissal. Replacing an unsaved drawing
requires an explicit in-app choice.

The map shades the interior, draws dashed amber limits and a solid red backstop,
and labels L/R/BS. Night mode uses red line/fill/label colors. Folder and lane
visibility affect display only: **hidden lanes still guide**. A deleted target
or linked graphic stays identifiable in the library rather than silently
deleting the lane.
Displayed side limits reach the backstop, including its end rays, matching the
guide's finite map extent. Unlike the Android snapshot's straight top shading
edge, the iOS fill retains intervening backstop vertices so a bent backstop
does not shade a different area from the crossing detector. Side labels sit
halfway along the line and face outward; backstop text sits above its line.

## Guidance

Starting navigation uses the lane assigned to the selected target. A checkpoint
lane wins over its route's lane; otherwise the newest applicable lane wins.
A route's lane state survives checkpoint advances. Its feedback session also
survives those advances so an already queued crossing notification is not
canceled. A different lane/geometry gets a new crossing detector. Missing or
invalid linked geometry exposes a reason and falls back to ordinary azimuth
guidance. Hiding a lane does not reset its detector.

With usable position and resolved geometry, heading is not required:

| State | Foreground cue |
| --- | --- |
| Inside | Silent |
| Past left limit | Two taps to turn right; repeats every 2.5 s |
| Past right limit | One long pulse to turn left; repeats every 2.5 s |
| Past backstop | Three long pulses to turn back; repeats every 4 s |
| Reentered | One short tick, then silence |
| Position unavailable | Existing unavailable cue; never claim inside |

Crossing requires 5 m plus reported accuracy outside on two distinct new fixes;
reentry requires 3 m inside on two fixes. Backstop overshoot takes precedence
over side crossings. Polyline bends use vertex bisectors; side limits extend
forward and the backstop extends both ways. Repeated readings do not count as
new fixes. Missing position resets pending confirmations. The app retains its
shared 25 m / 10 s navigation-fix gate; the lane core additionally rejects
accuracy worse than 50 m.

Early warning is off by default, with 25/50 m choices in Guide settings. It gives
one turn-away cue per approach, rearming after moving 10 m beyond the warning
band. The setting persists and uses Android's `laneWarningM` backup key.
The Navigate panel names the lane and limits and shows crossing/unavailable/
fallback state; overshoot includes true bearing/distance back to the target.

Background Core Location remains subject to iOS execution and permissions.
Confirmed crossing/reentry transitions request time-sensitive notifications
when the app is backgrounded, using a separate identifier from route milestones.
Repeated steering and approach-warning pulses do not become notification spam.
Notifications depend on authorization and Focus. Core Haptics runs while open;
continuous screen-locked vibration patterns are not promised. Simulator/model
checks do not prove physical locked-screen delivery or battery performance.

**The closed quiet-inside perimeter remains independent.** It does not inherit
lane approach warnings, azimuth steering, arrival or heartbeat policy. Creating
or saving a lane does not start either guide or perimeter monitoring.

## Persistence and remaining integration

`NavigationLaneStore` owns a separate versioned JSON library through a serial
worker. It validates before atomic replacement and publishes revisioned values
on the main actor. Delayed callers cannot replace a newer snapshot. Edit intents
patch changed fields against current data, preserve concurrent visibility, and
cannot resurrect a deleted original. Creation retries keep an existing ID.
Failed writes keep memory/disk unchanged; unreadable/duplicate-ID libraries are
kept and reported rather than overwritten. The file uses protection compatible
with background work after first unlock. Folder registration is a second staged
store phase; its error explicitly says the lane was already saved and retry
retains that record.

Backups now include Android's optional `navLanes` section. Restore validates the
whole archive before publishing anything, then merges lanes after graphics and
before course history/settings. Existing lane IDs retain their current local
edits; an unchanged retry skips rewriting the lane file. Missing linked graphics
or targets are retained rather than silently dropping the lane. Referenced
folders are registered in the waypoint/folder phase. A later failure reports
durable earlier phases and leaves later phases untouched.

Route-card screen, shared text and PDF use the same per-leg limits. Checkpoint
lanes at a leg's endpoint override the route lane; a hidden lane still applies.
Report requests capture relevant lane/ownership/graphic values, and workers
prepare an indexed leg table. Changing limits or linked names invalidates an
in-progress report/PDF. PDF rows measure and wrap their labels before pagination,
retaining every leg and the final totals.

Still pending: phone-to-watch lane status and direct map-lane hit selection.
Complete cached watch overlays and the committed Android lane-start/reminder/cue
switches are implemented; see validation below.
These are implementation gaps, not iOS permission restrictions.
Physical thumb/compass/GPS/lock/storage-pressure/battery checks remain open.

## Validation

The complete core suite passes 340 tests. New coverage includes serial storage,
concurrent edits/visibility, create retry, deleted-original conflicts, corrupt/
duplicate libraries, failed atomic replacement/retry, warning-setting backups,
transition-only background notification policy, finite visible extensions and
bent-backstop/side-limit shading.

All 137 app integration tests pass. Lane tests drive the production navigation
session without heading, with hidden lanes, linked-line movement/deletion,
unavailable position, route checkpoint continuity and checkpoint overrides.
The feedback-session assertion guards against canceling queued crossings at a
same-lane checkpoint change; this is not physical notification-delivery proof.

A closed iOS 26.5 bundle passes 140 tests: those 137 integration cases plus both
new native lane workflows and the existing route draw/drag/save regression.
After display refinements, a second closed bundle passes both lane workflows
again, including Waypoints → map editing, hide/edit/relaunch/delete without
removing linked graphics, and drawing/inserting/dragging a bend. A final native
draw-only run passes; reading its actual saved lane file confirms three vertices
and a 13.0 m perpendicular bend, rather than merely a collinear inserted point.
Day/night map and hidden-library screenshots were exported and inspected.
The unsigned phone/embedded-watch Release build passes. Hosted CI and physical
GPS/haptics/background delivery remain separate gates.

## Backup and report validation

The complete core suite now passes 347 tests and all 143 app integration tests
pass. These include Android-compatible optional lane JSON/ZIP records, legacy
archives without lanes, malformed sections, additive retries, existing-local-ID
precedence, serial atomic lane publication, canceled confirmed restore and real
filesystem failures before/after the lane phase. Route-card requests capture
lane/target/graphic values; checkpoint limits override route limits, hidden
lanes still apply and changed inputs invalidate prepared PDFs. An 84-leg PDF
retains every table marker exactly once, repeats page headers, includes one
final total and keeps every extracted character inside the page bounds.

The clean `gridfix-lane-backup-native-final.xcresult` passes four native tests
with zero failures/skips: the existing night-mode mixed-record backup round
trip, hidden whole-route lane export/delete/restore/relaunch and route-card/PDF
preview, plus both existing native PDF workflows. Files selection handles
Browse reopening directly inside the local provider with virtualized filenames;
no files were removed and count assertions remain intact. Actual PDFKit pages
were rendered and the short, first, continuation and final-page layouts were
visually inspected. Native night library, per-leg limit and PDF-preview
screenshots were also inspected for readable text and controls. The unsigned
phone/embedded-watch Release build passes.
Watch lane synchronization, protected backups and later Android cue switches
remain implementation work; this does not prove physical lock-screen delivery.


## Lane startup and cue settings · Android 4db6b21

Guidance starts in **Not in the lane yet**, silent until two distinct usable
fixes place the user inside every applicable limit by more than the three-metre
return margin. Behind the start does not count as entry. The first confirmed
entry gives the optional inside tick. Once entered, the existing accuracy-aware
crossing confirmation, backstop priority and return hysteresis apply. Changing
to a different lane starts a new entry state; reshaping an already-entered lane
and changing checkpoints within the same route lane retain entered state.

Guide settings now provide independent side-limit, backstop, inside-tick and
position-loss switches (all default on), plus a not-in-lane reminder: Off,
2, 5 or 10 minutes (default 5). Imported values through 120 minutes remain
selectable. The reminder is long-short-long, timed from the first distinct fix
and repeated at the selected interval while entry is still unconfirmed. Early
warning retains its separate Off/25/50 m preference and approach rearming.
The newer eacf084 review makes approach warnings obey the corresponding
side/backstop switch as well. Route checkpoint and arrival cues are independent.

Position lost in lane mode plays three taps once, then no more than once a
minute while enabled, replacing the earlier four-second cadence. Fresh usable
GPS re-arms the loss alert. All five new settings persist locally and through
the Android backup keys, with Android defaults when absent from old files.
No backup starts guidance or changes local Live Activities consent.

Foreground playback uses the Android timing contract. In the background, lane
entry/crossing and the configured not-yet reminder request iOS notifications;
repeating steering and GPS-loss haptics require the app open. Notification
sound/pattern and delivery remain controlled by iOS settings and Focus. These
are guidance settings, not quiet-inside perimeter settings.

The full core suite passes 362 tests, including strict
startup, behind-start exclusion, entry, reminder timing/disable/repeat, duplicate
fixes, independent switches, legacy backup defaults and validation bounds.
All 158 app integration tests pass, including live settings changes, background
reminder requests, inside-tick suppression, side-cue suppression/re-enable,
60-second lost-GPS cadence, lane continuity across route checkpoints and
backup/local-consent isolation. The native settings workflow passes all four
switches, the reminder menu, relaunch persistence and night mode. Day/night
screenshots were inspected: controls, current choice and explanations remain
readable. Only one phone simulator was used and it was shut down afterward.
Physical haptic feel, locked-screen delivery and battery use remain required.


## Reviewed geometry and guidance · Android eacf084

The objective (checkpoint or final route point) now identifies the near side of
the backstop. Without an available objective, length-weighted samples of both
limits determine it. Endpoint orientation uses the signed side of the backstop;
left/right uses which side of each oriented limit contains the lane, not the
number or spacing of vertices. Editor validation, serial save, map shading,
watch overlay preparation and active guidance share this resolver, including
hidden objectives.

Lanes that turn back across the distant backstop extension, or whose final
side-limit rays cross before the backstop, are refused with actionable messages.
An objective on the backstop is refused. Drawn points are sanitized for finite
coordinates, latitude range and wrapped longitude before capturing a lane line.

After an entered lane is reshaped, guidance retains entered state and can
reconfirm an outside crossing in two distinct fixes. Renaming/hiding is not a
geometry change. An objective move revalidates geometry. Walking out past a side
limit and then behind its start now returns to Not in the lane yet, without a
false inside tick; the reminder interval restarts. Approach warnings now obey
the side/backstop cue switches, following the newer Android review policy.

The core suite passes 373 tests, including Android's U-turn/funnel, dense and
reversed lines, length-weighted near-side inference, objective, behind-start,
warning-switch and drag-sanitization cases, plus sparse-backup presence semantics.
The final clean native bundle passes all 161 app integration tests and the new
objective-on-backstop rejection/correction test in day and night modes. The
existing drawing/dragging, linked-line edit/hide/relaunch/delete, hidden-lane
backup/PDF and mixed backup Files workflows pass in the preceding native matrix.
Day/night maps, restored library and explicit disabled-save error screens were
exported and inspected. The test checkpoint fixture now lies before its backstop;
a separate deliberately invalid checkpoint tests the rejection. The final
unsigned phone/watch/activity-extension Release build passes. Only one phone
simulator was used and it is stopped; no watch was booted for this model/UI pass.

Sparse settings restore preserves missing local values, including edits made
after an older preparation. Explicit values and null declination still apply.
Programmatically changing a parsed sparse plan marks the changed keys explicit,
without turning all missing fields into default-valued writes. Files failures,
ordered partial retry and existing lane edits retain their existing tests.
Physical GPS/notification/haptic/storage checks remain open.
