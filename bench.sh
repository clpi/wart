#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

RUNS="${RUNS:-5}"
ZIG_BIN="${ZIG:-zig}"
WX_BIN="$ROOT_DIR/zig-out/bin/wart"
WX_ARGS="${WART_BENCH_ARGS:--j}"
RESULTS_DIR="$ROOT_DIR/bench/results"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$ROOT_DIR/.cache}"
export ZIG_GLOBAL_CACHE_DIR="${ZIG_GLOBAL_CACHE_DIR:-$ROOT_DIR/.zig-cache/global}"

mkdir -p "${XDG_CACHE_HOME}" "${ZIG_GLOBAL_CACHE_DIR}"

echo "Building wart (ReleaseFast + LLVM + Native CPU) with ${ZIG_BIN}..."
"${ZIG_BIN}" build --release=fast -Dcpu=native -Duse-llvm=true

if ! "${ROOT_DIR}/scripts/build-comprehensive-git-wasm.sh" >/dev/null; then
  echo "warning: failed to build git_replacement_comprehensive.wasm; continuing with existing artifacts" >&2
fi

if [[ ! -x "${WX_BIN}" ]]; then
  echo "wart binary not found at ${WX_BIN}"
  exit 1
fi

if command -v wasm-tools >/dev/null 2>&1 && [[ -f "bench/comprehensive/wasm/wasm30_gc_bench.wat" ]]; then
  mkdir -p bench/wasm
  if ! wasm-tools parse bench/comprehensive/wasm/wasm30_gc_bench.wat -o bench/wasm/wasm30_gc_bench.wasm; then
    echo "warning: failed to build wasm30_gc_bench.wasm; continuing without it" >&2
  fi
fi

bench_files=()

# Pull in curated benchmark workloads when available.
[[ -f "zig-out/bin/opcodes_cli.wasm" ]] && bench_files+=("zig-out/bin/opcodes_cli.wasm")
for extra in bench/wasm/*.wasm; do
  [[ -f "${extra}" ]] && bench_files+=("${extra}")
done
for extra in examples/*.wasm; do
  [[ -f "${extra}" ]] && bench_files+=("${extra}")
done

mkdir -p "${RESULTS_DIR}"

# Pre-flight: verify wart can execute each file (informational)
echo "Verifying wart can execute benchmark files..."
for wasm in "${bench_files[@]}"; do
  [[ -f "${wasm}" ]] || continue
  if "${WX_BIN}" "${wasm}" >/dev/null 2>&1; then
    printf "  %-50s OK\n" "${wasm}"
  else
    printf "  %-50s FAIL (will still benchmark with --ignore-failure)\n" "${wasm}"
  fi
done
echo ""

runtime_count=1
WASMTIME_BIN=""
WASMER_BIN=""
WASMEDGE_BIN=""
WAZERO_BIN=""
WASM3_BIN=""

if command -v wasmtime >/dev/null 2>&1; then
  WASMTIME_BIN="$(command -v wasmtime)"
  runtime_count=$((runtime_count + 1))
else
  echo "Skipping wasmtime (not on PATH)"
fi

if command -v wasmer >/dev/null 2>&1; then
  WASMER_BIN="$(command -v wasmer)"
  runtime_count=$((runtime_count + 1))
else
  echo "Skipping wasmer (not on PATH)"
fi

if command -v wasmedge >/dev/null 2>&1; then
  WASMEDGE_BIN="$(command -v wasmedge)"
  runtime_count=$((runtime_count + 1))
else
  echo "Skipping wasmedge (not on PATH)"
fi

if command -v wazero >/dev/null 2>&1; then
  WAZERO_BIN="$(command -v wazero)"
  runtime_count=$((runtime_count + 1))
else
  echo "Skipping wazero (not on PATH)"
fi

if command -v wasm3 >/dev/null 2>&1; then
  WASM3_BIN="$(command -v wasm3)"
  runtime_count=$((runtime_count + 1))
else
  echo "Skipping wasm3 (not on PATH)"
fi

if [[ "${runtime_count}" -lt 2 ]]; then
  echo "No competing runtimes detected; install wasmtime/wasmer/wasmedge/wazero/wasm3 for comparisons."
fi

runtime_available() {
  case "$1" in
    wart) [[ -n "${WX_BIN}" ]] ;;
    wasmtime) [[ -n "${WASMTIME_BIN}" ]] ;;
    wasmer) [[ -n "${WASMER_BIN}" ]] ;;
    wasmedge) [[ -n "${WASMEDGE_BIN}" ]] ;;
    wazero) [[ -n "${WAZERO_BIN}" ]] ;;
    wasm3) [[ -n "${WASM3_BIN}" ]] ;;
    *) return 1 ;;
  esac
}

runtime_command() {
  local name="$1"
  local wasm="$2"
  case "${name}" in
    wart)
      if [[ -n "${WX_ARGS}" ]] && "${WX_BIN}" ${WX_ARGS} "${wasm}" >/dev/null 2>&1; then
        printf '%q %s %q' "${WX_BIN}" "${WX_ARGS}" "${wasm}"
      else
        printf '%q %q' "${WX_BIN}" "${wasm}"
      fi
      ;;
    wasmtime)
      printf '%q %q' "${WASMTIME_BIN}" "${wasm}"
      ;;
    wasmer)
      printf '%q run %q' "${WASMER_BIN}" "${wasm}"
      ;;
    wasmedge)
      printf '%q %q' "${WASMEDGE_BIN}" "${wasm}"
      ;;
    wazero)
      printf '%q run %q' "${WAZERO_BIN}" "${wasm}"
      ;;
    wasm3)
      printf '%q %q' "${WASM3_BIN}" "${wasm}"
      ;;
    *)
      echo "unknown runtime ${name}" >&2
      return 1
      ;;
  esac
}

run_hyperfine() {
  local wasm="$1"
  echo "Benchmarking ${wasm} (${RUNS} runs)"
  local commands=()
  for name in wart wasmtime wasmer wasmedge wazero wasm3; do
    runtime_available "${name}" || continue
    commands+=("$(runtime_command "${name}" "${wasm}")")
  done
  local base_name
  base_name="$(basename "${wasm}")"
  local json_file="${RESULTS_DIR}/${TIMESTAMP}-${base_name%.wasm}.json"
  local markdown_file="${RESULTS_DIR}/${TIMESTAMP}-${base_name%.wasm}.md"

  hyperfine \
    --ignore-failure \
    --warmup 1 \
    --runs "${RUNS}" \
    --export-json "${json_file}" \
    --export-markdown "${markdown_file}" \
    "${commands[@]}"

  echo "Saved ${json_file}"
  echo "Saved ${markdown_file}"
}

run_fallback_timer() {
  local wasm="$1"
  echo "Benchmarking ${wasm} (fallback timer, ${RUNS} runs)"
  for name in wart wasmtime wasmer wasmedge wazero wasm3; do
    runtime_available "${name}" || continue
    time bash -c "for _ in \$(seq 1 ${RUNS}); do $(runtime_command "${name}" "${wasm}") >/dev/null; done"
  done
}

if command -v hyperfine >/dev/null 2>&1; then
  for wasm in "${bench_files[@]}"; do
    [[ -f "${wasm}" ]] || continue
    run_hyperfine "${wasm}"
  done
else
  echo "hyperfine not found; using time fallback."
  for wasm in "${bench_files[@]}"; do
    [[ -f "${wasm}" ]] || continue
    run_fallback_timer "${wasm}"
  done
fi

echo "Benchmarks complete. Review the generated measurements before making performance claims."
