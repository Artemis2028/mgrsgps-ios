import subprocess
import unittest
from types import SimpleNamespace
from unittest.mock import patch
from simulator_location import set_location

class SimulatorLocationRecoveryTests(unittest.TestCase):
    @patch('simulator_location.subprocess.run')
    def test_timeout_does_not_kill_feed_and_next_real_command_can_succeed(self, run):
        run.side_effect = [subprocess.TimeoutExpired(['xcrun','simctl'],20),SimpleNamespace(returncode=0,stdout='',stderr='')]
        self.assertFalse(set_location('test-device',24,54))
        self.assertTrue(set_location('test-device',24.001,54))
        self.assertEqual(run.call_args.args[0][-1],'24.0010000,54.0000000')
    @patch('simulator_location.subprocess.run')
    def test_boot_transition_is_retryable(self, run):
        run.return_value = SimpleNamespace(returncode=149,stdout='',stderr='Device is Shutdown')
        self.assertFalse(set_location('test-device',24,54))
    @patch('simulator_location.subprocess.run')
    def test_unexpected_failure_is_not_hidden_as_a_retry(self, run):
        run.return_value = SimpleNamespace(returncode=2,stdout='',stderr='Invalid device')
        with self.assertRaises(subprocess.CalledProcessError): set_location('bad-device',24,54)

if __name__ == '__main__': unittest.main()
