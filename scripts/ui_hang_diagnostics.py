"""Capture at most three stacks from this simulator's app after native UI stalls.

Read-only diagnostics: no app/container writes, signals to the app, screenshots,
network calls, credential reads or changes to test outcomes/deadlines.
"""
from pathlib import Path
import re
import signal
import subprocess
import sys
import time

SIGNALS = ('App animations complete notification not received',
           'process main thread busy for 30.0s')


def stalled(text):
    return any(marker in text for marker in SIGNALS)


def owned_pids(processes, binary):
    result = []
    for line in processes.splitlines():
        match = re.fullmatch(r'\s*(\d+)\s+(.+?)\s*', line)
        if match and int(match[1]) > 1 and match[2] == str(binary):
            result.append(int(match[1]))
    return result


class Collector:
    def __init__(self, simulator, directory):
        self.simulator = simulator
        self.directory = Path(directory)
        self.seen = set()

    def capture(self):
        if len(self.seen) >= 3:
            return
        try:
            path = subprocess.check_output(
                ['xcrun', 'simctl', 'get_app_container', self.simulator,
                 'app.gridfix.ios', 'app'], text=True, timeout=5).strip()
            bundle = Path(path)
            if bundle.name != 'MGRSGPS.app' or self.simulator not in bundle.parts:
                return
            processes = subprocess.check_output(
                ['ps', '-ww', '-axo', 'pid=,comm='], text=True, timeout=5)
            for pid in owned_pids(processes, bundle / 'MGRSGPS'):
                if pid in self.seen or len(self.seen) >= 3:
                    continue
                self.seen.add(pid)
                self.directory.mkdir(parents=True, exist_ok=True)
                output = self.directory / f'app-mainloop-{len(self.seen)}.txt'
                # Read-only stack sampling; no app signal or termination command.
                result = subprocess.run(
                    ['/usr/bin/sample', str(pid), '1', '1', '-file', str(output)],
                    capture_output=True, timeout=8)
                print(f'Stall stack capture {len(self.seen)}: exit {result.returncode}', flush=True)
        except (OSError, subprocess.SubprocessError):
            # Collection failure cannot replace the original test outcome.
            print('Stall stack unavailable; preserving test execution.', flush=True)


def main(simulator, logfile, directory):
    running = True

    def stop(*_):
        nonlocal running
        running = False

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    collector = Collector(simulator, directory)
    offset, previous = 0, ''
    while running:
        try:
            path = Path(logfile)
            if path.stat().st_size < offset:
                offset, previous = 0, ''
            with path.open(errors='replace') as log:
                log.seek(offset)
                chunk = log.read(64 * 1024)
                offset = log.tell()
            if stalled(previous + chunk):
                collector.capture()
            previous = chunk[-256:]
        except OSError:
            pass
        time.sleep(0.25)


if __name__ == '__main__':
    main(*sys.argv[1:])
