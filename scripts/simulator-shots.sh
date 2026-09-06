#!/bin/bash
# Boot a simulator, install the app, drop it on a known grid, and take the
# screenshots. Written to survive Xcode image churn on the runners: nothing
# here hard-codes a device name or a runtime version.
set -euo pipefail

APP_PATH="${1:?usage: simulator-shots.sh <path to .app> <output dir>}"
OUT_DIR="${2:?usage: simulator-shots.sh <path to .app> <output dir>}"
BUNDLE_ID="${BUNDLE_ID:-app.gridfix.ios}"
# Abu Dhabi: the ground Rafael actually field-tests on, and 40R BN is a grid
# he will recognise at a glance if the projection ever goes wrong.
LAT="${SIM_LAT:-24.45390}"
LON="${SIM_LON:-54.37730}"

mkdir -p "$OUT_DIR"

IFS=$'\t' read -r UDID NAME < <("$(dirname "$0")/pick-simulator.sh")
echo "simulator: $NAME ($UDID)"

xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b

# Cosmetics: a clean status bar makes a screenshot look like a product shot
# rather than a debugging session.
xcrun simctl status_bar "$UDID" override \
  --time "09:41" --batteryState charged --batteryLevel 100 \
  --cellularMode active --cellularBars 4 --wifiMode active --wifiBars 3 || true

xcrun simctl install "$UDID" "$APP_PATH"

# Pre-grant location so the first screenshot is the app, not a permission alert.
xcrun simctl privacy "$UDID" grant location-always "$BUNDLE_ID" || true
xcrun simctl location "$UDID" set "$LAT,$LON" || \
  echo "note: simctl location unavailable on this Xcode; the app will show NO FIX"

xcrun simctl launch "$UDID" "$BUNDLE_ID"
sleep 6
xcrun simctl io "$UDID" screenshot "$OUT_DIR/position.png"

# A second frame a few seconds later: Core Location in the Simulator often
# delivers its first fix after the app has already drawn once.
sleep 5
xcrun simctl io "$UDID" screenshot "$OUT_DIR/position-settled.png"

# The map with the MGRS grid on it. CI cannot tap a tab bar, so the app reads
# the starting tab from a launch argument (-startTab map → tag 2; navigate=1).
xcrun simctl terminate "$UDID" "$BUNDLE_ID" || true

# Stream the app's own log while the map screen runs. A screenshot cannot say
# whether the grid geometry was empty or whether the renderer never got it;
# the [grid] lines can.
xcrun simctl spawn "$UDID" log stream --style compact \
  --predicate 'eventMessage CONTAINS "[grid]"' > "$OUT_DIR/app.log" 2>&1 &
LOG_PID=$!

xcrun simctl launch "$UDID" "$BUNDLE_ID" -startTab map
sleep 14                     # the basemap style and its tiles have to arrive
xcrun simctl io "$UDID" screenshot "$OUT_DIR/map-grid.png"

kill "$LOG_PID" 2>/dev/null || true
echo "--- app log ---"
cat "$OUT_DIR/app.log" 2>/dev/null | head -20 || true

echo "screenshots:"
ls -la "$OUT_DIR"
