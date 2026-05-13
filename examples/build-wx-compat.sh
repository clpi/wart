#!/bin/bash
# Build mini-git-enhanced in wart-compatible mode
# Uses only features that wart currently supports well

set -e

echo "Building wart-compatible mini-git-enhanced..."
echo ""

# Find WASI SDK
if [ -z "$WASI_SDK_PATH" ]; then
    if [ -d "$HOME/.local/share/mise/installs/wasi-sdk/27" ]; then
        WASI_SDK_PATH="$HOME/.local/share/mise/installs/wasi-sdk/27"
    elif [ -d "$HOME/.local/share/mise/installs/wasi-sdk/29" ]; then
        WASI_SDK_PATH="$HOME/.local/share/mise/installs/wasi-sdk/29"
    elif [ -d "/opt/wasi-sdk" ]; then
        WASI_SDK_PATH="/opt/wasi-sdk"
    fi
fi

CLANG="$WASI_SDK_PATH/bin/clang"
if [ ! -f "$CLANG" ]; then
    CLANG="$WASI_SDK_PATH/wasi-sdk/bin/clang"
fi

echo "Using WASI SDK: $WASI_SDK_PATH"
echo ""

# Only use features that wart supports well
# Avoid: -mmultivalue, -mreference-types, -mmutable-globals
FEATURES=(
    "-mbulk-memory"     # Bulk memory (partial support in wart)
    "-msign-ext"        # Sign extension (works in wart)
    "-O2"               # Conservative optimization
)

CFLAGS=(
    "-Wall"
    "-Wextra"
    "-std=c11"
    "-D_WASI_EMULATED_PROCESS_CLOCKS"
)

LDFLAGS=(
    "-Wl,--allow-undefined"
    "-Wl,--max-memory=67108864"  # 64 MB
)

echo "Features (wart-compatible):"
for feature in "${FEATURES[@]}"; do
    echo "  $feature"
done
echo ""

"$CLANG" \
    "${CFLAGS[@]}" \
    "${FEATURES[@]}" \
    "${LDFLAGS[@]}" \
    mini-git-enhanced.c \
    -o mini-git-wart.wasm

if [ $? -eq 0 ]; then
    echo "✓ Build successful!"
    echo ""
    SIZE=$(ls -lh mini-git-wart.wasm | awk '{print $5}')
    echo "Output: mini-git-wart.wasm ($SIZE)"
    echo ""
    echo "Testing with wart:"
    /Users/clp/x/wart/zig-out/bin/wart run mini-git-wart.wasm help 2>&1 | head -20
else
    echo "✗ Build failed"
    exit 1
fi
