#!/usr/bin/env python3
"""Run the full isolated regression suite once for each supplied Xray binary.

No binaries are downloaded and no system services are changed by this runner.
Requires Linux/WSL, Bash, jq, openssl, sing-box and mihomo for zero-skip coverage.
"""
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--xray", action="append", type=Path, required=True, help="Path to an executable; repeat for each version")
    parser.add_argument("--report", type=Path, required=True, help="JSON report; per-version logs are written beside it")
    args = parser.parse_args()
    binaries = [path.resolve(strict=True) for path in args.xray]
    if any(not os.access(binary, os.X_OK) for binary in binaries):
        parser.error("Every Xray binary must be executable")
    report_path = args.report.resolve()
    report_path.parent.mkdir(parents=True, exist_ok=True)
    logs = report_path.with_suffix(".logs")
    logs.mkdir(exist_ok=True)
    report = {"script_sha256": hashlib.sha256((ROOT / "argov.sh").read_bytes()).hexdigest(), "versions": []}
    for index, binary in enumerate(binaries, 1):
        version = subprocess.run([str(binary), "version"], capture_output=True, text=True, check=True, timeout=10).stdout.splitlines()[0]
        print(f"[{index}/{len(binaries)}] {version}", flush=True)
        started = time.monotonic()
        with tempfile.TemporaryDirectory(prefix="argov-xray-matrix-") as directory:
            (Path(directory) / "xray").symlink_to(binary)
            env = dict(os.environ, PATH=directory + os.pathsep + os.environ.get("PATH", ""), PYTHONDONTWRITEBYTECODE="1")
            # The tested script is part of this checkout, not an inherited override.
            env.pop("ARGOV_TEST_SCRIPT", None)
            result = subprocess.run(["bash", "tests/argov_static_tests.sh", "argov.sh"], cwd=ROOT,
                                    env=env, capture_output=True, text=True, timeout=300)
        output = result.stdout + result.stderr
        counts = [int(count) for count in re.findall(r"Ran (\d+) tests? in", output)]
        skipped = sum(int(count) for count in re.findall(r"skipped=(\d+)", output))
        # Five unittest suites must run; static/compat/subscription/relay checks
        # run as part of the same shell command and fail its exit status.
        passed = result.returncode == 0 and len(counts) == 5 and skipped == 0
        log_path = logs / f"{index:02d}.log"
        log_path.write_text(version + "\n" + output, encoding="utf-8")
        record = {"version": version, "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
                  "passed": passed, "exit_code": result.returncode, "tests": sum(counts), "skipped": skipped,
                  "seconds": round(time.monotonic() - started, 2), "log": str(log_path)}
        report["versions"].append(record)
        report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"  {'PASS' if passed else 'FAIL'}: {record['tests']} tests, {skipped} skipped, {record['seconds']}s", flush=True)
        if not passed:
            print(output[-16000:], flush=True)
    return 0 if all(item["passed"] for item in report["versions"]) else 1


if __name__ == "__main__":
    sys.exit(main())
