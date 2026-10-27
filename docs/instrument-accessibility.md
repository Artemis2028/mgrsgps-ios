# Position and Navigate at accessibility text sizes

At global AccessibilityXXXL on the real iPhone simulator, the Position heading
wrapped as “Po- / sitio / n” beside a scaled-up QR glyph. Its Settings action
had a36-point target. This was an actual layout gap; an otherwise usable grid
did not establish that the screen was readable.

Position and Navigate now give their native, scaled titles the full row at
accessibility sizes in portrait. Actions sit below, with bounded utility glyphs
and44-point targets. Compact-height landscape uses the wider single row to
preserve vertical room. Position keeps its complete grid/callout and independently
scrolling details; Navigate keeps its scrolling target/readouts/actions. Normal
text-size layouts retain their existing arrangement. Context-menu orientation,
precise-location QR gating, target selection and night colors are retained.

Android release/1.1.0 remains482b417; remote release/main/claude-tak refs were
rechecked unchanged. This is a native iOS layout correction; it does not change
Android's coordinate, target, north-reference or navigation behavior.

Validation,27 October:
- `/tmp/mgrsgps-instrument-before.xcresult` fails the44-point Settings target
  requirement (actual36). Its display screenshot also shows the broken heading
  and oversized QR icon. This failed evidence is retained.
- `/tmp/mgrsgps-instrument-layout.xcresult`: two new real Core Location UI
  journeys pass day/night at AccessibilityXXXL, including current-position
  callout, QR sharing, navigation actions and selecting the exact saved target.
  Portrait captures inspected.
- `/tmp/mgrsgps-instrument-final.xcresult`: both final-source journeys pass
  with additional landscape checks on both screens. Display-level portrait and
  landscape day/night captures inspected. No injected app position/heading.
- `/tmp/mgrsgps-instrument-regression.xcresult`: all ten existing ordinary-size
  USNG naming, target choice/cancel/retry/relaunch, military/imported target,
  orientation locking/shortcut and current/waypoint QR workflows pass. This
  source-compatible bundle precedes only the accessibility-landscape row tweak.
- Final unsigned phone/watch/widget Release succeeds in
  `/tmp/mgrsgps-instrument-final-release.log`; ten Python harness checks pass.
  All parents ended naturally; the owned simulator and fake-location feed are off.

These checks cover Glance and Navigate controls on the tested iPhone runtime.
They do not establish whole-app spoken VoiceOver, every device/font size, full
instrument-face accessibility, or physical compass/QR readability. QR instructions
and navigation details remain scrollable; every item is not promised to fit in
one landscape viewport. Hosted109 runs on the earliera002f17 source, so this
candidate remains local until that run is terminal.
