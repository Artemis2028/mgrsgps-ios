#!/usr/bin/env python3
"""Real simulator fixes alternating two practice checkpoints; no in-app mock GPS."""
from simulator_location import set_location
import sys
import time

started = time.monotonic()
for index in range(900):
    phase = int(time.monotonic() - started) // 15 % 2
    latitude = (24.4539 if phase == 0 else 24.4550) + index % 3 * 0.000002
    set_location(sys.argv[1], latitude, 54.3773)
    time.sleep(2)
