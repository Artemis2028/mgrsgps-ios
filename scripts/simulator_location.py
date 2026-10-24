"""Send real simulator fixes while tolerating Xcode's boot/restart window."""
import subprocess
import sys


def set_location(simulator, latitude, longitude):
    command = ["xcrun", "simctl", "location", simulator, "set", f"{latitude:.7f},{longitude:.7f}"]
    result = subprocess.run(command, capture_output=True, text=True, timeout=20)
    if result.returncode == 0:
        return True
    # Xcode may shut down/reboot the device between build and test launch.
    # Keep the host feed alive; never replace actual locations with app mocks.
    if "Shutdown" in result.stderr or "Booting" in result.stderr:
        print("Waiting for simulator location service: " + result.stderr.strip(), file=sys.stderr, flush=True)
        return False
    print(result.stderr, file=sys.stderr, flush=True)
    raise subprocess.CalledProcessError(result.returncode, command, output=result.stdout, stderr=result.stderr)
