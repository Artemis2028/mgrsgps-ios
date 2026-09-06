#!/bin/bash
# Print "<udid>\t<name>" for a usable iPhone simulator on this machine.
#
# Preference order (stable CI screenshots): iPhone 16, then iPhone 15, then
# iPhone 14. If none of those exist on the image, fall back to the previous
# “plain iPhone <n>” heuristic (non-Pro/Plus/Max). Override locally with
# SIMULATOR_DEVICE_NAME="iPhone 16" (exact name match).
#
# Lives in its own file on purpose. It used to be a python -c block embedded in
# the workflow's `run:` scalar, where its unindented lines terminated the YAML
# block early and made the whole file invalid. Anything with its own
# indentation rules stays out of YAML.
#
# Missing preferred names must not hard-fail CI — macos-latest churn is expected.
set -euo pipefail

xcrun simctl list devices available -j | SIMULATOR_DEVICE_NAME="${SIMULATOR_DEVICE_NAME:-}" python3 -c '
import json, os, sys

PREFERRED = ["iPhone 16", "iPhone 15", "iPhone 14"]

data = json.load(sys.stdin)["devices"]
override = os.environ.get("SIMULATOR_DEVICE_NAME", "").strip()

candidates = []
for runtime, devices in data.items():
    if "iOS" not in runtime:
        continue
    for d in devices:
        if not d.get("isAvailable") or "iPhone" not in d["name"]:
            continue
        candidates.append((runtime, d))

if not candidates:
    sys.exit("no available iPhone simulator on this image")

def pick_by_exact_name(name):
    matches = [(runtime, d) for runtime, d in candidates if d["name"] == name]
    if not matches:
        return None
    # Newest runtime wins when several runtimes expose the same device name.
    matches.sort(key=lambda t: t[0], reverse=True)
    runtime, d = matches[0]
    return d["udid"], d["name"]

if override:
    hit = pick_by_exact_name(override)
    if hit is None:
        sys.exit(f"SIMULATOR_DEVICE_NAME={override!r} not found among available iPhones")
    print(hit[0], hit[1], sep="\t")
    raise SystemExit(0)

for preferred in PREFERRED:
    hit = pick_by_exact_name(preferred)
    if hit is not None:
        print(hit[0], hit[1], sep="\t")
        raise SystemExit(0)

# Fallback: prefer a plain "iPhone <n>" over Pro/Plus/Max so a screenshot is a
# normal phone shape; ties break deterministically on runtime + name.
best = None
for runtime, d in candidates:
    rank = ("Pro" in d["name"]) + ("Max" in d["name"]) + ("Plus" in d["name"])
    key = (rank, runtime, d["name"])
    if best is None or key < best[0]:
        best = (key, d["udid"], d["name"])
print(best[1], best[2], sep="\t")
'
