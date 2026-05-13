#!/bin/bash
# Benchmark mini-git-enhanced across different runtimes

set -e

WASM_FILE="mini-git-enhanced.wasm"
ITERATIONS=10
TEMP_DIR=$(mktemp -d)

echo "========================================="
echo "Mini-Git Enhanced Performance Benchmark"
echo "========================================="
echo "WASM file: $WASM_FILE"
echo "Iterations: $ITERATIONS"
echo "Temp dir: $TEMP_DIR"
echo ""

# Create test data
cd "$TEMP_DIR"
for i in {1..50}; do
    echo "File $i content with some data" > "file$i.txt"
done

# Function to benchmark a runtime
benchmark_runtime() {
    local runtime_name="$1"
    local runtime_cmd="$2"
    local wasm_path="$3"

    echo "Testing $runtime_name..."

    # Benchmark: Show help (cold start)
    local help_total=0
    for i in $(seq 1 $ITERATIONS); do
        local start=$(date +%s%N)
        eval "$runtime_cmd $wasm_path help" > /dev/null 2>&1 || true
        local end=$(date +%s%N)
        local duration=$(( (end - start) / 1000000 )) # Convert to ms
        help_total=$((help_total + duration))
    done
    local help_avg=$((help_total / ITERATIONS))

    # Benchmark: Init repository
    rm -rf .minigit
    local init_start=$(date +%s%N)
    eval "$runtime_cmd $wasm_path initialize" > /dev/null 2>&1 || \
    eval "$runtime_cmd $wasm_path verify" > /dev/null 2>&1 || true
    local init_end=$(date +%s%N)
    local init_time=$(( (init_end - init_start) / 1000000 ))

    # Benchmark: Add 50 files (includes hashing)
    local add_total=0
    for file in file*.txt; do
        local start=$(date +%s%N)
        eval "$runtime_cmd $wasm_path add $file" > /dev/null 2>&1 || true
        local end=$(date +%s%N)
        local duration=$(( (end - start) / 1000000 ))
        add_total=$((add_total + duration))
    done
    local add_avg=$((add_total / 50))

    echo "  Help (avg):     ${help_avg}ms"
    echo "  Init:           ${init_time}ms"
    echo "  Add file (avg): ${add_avg}ms"
    echo "  Add 50 files:   ${add_total}ms"
    echo ""

    # Return results
    echo "$runtime_name,$help_avg,$init_time,$add_avg,$add_total"
}

# Find runtimes
WX="/Users/clp/x/wart/zig-out/bin/wart"
WASMTIME=$(which wasmtime 2>/dev/null || echo "")
WASMER=$(which wasmer 2>/dev/null || echo "")
WASM_PATH="$(cd "$(dirname "$0")" && pwd)/$WASM_FILE"

# Run benchmarks
echo "Running benchmarks..."
echo ""

results=()

# Benchmark wart
if [ -x "$WX" ]; then
    result=$(benchmark_runtime "wart" "$WX" "$WASM_PATH")
    results+=("$result")
else
    echo "wart not found, skipping"
fi

# Benchmark wasmtime
if [ -n "$WASMTIME" ]; then
    result=$(benchmark_runtime "wasmtime" "$WASMTIME --dir=." "$WASM_PATH")
    results+=("$result")
else
    echo "wasmtime not found, skipping"
fi

# Benchmark wasmer
if [ -n "$WASMER" ]; then
    result=$(benchmark_runtime "wasmer" "$WASMER run --dir=. -- " "$WASM_PATH")
    results+=("$result")
else
    echo "wasmer not found, skipping"
fi

# Cleanup
cd - > /dev/null
rm -rf "$TEMP_DIR"

# Display summary
echo "========================================="
echo "Summary (lower is better)"
echo "========================================="
printf "%-12s %10s %10s %10s %10s\n" "Runtime" "Help(ms)" "Init(ms)" "Add(ms)" "Total(ms)"
echo "---------------------------------------------------------"

for result in "${results[@]}"; do
    IFS=',' read -r name help init add total <<< "$result"
    printf "%-12s %10s %10s %10s %10s\n" "$name" "$help" "$init" "$add" "$total"
done

# Determine winner
echo ""
if [ ${#results[@]} -gt 1 ]; then
    IFS=',' read -r wart_name wart_help wart_init wart_add wart_total <<< "${results[0]}"
    IFS=',' read -r wt_name wt_help wt_init wt_add wt_total <<< "${results[1]}"

    if [ -n "$wart_total" ] && [ -n "$wt_total" ] && [ "$wart_total" -gt 0 ] && [ "$wt_total" -gt 0 ]; then
        if [ "$wart_total" -lt "$wt_total" ]; then
            speedup=$(awk "BEGIN {printf \"%.2f\", $wt_total / $wart_total}")
            echo "wart is ${speedup}x faster than $wt_name!"
        else
            speedup=$(awk "BEGIN {printf \"%.2f\", $wart_total / $wt_total}")
            echo "$wt_name is ${speedup}x faster than wart"
        fi
    fi
fi
