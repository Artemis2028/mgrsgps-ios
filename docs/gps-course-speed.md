# GPS course and speed parity

Android source reference: `release/1.1.0` / `482b417`, `ui/screens/PositionScreen.kt`, `ui/screens/NavigateScreen.kt` and `coords/Coordinates.kt`.

The foreground fix now retains Core Location's reported course and speed. Invalid, nonfinite or missing measurements remain unavailable; the app does not calculate a heading from two positions or invent zero speed. Speed displays in Android's one-decimal km/h, mph or knots using the existing shared formatting factors. Zero reported speed is valid.

Position Glance uses **GPS course**, not the magnetometer. Lensatic/Dial prefer a fresh compass and fall back to reported course when no usable compass reading is available. Course requires a finite reported speed strictly greater than 0.5 m/s and a reported bearing in 0…<360°. A retained stale fix keeps its historical movement values explicitly labeled **LAST CRS / LAST SPEED**, alongside the STALE word, monotonic age and precision warning. This is a readout of the old sample, not an extrapolated current direction.

Navigate prefers a valid compass and permits GPS course only when the device has no compass, matching Android's more restrictive rule. A temporarily bad or expired compass does not silently switch sources. Course navigation requires the existing authorized/precise ≤25 m, ≤10-second fix policy. Its visual steering label is **GPS course**, rather than Screen top; it describes direction of travel and does not rotate with the display. True/magnetic/grid and degrees/mils are applied to the true course through the same reference conversions as other headings. Manual declination does not rotate the underlying true GPS course.

The main compass runs only for Position Lensatic/Dial or the Navigate screen. Tab/face changes update demand; backgrounding stops the foreground manager. This does not control the independent background pocket-navigation driver or change quiet-inside boundary monitoring. The existing screenshot-only `-startHeading` instrument override is now DEBUG-only and cannot paint a fictitious heading in Release.

## Verification

The app integration suite has 94 passing tests. New tests exercise actual CLLocation field conversion, missing provider values, Glance/instrument source preference, stationary/slow/invalid course rejection, missing-versus-bad compass navigation policy, true/magnetic/grid course conversion and stale/inaccurate navigation fixes.

The native simulator workflow uses `simctl location start --speed=1.6 --interval=1` to deliver genuine Core Location samples on a northbound path. It verifies 000° true course and 5.8 km/h, changes native settings to 3.6 mph and 3.1 kn, checks night-mode readouts and selected-target GPS-course navigation, then replaces the moving scenario with a fixed location and verifies that course becomes unavailable. ETA also receives the real reported speed. Native screenshots were visually inspected. CI gives this workflow a separate feed phase and retains its log and xcresult. The real stale/recovery workflow remains a regression check.

Simulated motion proves provider-field wiring and presentation, not real receiver speed/course accuracy, compass quality, battery use or body/worn-device behavior. Those remain physical checks. Direction of travel can differ from the direction the phone points; the explicit source label must remain visible.
