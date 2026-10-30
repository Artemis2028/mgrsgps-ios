from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from ui_hang_diagnostics import Collector, owned_pids, stalled


class UIHangDiagnosticsTests(unittest.TestCase):
    def test_only_exact_owned_binary_is_eligible_not_other_apps_or_arguments(self):
        binary = Path('/Devices/TEST/data/MGRSGPS.app/MGRSGPS')
        processes = (' 1 ' + str(binary) + '\n 42 ' + str(binary) + '\n'
                     ' 43 /Devices/OTHER/data/MGRSGPS.app/MGRSGPS\n'
                     ' 44 ' + str(binary) + ' --argument\n 45 /usr/bin/sample\n')
        self.assertEqual(owned_pids(processes, binary), [42])
        self.assertFalse(stalled('Normal native test case failed: expected count'))
        self.assertTrue(stalled('App animations complete notification not received'))
        self.assertTrue(stalled('Unable to perform work: process main thread busy for 30.0s'))

    def test_duplicate_stalls_capture_once_and_total_is_bounded(self):
        with tempfile.TemporaryDirectory() as directory:
            collector = Collector('TEST', directory)
            bundle = '/Devices/TEST/data/MGRSGPS.app'
            def command(args, **kwargs):
                if args[0] == 'xcrun':
                    return bundle
                return f'42 {bundle}/MGRSGPS\n'
            with patch('ui_hang_diagnostics.subprocess.check_output', side_effect=command), \
                 patch('ui_hang_diagnostics.subprocess.run') as sample:
                sample.return_value.returncode = 0
                collector.capture(); collector.capture()
                self.assertEqual(sample.call_count, 1)
                self.assertEqual(sample.call_args.args[0][:4], ['/usr/bin/sample', '42', '1', '1'])
                self.assertTrue(Path(sample.call_args.args[0][-1]).is_relative_to(directory))
                collector.seen = {42, 43, 44}
                collector.capture()
                self.assertEqual(sample.call_count, 1)

    def test_wrong_simulator_container_never_samples(self):
        with tempfile.TemporaryDirectory() as directory:
            collector = Collector('TEST', directory)
            with patch('ui_hang_diagnostics.subprocess.check_output', return_value='/Devices/OTHER/MGRSGPS.app'), \
                 patch('ui_hang_diagnostics.subprocess.run') as sample:
                collector.capture()
                sample.assert_not_called()


if __name__ == '__main__':
    unittest.main()
