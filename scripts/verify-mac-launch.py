#!/usr/bin/env python3
"""Launch the actual .app through Launch Services, with isolated records and a memory watchdog."""
import json
from pathlib import Path
import signal
import subprocess
import sys
import time

bundle = Path(sys.argv[1]).resolve()
output = Path(sys.argv[2]).resolve()
output.mkdir(parents=True, exist_ok=True)
result_path = output / "release-launch-result.json"
if result_path.exists():
    raise SystemExit("Use a fresh verification directory.")
executable = str(bundle / "Contents/MacOS/HabitCounter")
samples = []
owned_pids = set()

def sample():
    listing = subprocess.check_output(["ps", "-axo", "pid=,rss=,args="], text=True)
    for line in listing.splitlines():
        fields = line.strip().split(None, 2)
        if len(fields) == 3 and executable in fields[2] and "--startup-check" in fields[2] and str(output) in fields[2]:
            pid, rss = int(fields[0]), int(fields[1])
            owned_pids.add(pid)
            samples.append({"seconds": round(time.monotonic() - started, 1), "pid": pid, "rss_kib": rss})
            if rss > 512 * 1024:
                raise RuntimeError("Release app exceeded the startup memory limit.")

started = time.monotonic()
launch = subprocess.Popen(["open", "-n", "-W", str(bundle), "--args", "--startup-check", str(output)])
try:
    while time.monotonic() - started < 45:
        sample()
        if result_path.exists():
            result = json.loads(result_path.read_text())
            launch.wait(timeout=8)
            if not result.get("passed"):
                raise RuntimeError(json.dumps(result))
            result["peak_main_process_rss_mib"] = round(max((s["rss_kib"] for s in samples), default=0) / 1024, 1)
            result["launched_via_launch_services"] = True
            result["elapsed_seconds"] = round(time.monotonic() - started, 1)
            (output / "verification.json").write_text(json.dumps(result, indent=2))
            print(json.dumps(result, indent=2))
            break
        if launch.poll() is not None:
            raise RuntimeError("App exited before completing its startup checks.")
        time.sleep(1)
    else:
        raise RuntimeError("Actual app startup timed out.")
finally:
    (output / "memory-samples.json").write_text(json.dumps(samples, indent=2))
    # Only this diagnostic instance is eligible for cleanup; never another running app.
    listing = subprocess.check_output(["ps", "-axo", "pid=,args="], text=True)
    for line in listing.splitlines():
        fields = line.strip().split(None, 1)
        if len(fields) == 2 and int(fields[0]) in owned_pids and executable in fields[1] and str(output) in fields[1]:
            try:
                __import__("os").kill(int(fields[0]), signal.SIGTERM)
            except ProcessLookupError:
                pass
