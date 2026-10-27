#!/usr/bin/env python3
"""Real simulator fixes alternating two practice checkpoints; no in-app mock GPS."""
from simulator_location import set_location
from practice_location_control import PracticeLocationControl
from pathlib import Path
import sys
import time

started = time.monotonic()
control = PracticeLocationControl()
control_log = Path(sys.argv[2]) if len(sys.argv) > 2 else None
offset = 0
for index in range(900):
    now = time.monotonic()
    if control_log and control_log.exists():
        with control_log.open(errors='replace') as log:
            if control_log.stat().st_size < offset:
                offset = 0
            log.seek(offset)
            control.consume(log.read(), now)
            offset = log.tell()
    phase = control.current(now)
    if phase is None:
        phase = int(now - started) // 15 % 2
    latitude = (24.4539 if phase == 0 else 24.4550) + index % 3 * 0.000002
    set_location(sys.argv[1], latitude, 54.3773)
    time.sleep(2)
