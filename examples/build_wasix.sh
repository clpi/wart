#!/bin/bash

# Build script for WASIX demo
# Requires wasi-sdk or clang with wasm32-wasi target

set -e

echo "Building WASIX demo..."

# Try to find WASI SDK
WASI_SDK_PATH="${WASI_SDK_PATH:-$HOME/.local/share/mise/installs/wasi-sdk/27}"

if [ -d "$WASI_SDK_PATH" ]; then
    CC="$WASI_SDK_PATH/bin/clang"
    echo "Using WASI SDK at: $WASI_SDK_PATH"
else
    # Fallback to system clang
    CC="clang"
    echo "Using system clang"
fi

# Compile WASIX demo
$CC \
    --target=wasm32-wasi \
    -O2 \
    -nostartfiles \
    -Wl,--no-entry \
    -Wl,--export=main \
    -Wl,--allow-undefined \
    -o wasix_demo.wasm \
    wasix_demo.c

echo "Built: wasix_demo.wasm"
echo ""
echo "Run with: ../zig-out/bin/wart wasix_demo.wasm"
