#!/usr/bin/env python3
"""Partition every UI XCTest class; dedicated location scenarios keep their own feed."""
import argparse
import hashlib
from pathlib import Path
import re

SPECIAL = {name + 'WorkflowTests' for name in ('Boundary','Navigation','Practice','PositionFix','Movement')}
# Run 109: library UI 80.5 min hit the job deadline while map finished in
# 63 min overall. Move the measured 11.3-minute waypoint class to map and
# assign the new instrument cases to field; retain every case and three workers.
GROUPS = {
    'library': 'Backup ImportReview Interchange KMLPackage LargeLibrary LibrarySearch Library WaypointRecovery WaypointSaveFailure'.split(),
    'map': 'Graphic MapLasso MapLayer MapTool Measurement MilitarySymbol NavigationLane OfflineDownloadLifetime Terrain ProtectedFile Waypoint'.split(),
    'field': 'FieldEdit FieldExport FieldFix GridNaming InstrumentAccessibility LaneCue LiveActivity Orientation Planning PositionQR PositionSolar Projection RoutePDF TAKEnrollment TAKLocal TrackRecording'.split(),
}

def discover(directory):
    classes = []
    for file in sorted(Path(directory).glob('*.swift')):
        classes += re.findall(r'^\s*(?:final\s+)?class\s+(\w+)\s*:\s*XCTestCase\b',file.read_text(),re.M)
    if len(classes) != len(set(classes)):
        raise ValueError('Duplicate UI XCTest class')
    if not classes:
        raise ValueError('No UI XCTest classes discovered')
    return set(classes)

def partition(classes):
    owners = {}
    for group,names in GROUPS.items():
        for name in names:
            name += 'WorkflowTests'
            if name in owners: raise ValueError('Duplicate shard assignment: '+name)
            owners[name] = group
    missing = (set(owners) | SPECIAL) - classes
    if missing: raise ValueError('Configured classes missing: '+', '.join(sorted(missing)))
    result = {group: [] for group in GROUPS}
    for name in sorted(classes-SPECIAL):
        # New classes automatically run once; a later measured rebalancing can name them above.
        group = owners.get(name) or tuple(GROUPS)[int.from_bytes(hashlib.sha256(name.encode()).digest()[:4],'big') % len(GROUPS)]
        result[group].append(name)
    return result

def arguments(group,classes):
    selected = partition(classes)[group]
    return (['-only-testing:MGRSGPSTests'] if group == 'field' else []) + ['-only-testing:MGRSGPSUITests/'+name for name in selected]

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('shard',choices=GROUPS)
    parser.add_argument('--directory',type=Path,default=Path(__file__).resolve().parents[1]/'App/UITests')
    args = parser.parse_args()
    print('\n'.join(arguments(args.shard,discover(args.directory))))
