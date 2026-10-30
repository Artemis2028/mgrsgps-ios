"""Send real simulator fixes while tolerating Xcode's boot/restart window."""
import subprocess
import sys


def set_location(simulator, latitude, longitude):
    command = ["xcrun", "simctl", "location", simulator, "set", f"{latitude:.7f},{longitude:.7f}"]
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=20)
    except subprocess.TimeoutExpired:
        # CoreSimulator can stall briefly under a build/test workload. run()
        # kills/reaps the timed-out child; the host feed must send the next
        # real fix instead of silently dying for the rest of the test suite.
        print("Simulator location command timed out; retrying the next sample", file=sys.stderr, flush=True)
        return False
    if result.returncode == 0:
        return True
    # Xcode may shut down/reboot the device between build and test launch.
    # Keep the host feed alive; never replace actual locations with app mocks.
    if "Shutdown" in result.stderr or "Booting" in result.stderr:
        print("Waiting for simulator location service: " + result.stderr.strip(), file=sys.stderr, flush=True)
        return False
    print(result.stderr, file=sys.stderr, flush=True)
    raise subprocess.CalledProcessError(result.returncode, command, output=result.stdout, stderr=result.stderr)
