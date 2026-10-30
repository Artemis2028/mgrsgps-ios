"""Observe actual app journal growth while the UI test stays on SpringBoard.

No app GPS injection or app-container writes: receipts go only to the UI-test
runner's temporary directory. The separate simctl route supplies real fixes.
"""
from dataclasses import dataclass
import json
from pathlib import Path
import re
import signal
import subprocess
import sys
import time
import uuid


@dataclass(frozen=True)
class Snapshot:
    session: str
    count: int


def read_snapshot(directory):
    journal = Path(directory) / 'tmp/mgrsgps-ui-tests/LiveRecording'
    metadata = journal / 'session.json'
    if metadata.stat().st_size > 64 * 1024:
        raise ValueError('Unexpected recording metadata size')
    session = json.loads(metadata.read_bytes())['id']
    if not isinstance(session, str) or not session:
        raise ValueError('Missing recording session')
    points = (journal / 'points.txt').read_bytes()
    # Do not count a partially written final line as an accepted point.
    complete = points[:points.rfind(b'\n') + 1]
    return Snapshot(session, sum(bool(line.strip()) for line in complete.splitlines()))


def receipt(before, after):
    result = {'status': 'error', 'before': before.count, 'after': after.count,
              'sameSession': before.session == after.session}
    if before.count > 0 and after.count > before.count and result['sameSession']:
        result['status'] = 'ok'
    return result


def container(simulator, bundle):
    result = subprocess.run(['xcrun', 'simctl', 'get_app_container', simulator, bundle, 'data'],
                            check=True, capture_output=True, text=True, timeout=5)
    return Path(result.stdout.strip())


def write_receipt(directory, token, phase, value):
    # Tokens from log output are data, never paths or commands.
    token = str(uuid.UUID(token)).upper()
    path = Path(directory) / 'tmp' / f'recording-background-{token}-{phase}.json'
    temporary = path.with_suffix('.json.tmp')
    temporary.write_text(json.dumps(value))
    temporary.replace(path)


class Observer:
    def __init__(self, simulator):
        self.simulator = simulator
        self.starts = {}
        self.processed = set()

    def phase(self, phase, token):
        if (phase, token) in self.processed:
            return
        runner = container(self.simulator, 'app.gridfix.ios.uitests.xctrunner')
        try:
            sample = read_snapshot(container(self.simulator, 'app.gridfix.ios'))
            if phase == 'BEGIN':
                self.starts[token] = sample
                value = {'status': 'ok' if sample.count > 0 else 'error', 'before': sample.count}
            elif token in self.starts:
                value = receipt(self.starts[token], sample)
            else:
                value = {'status': 'error', 'detail': 'Background start was not observed'}
        except (OSError, ValueError, KeyError, subprocess.SubprocessError):
            value = {'status': 'error', 'detail': 'Live recording journal could not be observed'}
        write_receipt(runner, token, phase.lower(), value)
        self.processed.add((phase, token))
        print('recording-background', phase, value, flush=True)


def main():
    simulator, log_name = sys.argv[1:3]
    observer = Observer(simulator)
    running = True

    def stop(*_):
        nonlocal running
        running = False

    signal.signal(signal.SIGTERM, stop)
    pattern = re.compile(r'RECORDING_BACKGROUND_CHECK_(BEGIN|END) ([0-9A-Fa-f-]{36})')
    offset, pending = 0, ''
    log = Path(log_name)
    while running:
        try:
            if log.stat().st_size < offset:
                offset, pending = 0, ''
            with log.open(errors='replace') as source:
                source.seek(offset)
                pending += source.read(256 * 1024)
                offset = source.tell()
            lines = pending.split('\n')
            pending = lines.pop()
            for line in lines:
                match = pattern.search(line)
                if match:
                    observer.phase(*match.groups())
        except (OSError, subprocess.SubprocessError):
            # A boot/provider transition must not invent a success receipt.
            pass
        time.sleep(0.2)


if __name__ == '__main__':
    main()
