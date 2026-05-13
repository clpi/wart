#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${ROOT_DIR}/bench/comprehensive/git_replacement_comprehensive.cpp"
OUT="${ROOT_DIR}/bench/wasm/git_replacement_comprehensive.wasm"

if [[ ! -f "${SRC}" ]]; then
  echo "source file not found: ${SRC}" >&2
  exit 1
fi

mkdir -p "$(dirname "${OUT}")"

if command -v zig >/dev/null 2>&1; then
  zig c++ \
    -target wasm32-wasi \
    -std=c++20 \
    -O3 \
    -DNDEBUG \
    -fno-exceptions \
    -fno-rtti \
    -fno-stack-protector \
    -Wl,--strip-all \
    -o "${OUT}" \
    "${SRC}"
elif command -v clang++ >/dev/null 2>&1; then
  clang++ \
    --target=wasm32-wasi \
    -std=c++20 \
    -O3 \
    -DNDEBUG \
    -fno-exceptions \
    -fno-rtti \
    -fno-stack-protector \
    -Wl,--strip-all \
    -o "${OUT}" \
    "${SRC}"
else
  echo "need zig or clang++ to build ${OUT}" >&2
  exit 1
fi

echo "built ${OUT}"
