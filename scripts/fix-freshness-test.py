#!/usr/bin/env python3
"""External real-CoreLocation feed: stop on the UI test's observed fresh fix,
then resume only after it has asserted the actual stale state. No app mock GPS.
The caller owns this process and must terminate it and clear location on exit.
"""
from pathlib import Path
import subprocess
import sys
import time
from simulator_location import set_location

simulator, log_path = sys.argv[1:3]
phase = "feeding"
sample = 0
deadline = time.monotonic() + 600
while time.monotonic() < deadline:
    log = Path(log_path).read_text(errors="replace") if Path(log_path).exists() else ""
    if "GRIDFIX_FRESHNESS_DONE" in log:
        print("freshness test completed", flush=True)
        break
    if phase == "feeding" and "GRIDFIX_FRESHNESS_READY" in log:
        subprocess.run(["xcrun", "simctl", "location", simulator, "clear"], check=True, timeout=20)
        phase = "waiting"
        print("location delivery stopped after observed fresh fix", flush=True)
    if phase == "waiting" and "GRIDFIX_FRESHNESS_RESUME" in log:
        phase = "resuming"
        print("location delivery resumed after observed stale fix", flush=True)
    if phase != "waiting":
        # Re-setting the identical coordinate can be coalesced by CoreSimulator
        # after clear. Resume with a real moving stream, like the route feeds.
        latitude = 24.4539 if phase == "feeding" else 24.4540 + sample * 0.000001
        delivered = set_location(simulator, latitude, 54.3773)
        if sample % 5 == 0:
            print(f"phase={phase} sample={sample} delivered={delivered}", flush=True)
        sample += 1
    time.sleep(1)
else:
    raise SystemExit("Freshness test did not complete within 600 seconds")
