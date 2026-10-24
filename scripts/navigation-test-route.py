#!/usr/bin/env python3
"""Move through three ordered route points using real simulator Core Location."""
import subprocess
import sys
import time

started = time.monotonic()
for index in range(900):
    phase = (int(time.monotonic() - started) // 8) % 3
    latitude = 24.4539 + phase * 0.001 + (index % 4) * 0.000006
    subprocess.run(["xcrun", "simctl", "location", sys.argv[1], "set", f"{latitude:.7f},54.3773000"], check=True)
    time.sleep(1)
