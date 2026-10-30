import json
from pathlib import Path
import tempfile
import unittest
from recording_background_check import Snapshot, read_snapshot, receipt, write_receipt


class RecordingBackgroundEvidenceTests(unittest.TestCase):
    def test_no_growth_or_replaced_session_cannot_prove_background_delivery(self):
        self.assertEqual(receipt(Snapshot('one', 3), Snapshot('one', 3))['status'], 'error')
        self.assertEqual(receipt(Snapshot('one', 3), Snapshot('two', 5))['status'], 'error')
        self.assertEqual(receipt(Snapshot('one', 0), Snapshot('one', 5))['status'], 'error')
        result = receipt(Snapshot('one', 3), Snapshot('one', 5))
        self.assertEqual((result['status'], result['before'], result['after']), ('ok', 3, 5))

    def test_partial_point_is_not_counted_and_receipt_stays_in_runner_tmp(self):
        with tempfile.TemporaryDirectory() as directory:
            journal = Path(directory) / 'tmp/mgrsgps-ui-tests/LiveRecording'
            journal.mkdir(parents=True)
            (journal / 'session.json').write_text(json.dumps({'id': 'one'}))
            (journal / 'points.txt').write_bytes(b'fake first\nfake second\npartial')
            self.assertEqual(read_snapshot(directory), Snapshot('one', 2))
            token = 'C92C12F9-4D49-4CA2-B03A-79818D6E7331'
            write_receipt(directory, token, 'end', {'status': 'ok'})
            self.assertEqual(json.loads((Path(directory) / 'tmp' / f'recording-background-{token}-end.json').read_text()), {'status': 'ok'})
            with self.assertRaises(ValueError):
                write_receipt(directory, '../escape', 'end', {})


if __name__ == '__main__':
    unittest.main()
