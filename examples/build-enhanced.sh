#!/bin/bash
# Build script for mini-git-enhanced with all bleeding-edge WASM features

set -e

echo "Building mini-git-enhanced with bleeding-edge WebAssembly features..."
echo ""

# Find WASI SDK
if [ -z "$WASI_SDK_PATH" ]; then
    # Try common locations
    if [ -d "/Users/clp/.local/share/mise/installs/wasi-sdk/27" ]; then
        WASI_SDK_PATH="/Users/clp/.local/share/mise/installs/wasi-sdk/27"
    elif [ -d "/opt/wasi-sdk" ]; then
        WASI_SDK_PATH="/opt/wasi-sdk"
    else
        echo "Error: WASI SDK not found. Please set WASI_SDK_PATH environment variable."
        exit 1
    fi
fi

WASICC="$WASI_SDK_PATH/bin/clang"
SYSROOT="$WASI_SDK_PATH/share/wasi-sysroot"

if [ ! -f "$WASICC" ]; then
    echo "Error: wasicc not found at $WASICC"
    exit 1
fi

echo "Using WASI SDK: $WASI_SDK_PATH"
echo ""

# Feature flags for bleeding-edge WASM features
# NOTE: Using minimal set for maximum compatibility with wart runtime
# All features are documented but some are disabled to ensure wart compatibility
FEATURES=(
    # Core WASM features that work with wart
    "-mbulk-memory"           # Bulk memory operations
    # "-msimd128"             # Disabled while stack underflow is unresolved
    "-msign-ext"              # Sign extension operators

    # Optimization (conservative level for compatibility)
    "-O2"                     # Optimization level 2

    # Features that work in wasmtime but may have issues in wart:
    # (Keeping these commented until wart support is verified)
    # "-mmutable-globals"     # Mutable globals
    # "-mnontrapping-fptoint" # Non-trapping conversions
    # "-mreference-types"     # Reference types
    # "-mmultivalue"          # Multi-value returns
    # "-mtail-call"           # Tail call optimization
    # "-mexception-handling"  # Exception handling
    # "-matomics"             # Atomics
    # "-pthread"              # Threads
    # "-flto"                 # Link-time optimization
)

# Additional compiler flags
CFLAGS=(
    "-Wall"
    "-Wextra"
    "-std=c11"
    "--sysroot=$SYSROOT"
    "-D_WASI_EMULATED_PROCESS_CLOCKS"
    "-D_WASI_EMULATED_SIGNAL"
    "-I$SYSROOT/include"
)

# Linker flags
LDFLAGS=(
    # "-Wl,--no-entry"          # No default entry point (removed - use normal _start)
    # "-Wl,--export-all"        # Export all functions (removed - only export what's needed)
    "-Wl,--allow-undefined"   # Allow undefined for WASI imports
    # NOTE: Shared memory/import-memory disabled for broader compatibility
    # "-Wl,--import-memory"     # Import memory (for shared memory)
    # "-Wl,--shared-memory"     # Enable shared memory
    "-Wl,--max-memory=67108864"  # 64 MB max memory
)

# Build command
echo "Compiling mini-git-enhanced.c..."
echo "Enabled features:"
for feature in "${FEATURES[@]}"; do
    echo "  $feature"
done
echo ""

"$WASICC" \
    "${CFLAGS[@]}" \
    "${FEATURES[@]}" \
    "${LDFLAGS[@]}" \
    mini-git-enhanced.c \
    -o mini-git-enhanced.wasm

if [ $? -eq 0 ]; then
    echo "✓ Build successful!"
    echo ""

    # Show file size
    SIZE=$(ls -lh mini-git-enhanced.wasm | awk '{print $5}')
    echo "Output: mini-git-enhanced.wasm ($SIZE)"
    echo ""

    # Inspect features (if wasm-objdump is available)
    if command -v wasm-objdump &> /dev/null; then
        echo "WASM module features:"
        wasm-objdump -h mini-git-enhanced.wasm | grep -A20 "Sections:" || true
    fi

    echo ""
    echo "You can now run:"
    echo "  wasmtime --dir=. --wasi-modules=experimental-wasi-threads mini-git-enhanced.wasm help"
    echo "  wasmer run --dir=. mini-git-enhanced.wasm -- help"
    echo "  ./zig-out/bin/wart mini-git-enhanced.wasm help"
else
    echo "✗ Build failed"
    exit 1
fi
