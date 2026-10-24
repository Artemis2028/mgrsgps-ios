#!/usr/bin/env python3
"""Real Core Location fixes paced by the UI test's saved pause/resume state.

Read the isolated Debug test store; never inject app navigation/location state.
Hold the first fix until the test pauses at point 2, then finish after resume.
This avoids racing import/menu/permission animations with a wall-clock route.
"""
from simulator_location import set_location
import json
from pathlib import Path
import subprocess
import sys
import time

simulator = sys.argv[1]
container = None
paused_at_second = False
last_phase = None
for index in range(900):
    if container is None or index % 10 == 0:
        try:
            result = subprocess.run(["xcrun", "simctl", "get_app_container", simulator, "app.gridfix.ios", "data"], capture_output=True, text=True, timeout=10)
            container = Path(result.stdout.strip()) if result.returncode == 0 and result.stdout.strip() else None
        except subprocess.TimeoutExpired:
            container = None
    saved = None
    if container:
        try:
            saved = json.loads((container / "tmp/mgrsgps-ui-tests/navigation-session-v1.json").read_text())
        except (OSError, ValueError):
            pass
    progress = (saved or {}).get("progress") or {}
    point = progress.get("index", 0)
    active = (saved or {}).get("active", False)
    if not saved or (active and point == 0):
        paused_at_second = False
    if point == 1 and not active:
        paused_at_second = True
    phase = 2 if point >= 2 else 1 if point == 1 and active and paused_at_second else 0
    if phase != last_phase or index % 10 == 0:
        print(f"navigation-feed sample={index} phase={phase} saved_index={point} active={active} paused_seen={paused_at_second}", flush=True)
        last_phase = phase
    delivered = set_location(simulator, 24.4539 + phase * 0.001 + (index % 4) * 0.000006, 54.3773)
    time.sleep(1 if delivered else 0.5)
