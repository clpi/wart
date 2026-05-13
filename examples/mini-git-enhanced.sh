#!/bin/bash
# Mini-Git Enhanced WASM Wrapper Script
# Usage: ./mini-git-enhanced.sh <command> [args]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WASM_FILE="$SCRIPT_DIR/mini-git-enhanced.wasm"

# Detect which WASM runtime is available
if command -v wasmtime &> /dev/null; then
    exec wasmtime --dir=. "$WASM_FILE" "$@"
elif command -v wasmer &> /dev/null; then
    exec wasmer run --dir=. "$WASM_FILE" -- "$@"
elif [ -x "$SCRIPT_DIR/../zig-out/bin/wart" ]; then
    exec "$SCRIPT_DIR/../zig-out/bin/wart" "$WASM_FILE" "$@"
else
    echo "Error: No WASM runtime found. Please install wasmtime, wasmer, or build wart."
    exit 1
fi
