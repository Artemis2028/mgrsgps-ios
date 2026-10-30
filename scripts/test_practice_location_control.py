import unittest
from practice_location_control import PracticeLocationControl


class PracticeLocationControlTests(unittest.TestCase):
    def test_fragmented_logged_marker_holds_then_advances_only_matching_run(self):
        control = PracticeLocationControl()
        control.consume('timestamp PRACTICE_SPLITS_HO', 10)
        self.assertIsNone(control.current(10))
        control.consume('LD run-a\n', 11)
        self.assertEqual(control.current(12), 0)
        control.consume('PRACTICE_SPLITS_ADVANCE old-run\nPRACTICE_SPLITS_RELEASE old-run\n', 13)
        self.assertEqual(control.current(14), 0)
        control.consume('PRACTICE_SPLITS_ADVANCE run-a\n', 15)
        self.assertEqual(control.current(16), 1)
        control.consume('PRACTICE_SPLITS_RELEASE run-a\n', 17)
        self.assertIsNone(control.current(18))

    def test_abandoned_hold_expires_and_new_run_replaces_old_token(self):
        control = PracticeLocationControl()
        control.consume('PRACTICE_SPLITS_HOLD first\n', 0)
        self.assertIsNone(control.current(120))
        control.consume('PRACTICE_SPLITS_HOLD next\n', 121)
        control.consume('PRACTICE_SPLITS_ADVANCE first\n', 122)
        self.assertEqual(control.current(123), 0)
