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

pick_device() {
  # Whatever iPhone the image happens to ship, preferring a plain one over a
  # Pro/Plus/Max so the screenshot is a normal phone shape.
  xcrun simctl list devices available -j \
    | python3 -c '
import json, sys
data = json.load(sys.stdin)["devices"]
best = None
for runtime, devices in data.items():
    if "iOS" not in runtime:
        continue
    for d in devices:
        if not d.get("isAvailable"):
            continue
        if "iPhone" not in d["name"]:
            continue
        # Prefer a plain "iPhone <n>" over Plus/Pro/Max so the screenshot is a
        # normal phone shape, then fall back to anything.
        rank = ("Pro" in d["name"]) + ("Max" in d["name"]) + ("Plus" in d["name"])
        key = (rank, runtime, d["name"])
        if best is None or key < best[0]:
            best = (key, d["udid"], d["name"], runtime)
if best is None:
    sys.exit("no available iPhone simulator on this image")
print(best[1], best[2], sep="\t")
'
}

IFS=$'\t' read -r UDID NAME < <(pick_device)
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
# the starting tab from a launch argument.
xcrun simctl terminate "$UDID" "$BUNDLE_ID" || true
xcrun simctl launch "$UDID" "$BUNDLE_ID" -startTab map
sleep 12                     # the basemap style and its tiles have to arrive
xcrun simctl io "$UDID" screenshot "$OUT_DIR/map-grid.png"

echo "screenshots:"
ls -la "$OUT_DIR"
