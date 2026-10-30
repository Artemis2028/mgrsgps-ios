"""Test-only host controls for real simulator fixes, never app-injected locations."""
import re


class PracticeLocationControl:
    def __init__(self):
        self.pending = ''
        self.token = None
        self.phase = None
        self.deadline = 0

    def consume(self, text, now):
        self.pending += text
        lines = self.pending.split('\n')
        self.pending = lines.pop()[-1024:]
        for line in lines:
            match = re.search(r'PRACTICE_SPLITS_(HOLD|ADVANCE|RELEASE) ([a-zA-Z0-9-]+)', line)
            if not match:
                continue
            action, token = match.groups()
            if action == 'HOLD':
                self.token, self.phase, self.deadline = token, 0, now + 120
            elif token == self.token:
                if action == 'ADVANCE':
                    self.phase, self.deadline = 1, now + 120
                else:
                    self.token, self.phase = None, None

    def current(self, now):
        if now >= self.deadline:
            self.token, self.phase = None, None
        return self.phase
