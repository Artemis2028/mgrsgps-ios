#!/usr/bin/env python3
"""Move through three ordered route points using real simulator Core Location."""
from simulator_location import set_location
import sys
import time

started = time.monotonic()
for index in range(900):
    phase = (int(time.monotonic() - started) // 8) % 3
    latitude = 24.4539 + phase * 0.001 + (index % 4) * 0.000006
    set_location(sys.argv[1], latitude, 54.3773)
    time.sleep(1)
