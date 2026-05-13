#!/bin/bash
# Build mini-git-ultra with maximum WASM features
# Including wasi-threads, SIMD, atomics, and bulk memory

set -e

echo "Building mini-git-ultra with bleeding-edge WebAssembly features..."
echo ""

# Find WASI SDK
if [ -z "$WASI_SDK_PATH" ]; then
    # Try to find wasi-sdk with thread support (need version 20+)
    if [ -d "$HOME/.local/share/mise/installs/wasi-sdk/27" ]; then
        WASI_SDK_PATH="$HOME/.local/share/mise/installs/wasi-sdk/27"
    elif [ -d "$HOME/.local/share/mise/installs/wasi-sdk/29" ]; then
        WASI_SDK_PATH="$HOME/.local/share/mise/installs/wasi-sdk/29"
    elif [ -d "/opt/wasi-sdk" ]; then
        WASI_SDK_PATH="/opt/wasi-sdk"
    else
        echo "Error: WASI SDK not found. Please install wasi-sdk 20+ with thread support."
        echo "  brew install wasi-sdk"
        echo "  OR download from https://github.com/WebAssembly/wasi-sdk/releases"
        exit 1
    fi
fi

CLANG="$WASI_SDK_PATH/bin/clang"
if [ ! -f "$CLANG" ]; then
    CLANG="$WASI_SDK_PATH/wasi-sdk/bin/clang"
fi

if [ ! -f "$CLANG" ]; then
    echo "Error: clang not found at $CLANG"
    exit 1
fi

echo "Using WASI SDK: $WASI_SDK_PATH"
echo "Compiler: $CLANG"
echo ""

# Maximum WASM features
# NOTE: Threads require shared memory and atomics
FEATURES=(
    # Core WASM features
    "-mbulk-memory"           # Bulk memory operations (memory.copy, memory.fill)
    "-msimd128"               # SIMD support (v128)
    "-msign-ext"              # Sign extension operators
    "-mmutable-globals"       # Mutable globals
    "-mnontrapping-fptoint"   # Non-trapping float-to-int conversions
    "-mmultivalue"            # Multi-value returns
    "-mreference-types"       # Reference types (externref, funcref)

    # Thread support (requires wasi-sdk 20+)
    "-pthread"                # POSIX threads support
    "-matomics"               # Atomic operations
    "-mbulk-memory"           # Required for threads

    # Optimization
    "-O3"                     # Maximum optimization
    "-flto"                   # Link-time optimization
)

# Compiler flags
CFLAGS=(
    "-Wall"
    "-Wextra"
    "-std=c11"
    "-D_WASI_EMULATED_PROCESS_CLOCKS"
    "-D_WASI_EMULATED_SIGNAL"
    "-D_WASI_EMULATED_MMAN"
)

# Linker flags for threads
LDFLAGS=(
    "-Wl,--import-memory"       # Import memory (required for threads)
    "-Wl,--shared-memory"       # Enable shared memory
    "-Wl,--max-memory=134217728"  # 128 MB max memory
    "-Wl,--export-dynamic"      # Export all symbols
    "-Wl,--export=__heap_base"  # Export heap base
    "-Wl,--export=__data_end"   # Export data end
    "-Wl,--export=malloc"       # Export malloc
    "-Wl,--export=free"         # Export free
)

# Build command
echo "Compiling mini-git-ultra.c with features:"
for feature in "${FEATURES[@]}"; do
    echo "  $feature"
done
echo ""

"$CLANG" \
    "${CFLAGS[@]}" \
    "${FEATURES[@]}" \
    "${LDFLAGS[@]}" \
    mini-git-ultra.c \
    -o mini-git-ultra.wasm

if [ $? -eq 0 ]; then
    echo "✓ Build successful!"
    echo ""

    # Show file size
    SIZE=$(ls -lh mini-git-ultra.wasm | awk '{print $5}')
    echo "Output: mini-git-ultra.wasm ($SIZE)"
    echo ""

    # Inspect WASM features
    if command -v wasm-objdump &> /dev/null; then
        echo "WASM module features:"
        echo ""
        wasm-objdump -h mini-git-ultra.wasm | head -30
        echo ""
        echo "Import section:"
        wasm-objdump -x mini-git-ultra.wasm | grep -A20 "Import\[" | head -25
    fi

    echo ""
    echo "You can now run:"
    echo "  # With wasmtime (requires --wasm-features=threads,bulk-memory)"
    echo "  wasmtime --dir=. --wasm-features=threads,bulk-memory,simd \\
"
    echo "    --wasi-modules=experimental-wasi-threads \\
"
    echo "    mini-git-ultra.wasm help"
    echo ""
    echo "  # With wart (if thread support is available)"
    echo "  wart run mini-git-ultra.wasm help"
    echo ""
    echo "  # Run benchmark to test parallel hashing"
    echo "  wasmtime --dir=. --wasm-features=threads,bulk-memory,simd \\
"
    echo "    --wasi-modules=experimental-wasi-threads \\
"
    echo "    mini-git-ultra.wasm benchmark"
else
    echo "✗ Build failed"
    echo ""
    echo "If you get pthread errors, your WASI SDK may not support threads."
    echo "Try building without threads using build-enhanced.sh instead."
    exit 1
fi
