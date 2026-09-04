#!/bin/bash
# Print "<udid>\t<name>" for a usable iPhone simulator on this machine.
#
# Lives in its own file on purpose. It used to be a python -c block embedded in
# the workflow's `run:` scalar, where its unindented lines terminated the YAML
# block early and made the whole file invalid. Anything with its own
# indentation rules stays out of YAML.
#
# Nothing here hard-codes a device name or a runtime version, because the
# GitHub macOS image changes both without warning.
set -euo pipefail

xcrun simctl list devices available -j | python3 -c '
import json, sys

data = json.load(sys.stdin)["devices"]
best = None
for runtime, devices in data.items():
    if "iOS" not in runtime:
        continue
    for d in devices:
        if not d.get("isAvailable") or "iPhone" not in d["name"]:
            continue
        # Prefer a plain "iPhone <n>" over Pro/Plus/Max so a screenshot is a
        # normal phone shape; ties break deterministically on runtime + name.
        rank = ("Pro" in d["name"]) + ("Max" in d["name"]) + ("Plus" in d["name"])
        key = (rank, runtime, d["name"])
        if best is None or key < best[0]:
            best = (key, d["udid"], d["name"])
if best is None:
    sys.exit("no available iPhone simulator on this image")
print(best[1], best[2], sep="\t")
'
