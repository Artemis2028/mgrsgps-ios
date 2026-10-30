#!/usr/bin/env python3
"""Deliver a real OS deep link while XCTest holds the waypoint loading screen.

The owning test/CI process must terminate this follower on exit. It only opens
the local recording panel; it never starts a recording or touches a TAK server.
"""
from pathlib import Path
import re
import subprocess
import sys
import time

simulator, filename = sys.argv[1:3]
path = Path(filename)
offset = 0
pending = ""
while True:
    if path.exists():
        size = path.stat().st_size
        if size < offset:
            offset = 0
            pending = ""
        with path.open("r", errors="replace") as stream:
            stream.seek(offset)
            pending += stream.read()
            offset = stream.tell()
        lines = pending.split("\n")
        pending = lines.pop()
        for line in lines:
            if re.fullmatch(r"WAYPOINT_STARTUP_RECORDING_LINK_READY (true|false)", line.strip()):
                subprocess.run(["xcrun", "simctl", "openurl", simulator, "gridfix://recording"], check=True, timeout=20)
                print("Delivered recording deep link to held waypoint startup", flush=True)
    time.sleep(0.2)
