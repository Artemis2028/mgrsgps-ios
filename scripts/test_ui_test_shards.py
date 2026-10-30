import unittest
from pathlib import Path
from ui_test_shards import SPECIAL, GROUPS, arguments, discover, partition

class UITestShardTests(unittest.TestCase):
    def setUp(self):
        self.classes = discover(Path(__file__).resolve().parents[1]/'App/UITests')
    def testEveryClassRunsExactlyOnceOrInDedicatedLocationScenario(self):
        groups = partition(self.classes)
        all_names = sum(groups.values(),[])
        self.assertEqual(len(all_names),len(set(all_names)))
        self.assertEqual(set(all_names) | SPECIAL,self.classes)
        self.assertFalse(set(all_names) & SPECIAL)
        args = sum((arguments(g,self.classes) for g in GROUPS),[])
        self.assertEqual(args.count('-only-testing:MGRSGPSTests'),1)
    def testNewClassAutomaticallyJoinsExactlyOneStableShard(self):
        name = 'NewCoverageWorkflowTests'
        result = partition(self.classes|{name})
        self.assertEqual(sum(name in names for names in result.values()),1)
        self.assertEqual(result,partition(self.classes|{name}))
    def testRenamedOrDeletedConfiguredTestsFailInsteadOfDisappearing(self):
        with self.assertRaises(ValueError): partition(self.classes-{'ProjectionWorkflowTests'})
        with self.assertRaises(ValueError): partition(self.classes-{'BoundaryWorkflowTests'})
