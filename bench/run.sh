#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
exec bash "$root_dir/scripts/run-benchmarks.sh" "$@"
