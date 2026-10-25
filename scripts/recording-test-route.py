#!/usr/bin/env python3
"""Feed a moving simulator route through simctl, including across test relaunches.

Runs outside the app: tests still exercise real Core Location/background delivery.
The parent test runner must terminate this process and clear simulated location.
"""
from simulator_location import set_location
import sys
import time

simulator = sys.argv[1]
for index in range(1500):
    latitude = 24.4539 + index * 0.00009
    delivered = set_location(simulator, latitude, 54.3773)
    if index % 10 == 0:
        print(f"location-feed sample={index} delivered={delivered} monotonic={time.monotonic():.1f}", flush=True)
    time.sleep(3 if delivered else 1)
