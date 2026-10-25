#!/usr/bin/env python3
"""Real simulator motion with reported course/speed, then a fixed position.
Run separately from recording, freshness and route-navigation feeds.
Caller owns process cleanup and simctl location clear.
"""
from pathlib import Path
import subprocess
import sys
import time
from simulator_location import set_location

simulator, log_path = sys.argv[1:3]
phase = "starting"
deadline = time.monotonic() + 600
while time.monotonic() < deadline:
    log = Path(log_path).read_text(errors="replace") if Path(log_path).exists() else ""
    if "GRIDFIX_MOTION_DONE" in log:
        print("motion UI checks completed", flush=True)
        break
    if phase == "starting" and set_location(simulator, 24.4539, 54.3773):
        subprocess.run(["xcrun", "simctl", "location", simulator, "start", "--speed=1.6", "--interval=1",
                        "24.4539,54.3773", "24.4639,54.3773"],check=True,timeout=20)
        phase = "moving"
        print("moving north at 1.6 m/s", flush=True)
    if phase == "moving" and "GRIDFIX_MOTION_STATIONARY" in log:
        # set replaces the interpolated scenario. Changed coordinate ensures
        # CoreSimulator delivers a new fixed sample instead of coalescing it.
        set_location(simulator, 24.4530, 54.3773)
        phase = "stationary"
        print("fixed position supplied", flush=True)
    time.sleep(1)
else:
    raise SystemExit("Motion UI checks did not finish within 600 seconds")
