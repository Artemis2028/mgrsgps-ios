#!/usr/bin/env python3
"""Real Core Location feed crossing a perimeter around Abu Dhabi's test fix.

Run outside the app for BoundaryWorkflowTests, never alongside recording's feed.
Stop this process and reset simulator location after the workflow.
"""
from simulator_location import set_location
import sys
import time

simulator = sys.argv[1]
started = time.monotonic()
for index in range(900):
    # Twelve seconds inside, twelve seconds 300 m east/outside, repeated.
    latitude = 24.4539 + (index % 6) * 0.000008
    longitude = 54.3773 if (int(time.monotonic() - started) // 12) % 2 == 0 else 54.3803
    set_location(simulator, latitude, longitude)
    time.sleep(1)
