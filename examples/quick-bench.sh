#!/bin/bash
# Quick performance benchmark for mini-git-enhanced

set -e

WX="/Users/clp/x/wart/zig-out/bin/wart"
WASM="/Users/clp/x/wart/examples/mini-git-enhanced.wasm"

echo "=== Quick Benchmark ==="
echo ""

# Test wart
echo "Testing wart..."
time $WX $WASM help 2>&1 | head -5
echo ""

# Test wasmtime
if command -v wasmtime &> /dev/null; then
    echo "Testing wasmtime..."
    time wasmtime --dir=. $WASM help 2>&1 | head -5
    echo ""
fi

# Test wasmer
if command -v wasmer &> /dev/null; then
    echo "Testing wasmer..."
    time wasmer run --dir=. $WASM -- help 2>&1 | head -5
    echo ""
fi

echo "=== Benchmark complete ==="
