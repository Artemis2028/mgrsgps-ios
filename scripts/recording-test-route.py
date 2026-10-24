#!/usr/bin/env python3
"""Feed a moving simulator route through simctl, including across test relaunches.

Runs outside the app: tests still exercise real Core Location/background delivery.
The parent test runner must terminate this process and clear simulated location.
"""
import subprocess
import sys
import time

simulator = sys.argv[1]
for index in range(900):
    latitude = 24.4539 + index * 0.00009
    subprocess.run(
        ["xcrun", "simctl", "location", simulator, "set", f"{latitude:.7f},54.3773000"],
        check=True,
    )
    time.sleep(3)
