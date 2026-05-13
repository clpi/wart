#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$ROOT_DIR" <<'PY'
import json
import pathlib
import subprocess
import sys

root = pathlib.Path(sys.argv[1])
lock_path = root / "third_party" / "spec-lock.json"
lock = json.loads(lock_path.read_text())

for suite in lock["suites"]:
    checkout = root / suite["checkout"]
    checkout.parent.mkdir(parents=True, exist_ok=True)
    repo = suite["repo"]
    commit = suite["commit"]

    if checkout.exists():
        subprocess.run(
            ["git", "-C", str(checkout), "remote", "set-url", "origin", repo],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    else:
        print(f"Cloning {suite['id']} from {repo}")
        subprocess.run(
            ["git", "clone", "--filter=blob:none", repo, str(checkout)],
            check=True,
        )

    print(f"Fetching {suite['id']} at {commit}")
    subprocess.run(
        ["git", "-C", str(checkout), "fetch", "--depth", "1", "origin", commit],
        check=True,
    )
    subprocess.run(
        ["git", "-C", str(checkout), "checkout", "--detach", commit],
        check=True,
    )
    head = subprocess.check_output(
        ["git", "-C", str(checkout), "rev-parse", "HEAD"],
        text=True,
    ).strip()
    if head != commit:
        raise SystemExit(f"{suite['id']}: expected {commit}, got {head}")
    print(f"Pinned {suite['id']} -> {head}")
PY
