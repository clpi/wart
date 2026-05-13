#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$ROOT_DIR" "$@" <<'PY'
import argparse
import datetime as dt
import hashlib
import json
import pathlib
import subprocess
import sys
import time


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def record(results, suite, case_id, feature, status, duration_ms, stdout, stderr, note):
    results.append(
        {
            "suite": suite,
            "case_id": case_id,
            "feature": feature,
            "status": status,
            "duration_ms": duration_ms,
            "stdout_hash": sha256_bytes(stdout),
            "stderr_hash": sha256_bytes(stderr),
            "note": note,
        }
    )


def run_capture(command, cwd):
    started = time.perf_counter()
    proc = subprocess.run(command, cwd=cwd, capture_output=True)
    duration_ms = int((time.perf_counter() - started) * 1000)
    return proc, duration_ms


root = pathlib.Path(sys.argv[1])
argv = sys.argv[2:]

parser = argparse.ArgumentParser(prog="run-spec-tests.sh")
parser.add_argument("--profile", default="all")
parser.add_argument("--format", choices=("json", "markdown"), default="markdown")
parser.add_argument("--output", default="artifacts/spec")
args = parser.parse_args(argv)

lock_path = root / "third_party" / "spec-lock.json"
lock = json.loads(lock_path.read_text())
selected = [
    suite
    for suite in lock["suites"]
    if args.profile == "all"
    or args.profile == suite["id"]
    or args.profile in suite.get("profiles", [])
]

results = []
gate_failures = []

proc, duration_ms = run_capture(["zig", "build", "test"], root)
status = "passed" if proc.returncode == 0 else "failed"
record(
    results,
    "local",
    "zig-build-test",
    "smoke",
    status,
    duration_ms,
    proc.stdout,
    proc.stderr,
    "Local smoke gate before upstream suite integration.",
)
if status != "passed":
    gate_failures.append("Local zig build test failed.")

if not selected:
    record(
        results,
        "selection",
        "profile-resolution",
        args.profile,
        "failed",
        0,
        b"",
        b"",
        f"No suites matched profile '{args.profile}'.",
    )
    gate_failures.append(f"No suites matched profile '{args.profile}'.")

for suite in selected:
    checkout = root / suite["checkout"]
    started = time.perf_counter()
    if checkout.exists():
        head = subprocess.check_output(
            ["git", "-C", str(checkout), "rev-parse", "HEAD"],
            text=True,
        ).strip()
        suite_status = "passed" if head == suite["commit"] else "failed"
        note = suite["note"]
        if suite_status != "passed":
            note = f"{suite['note']} Expected {suite['commit']} but found {head}."
    else:
        suite_status = "failed"
        note = "Pinned checkout missing. Run scripts/fetch-spec-suites.sh first."
    duration_ms = int((time.perf_counter() - started) * 1000)
    record(
        results,
        suite["id"],
        "lock-sync",
        suite["feature"],
        suite_status,
        duration_ms,
        b"",
        b"",
        note,
    )
    if suite_status != "passed":
        gate_failures.append(f"{suite['id']}: pinned checkout is missing or out of sync.")

    record(
        results,
        suite["id"],
        "runner-integration",
        suite["feature"],
        "unsupported",
        0,
        b"",
        b"",
        "Pinned checkout exists, but wart has not yet integrated this upstream suite into an executable runner.",
    )
    gate_failures.append(f"{suite['id']}: upstream suite runner integration is not implemented yet.")

timestamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
output_dir = root / args.output
output_dir.mkdir(parents=True, exist_ok=True)
json_path = output_dir / f"{timestamp}-{args.profile}.json"
md_path = output_dir / f"{timestamp}-{args.profile}.md"

payload = {
    "profile": args.profile,
    "generated_at": dt.datetime.now().isoformat(),
    "lock_date": lock["lock_date"],
    "gate_passed": not gate_failures,
    "gate_failures": gate_failures,
    "results": results,
}
json_path.write_text(json.dumps(payload, indent=2) + "\n")

lines = [
    f"# Conformance Results: {args.profile}",
    "",
    f"Lock date: `{lock['lock_date']}`",
    f"Gate passed: `{'yes' if not gate_failures else 'no'}`",
    "",
]
if gate_failures:
    lines.append("## Gate Failures")
    for failure in gate_failures:
        lines.append(f"- {failure}")
    lines.append("")

lines.extend(
    [
        "## Results",
        "",
        "| suite | case_id | feature | status | duration_ms | note |",
        "| --- | --- | --- | --- | ---: | --- |",
    ]
)
for result in results:
    note = result["note"].replace("|", "/")
    lines.append(
        f"| {result['suite']} | {result['case_id']} | {result['feature']} | {result['status']} | {result['duration_ms']} | {note} |"
    )
lines.append("")
md_path.write_text("\n".join(lines))

print(f"Wrote {json_path}")
print(f"Wrote {md_path}")

sys.exit(0 if not gate_failures else 1)
PY
