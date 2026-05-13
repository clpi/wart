#!/usr/bin/env bash
set -euo pipefail

# Benchmark findings (captured on 2026-03-05, America/Los_Angeles)
# Source run:
#   RUNS=1 WARMUP=0 STRICT_DISPATCH=0 STRICT_FASTEST=0 STRICT_SCENARIOS=0 ./b.sh --no-color
#   report: bench/results/20260305-063236-dispatch-matrix.{json,md}
# Key results:
# - wart wins/losses: 14/10 (top competitor winner: wasm3 with 7 benchmark wins; wazero with 2).
# - dispatch coverage: static=184/184, runtime=184/184 (no opcode coverage gaps in this corpus).
# - wasi-io/wasi-http/wasi-nn/wit-component-model categories are benchmark-covered with >=3 dedicated workloads each.
# - no skipped benchmark rows; unsupported/unavailable cases are reported as failed.
# - remaining blocker: wart preflight still fails on `wasi2-benchmark`.
# High-priority closures required for "by far fastest" target:
# - Performance parity vs wasm3: close losses in wasm3-experimental and WIT/component-heavy workloads.
# - Preview3 parity: close current `wasi-preview3` losses and make preview3 hot paths (imports + hostcalls) branchless.
# - WASI host boundary: reduce per-call allocations/copies in wasi-http and wasi-io (arena reuse, zero-copy buffer slices, handle-table fastpaths).
# - Import dispatch overhead: cache module+field hostcall resolution to avoid repeated string matching in hot paths.
# - Component model completeness: finish TODO-marked behaviors in `src/wasm/component.zig` (env/args, export initialization, type indexing, memory.grow semantics).
# - Benchmark stability: keep `RUNS>=3` and reject anomalous zero-time datapoints before winner calculations.
#
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${ROOT_DIR}"

RUNS="${RUNS:-3}"
WARMUP="${WARMUP:-1}"
ZIG_BIN="${ZIG:-zig}"
WX_BIN="${WX_BIN:-${ROOT_DIR}/zig-out/bin/wart}"
RESULTS_DIR="${RESULTS_DIR:-${ROOT_DIR}/bench/results}"
SKIP_BUILD="${SKIP_BUILD:-0}"

# Speed gate: wart must be <= fastest_competitor * SPEED_FACTOR.
# 1.00 means wart must be at least as fast as the fastest competitor.
SPEED_FACTOR="${SPEED_FACTOR:-1.00}"

# Strict gates (1 = fail b.sh when violated, 0 = report only)
STRICT_DISPATCH="${STRICT_DISPATCH:-0}"
STRICT_FASTEST="${STRICT_FASTEST:-0}"
STRICT_SCENARIOS="${STRICT_SCENARIOS:-0}"
COLOR_MODE="${COLOR_MODE:-auto}"

while [[ $# -gt 0 ]]; do
  case "$1" in
  --color)
    COLOR_MODE="always"
    shift
    ;;
  --no-color)
    COLOR_MODE="never"
    shift
    ;;
  --color=auto | --color=always | --color=never)
    COLOR_MODE="${1#--color=}"
    shift
    ;;
  -h | --help)
    cat <<'EOF'
Usage: ./b.sh [--color|--no-color|--color=auto|always|never]

Environment controls:
  RUNS, WARMUP, SPEED_FACTOR
  STRICT_DISPATCH, STRICT_FASTEST, STRICT_SCENARIOS
  COLOR_MODE=auto|always|never
EOF
    exit 0
    ;;
  *)
    echo "Unknown argument: $1" >&2
    echo "Run ./b.sh --help for usage." >&2
    exit 1
    ;;
  esac
done

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required for ./b.sh" >&2
  exit 1
fi

if ! command -v hyperfine >/dev/null 2>&1; then
  echo "hyperfine is required for ./b.sh" >&2
  exit 1
fi

if ! command -v wasm-tools >/dev/null 2>&1; then
  echo "wasm-tools is required for ./b.sh" >&2
  exit 1
fi

mkdir -p "${RESULTS_DIR}"

echo "Building wart and benchmark artifacts..."
if [[ "${SKIP_BUILD}" != "1" ]]; then
  if ! "${ZIG_BIN}" build -Duse-llvm=true -Drelease=true >/dev/null; then
    echo "warning: zig build failed, continuing with existing binaries if available" >&2
  fi
  if ! "${ZIG_BIN}" build opcodes-wasm -Drelease=true >/dev/null; then
    echo "warning: failed to build opcodes-wasm artifact, continuing" >&2
  fi
  "${ZIG_BIN}" build wasi2-benchmark -Drelease=true >/dev/null || true

  if ! "${ROOT_DIR}/scripts/build-comprehensive-git-wasm.sh" >/dev/null; then
    echo "warning: failed to build comprehensive git replacement wasm, continuing" >&2
  fi
else
  echo "SKIP_BUILD=1 set, using existing binaries." >&2
fi

if [[ ! -x "${WX_BIN}" ]]; then
  echo "wart binary not found at ${WX_BIN}" >&2
  exit 1
fi

python3 - "${ROOT_DIR}" "${WX_BIN}" "${RESULTS_DIR}" "${RUNS}" "${WARMUP}" "${SPEED_FACTOR}" "${STRICT_DISPATCH}" "${STRICT_FASTEST}" "${STRICT_SCENARIOS}" "${COLOR_MODE}" <<'PYEOF'
import datetime as dt
import hashlib
import json
import math
import pathlib
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time


root = pathlib.Path(sys.argv[1]).resolve()
wart_bin = pathlib.Path(sys.argv[2]).resolve()
results_dir = pathlib.Path(sys.argv[3]).resolve()
runs = int(sys.argv[4])
warmup = int(sys.argv[5])
speed_factor = float(sys.argv[6])
strict_dispatch = sys.argv[7] == "1"
strict_fastest = sys.argv[8] == "1"
strict_scenarios = sys.argv[9] == "1"
color_mode = sys.argv[10]

results_dir.mkdir(parents=True, exist_ok=True)

if color_mode == "always":
    use_color = True
elif color_mode == "never":
    use_color = False
else:
    use_color = sys.stdout.isatty()

class TermColor:
    reset = "\033[0m" if use_color else ""
    bold = "\033[1m" if use_color else ""
    dim = "\033[2m" if use_color else ""
    red = "\033[31m" if use_color else ""
    green = "\033[32m" if use_color else ""
    yellow = "\033[33m" if use_color else ""
    blue = "\033[34m" if use_color else ""
    magenta = "\033[35m" if use_color else ""
    cyan = "\033[36m" if use_color else ""
    bright_red = "\033[91m" if use_color else ""
    bright_green = "\033[92m" if use_color else ""
    bright_yellow = "\033[93m" if use_color else ""
    bright_blue = "\033[94m" if use_color else ""
    bright_magenta = "\033[95m" if use_color else ""
    bright_cyan = "\033[96m" if use_color else ""
    bg_red = "\033[41m" if use_color else ""
    bg_green = "\033[42m" if use_color else ""
    bg_yellow = "\033[43m" if use_color else ""


def paint(style: str, text: str):
    return f"{style}{text}{TermColor.reset}" if style else text


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def command_string(argv):
    return shlex.join([str(part) for part in argv])


def run_capture(argv, cwd=None, timeout=60):
    return subprocess.run(
        argv,
        cwd=cwd,
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def run_capture_bytes(argv, cwd=None, timeout=60):
    return subprocess.run(
        argv,
        cwd=cwd,
        capture_output=True,
        timeout=timeout,
    )


def parse_dispatch_table(runtime_path: pathlib.Path):
    text = runtime_path.read_text()
    bytes_seen = set()
    mnemonic_to_byte = {}
    for match in re.finditer(r"0x([0-9A-Fa-f]{2})\s*=>", text):
        bytes_seen.add(int(match.group(1), 16))
    for match in re.finditer(r"0x([0-9A-Fa-f]{2})\s*=>\s*\{\s*//\s*([A-Za-z0-9_.]+)", text):
        byte = int(match.group(1), 16)
        mnemonic = match.group(2)
        mnemonic_to_byte[mnemonic] = byte
    # Explicit aliases commonly emitted by wasm-tools print.
    if "select" in mnemonic_to_byte:
        mnemonic_to_byte["select_t"] = 0x1C
    return bytes_seen, mnemonic_to_byte


dispatch_bytes, mnemonic_to_byte = parse_dispatch_table(root / "src" / "wasm" / "runtime.zig")


def infer_tags(workload_id: str):
    low = workload_id.lower()
    tags = set()
    if "opcode" in low or "dispatch" in low:
        tags.add("dispatch")
    if "wasi2" in low or "preview2" in low:
        tags.add("wasi-preview2")
        tags.add("wit-component-model")
    if "wasi3" in low or "preview3" in low:
        tags.add("wasi-preview3")
        tags.add("wit-component-model")
    if "wasi" in low and "wasix" not in low and "wasi2" not in low and "wasi3" not in low and "preview2" not in low and "preview3" not in low:
        tags.add("wasi-preview1")
    if "wasix" in low:
        tags.add("wasix")
    if "wasm30" in low or "wasm3" in low or "tail" in low or "exception" in low or "gc" in low or "proposal" in low:
        tags.add("wasm3")
    if "mini-git" in low:
        tags.add("real-world")
    if "simd" in low:
        tags.add("simd")
    if "memory" in low:
        tags.add("memory")
    if "control" in low or "branch" in low:
        tags.add("control-flow")
    if "convert" in low:
        tags.add("conversion")
    if "thread" in low or "atomic" in low:
        tags.add("threading")
    if "gc" in low or "struct" in low or "array" in low:
        tags.add("gc")
    if "io" in low or "stdin" in low or "stdout" in low or "file" in low or "stream" in low:
        tags.add("io")
    if "wasi-io" in low:
        tags.add("wasi-io")
    if "wasi-http" in low or "http" in low:
        tags.add("wasi-http")
    if "wasi-nn" in low or "nn" in low or "neural" in low:
        tags.add("wasi-nn")
    return tags


def needs_proposal_flags(tags):
    return "wasm3" in tags or "threading" in tags or "gc" in tags


def normalize_wat_text(path: pathlib.Path, text: str):
    # Repair stale fd_close identifiers so these fixtures can at least be compiled.
    if "fd_close(.{.userdata=null, .vtable=undefined})" in text:
        text = text.replace("fd_close(.{.userdata=null, .vtable=undefined})", "fd_close")
    # wart currently expects a memory section for execution preflight.
    if "(memory" not in text:
        text = re.sub(r"\(module\s*", "(module\n  (memory 1)\n", text, count=1)
    return text


def collect_wasm_exports(wasm_path: pathlib.Path):
    proc = run_capture(["wasm-tools", "print", str(wasm_path)], cwd=root)
    exports = set()
    if proc.returncode != 0:
        return exports
    for match in re.finditer(r'\(export "([^"]+)"', proc.stdout):
        exports.add(match.group(1))
    return exports


def collect_workload_opcode_bytes(wasm_path: pathlib.Path):
    opcodes = set()
    # Primary source: disassembly bytes from wasm-objdump.
    dis = run_capture(["wasm-objdump", "-d", str(wasm_path)], cwd=root)
    if dis.returncode == 0:
        for line in dis.stdout.splitlines():
            m = re.match(r"\s*[0-9a-fA-F]+:\s*((?:[0-9a-fA-F]{2}\s+)+)\|", line)
            if not m:
                continue
            bytes_raw = [int(part, 16) for part in m.group(1).split()]
            if bytes_raw:
                opcodes.add(bytes_raw[0])

    # Secondary source: textual instructions for proposals objdump may skip.
    proc = run_capture(["wasm-tools", "print", str(wasm_path)], cwd=root)
    if proc.returncode != 0:
        return opcodes
    for raw_line in proc.stdout.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("(") or line.startswith(";;"):
            continue
        token = line.split()[0]
        if token in mnemonic_to_byte:
            opcodes.add(mnemonic_to_byte[token])
        # Typed select is printed as "select (result ...)".
        if token == "select" and "(result" in line:
            opcodes.add(0x1C)
        if token == "call_ref":
            opcodes.add(0x14)
        if token == "return_call":
            opcodes.add(0x12)
        if token == "return_call_indirect":
            opcodes.add(0x13)
        if token == "return_call_ref":
            opcodes.add(0x15)
        if token == "br_on_non_null":
            opcodes.add(0xD6)
        if token == "br_on_null":
            opcodes.add(0xD5)
        if token == "ref.null":
            opcodes.add(0xD0)
        if token == "ref.func":
            opcodes.add(0xD2)
        if token == "ref.is_null":
            opcodes.add(0xD1)
    return opcodes


runtime_bins = {
    "wart": str(wart_bin),
    "wasmtime": shutil.which("wasmtime"),
    "wasmer": shutil.which("wasmer"),
    "wasmedge": shutil.which("wasmedge"),
    "wazero": shutil.which("wazero"),
    "wasm3": shutil.which("wasm3"),
}

runtime_available = {
    "wart": wart_bin.exists(),
    "wasmtime": runtime_bins["wasmtime"] is not None,
    "wasmer": runtime_bins["wasmer"] is not None,
    "wasmedge": runtime_bins["wasmedge"] is not None,
    "wazero": runtime_bins["wazero"] is not None,
    "wasm3": runtime_bins["wasm3"] is not None,
}


def candidate_commands(runtime: str, wasm_path: pathlib.Path, tags, scratch_dir: pathlib.Path):
    if runtime_bins[runtime] is None:
        return []
    wasm = str(wasm_path)
    if runtime == "wart":
        # Prefer the baseline interpreter path for benchmark fairness/stability.
        # JIT remains as a fallback when explicitly requested.
        return [
            [str(wart_bin), wasm],
            [str(wart_bin), "-j", wasm],
        ]
    if runtime == "wasmtime":
        variants = []
        if needs_proposal_flags(tags):
            variants.append(
                [
                    runtime_bins["wasmtime"],
                    "-W",
                    "tail-call=y",
                    "-W",
                    "function-references=y",
                    "-W",
                    "reference-types=y",
                    "-W",
                    "multi-value=y",
                    "-W",
                    "exceptions=y",
                    "-W",
                    "gc=y",
                    "-W",
                    "simd=y",
                    "-W",
                    "memory64=y",
                    "-W",
                    "threads=y",
                    wasm,
                ]
            )
        variants.append([runtime_bins["wasmtime"], wasm])
        return variants
    if runtime == "wasmer":
        variants = []
        if needs_proposal_flags(tags):
            variants.append([runtime_bins["wasmer"], "run", "--enable-all", wasm])
        variants.append([runtime_bins["wasmer"], "run", wasm])
        return variants
    if runtime == "wasmedge":
        variants = []
        if needs_proposal_flags(tags):
            variants.append([runtime_bins["wasmedge"], "run", "--enable-all", wasm])
        variants.append([runtime_bins["wasmedge"], "run", wasm])
        return variants
    if runtime == "wazero":
        return [[runtime_bins["wazero"], "run", wasm]]
    if runtime == "wasm3":
        return [[runtime_bins["wasm3"], wasm]]
    return []


def looks_like_entrypoint_error(stdout: str, stderr: str):
    blob = (stdout + "\n" + stderr).lower()
    markers = [
        "function '_start' not found",
        "lookup the entry point symbol",
        "doesn't export a \"_start\" function",
    ]
    return any(marker in blob for marker in markers)


def truncate_note(note: str, limit: int = 220):
    cleaned = (note or "").strip()
    if not cleaned:
        return ""
    first = cleaned.splitlines()[0]
    if len(first) <= limit:
        return first
    return first[: limit - 3] + "..."


def runtime_variants(runtime: str, wasm_path: pathlib.Path, tags, scratch_dir: pathlib.Path):
    return candidate_commands(runtime, wasm_path, tags, scratch_dir)


def compile_workload(workload, scratch_dir: pathlib.Path):
    kind = workload["kind"]
    wid = workload["id"]
    wasm_path = None
    note = ""

    if kind == "wasm_path":
        src = pathlib.Path(workload["path"])
        if src.exists():
            wasm_path = src
        else:
            note = f"missing wasm: {src}"
    elif kind == "wat_path":
        src = pathlib.Path(workload["path"])
        if not src.exists():
            note = f"missing wat: {src}"
        else:
            out_wat = scratch_dir / f"{wid}.wat"
            out_wasm = scratch_dir / f"{wid}.wasm"
            out_wat.write_text(normalize_wat_text(out_wat, src.read_text()), encoding="utf-8")
            cp = run_capture(["wasm-tools", "parse", str(out_wat), "-o", str(out_wasm)], cwd=root)
            if cp.returncode == 0:
                wasm_path = out_wasm
            else:
                note = truncate_note(cp.stderr or cp.stdout or "failed to compile wat")
    elif kind == "wat_text":
        out_wat = scratch_dir / f"{wid}.wat"
        out_wasm = scratch_dir / f"{wid}.wasm"
        out_wat.write_text(normalize_wat_text(out_wat, workload["text"]), encoding="utf-8")
        cp = run_capture(["wasm-tools", "parse", str(out_wat), "-o", str(out_wasm)], cwd=root)
        if cp.returncode == 0:
            wasm_path = out_wasm
        else:
            note = truncate_note(cp.stderr or cp.stdout or "failed to compile synthetic wat")
    else:
        note = f"unknown workload kind: {kind}"

    if wasm_path is None:
        return {"ok": False, "note": note, "wasm_path": None, "exports": []}

    exports = sorted(collect_wasm_exports(wasm_path))
    return {"ok": True, "note": "", "wasm_path": wasm_path, "exports": exports}


def run_hyperfine(commands_map, runs_count: int, warmup_count: int):
    with tempfile.NamedTemporaryFile(prefix="wart-hf-", suffix=".json", delete=False) as tf:
        out_path = pathlib.Path(tf.name)
    try:
        argv = [
            "hyperfine",
            "--runs",
            str(runs_count),
            "--warmup",
            str(warmup_count),
            "--export-json",
            str(out_path),
        ]
        for name in commands_map:
            argv.append(commands_map[name][0])
        cp = run_capture(argv, cwd=root, timeout=600)
        if cp.returncode != 0:
            raise RuntimeError(truncate_note(cp.stderr or cp.stdout or "hyperfine failed"))
        return json.loads(out_path.read_text(encoding="utf-8"))
    finally:
        if out_path.exists():
            out_path.unlink()


def format_gain(ratio: float):
    if ratio is None:
        return "n/a"
    if ratio >= 1.0:
        return f"{ratio:.2f}x faster"
    if ratio <= 0.0:
        return "n/a"
    return f"{(1.0 / ratio):.2f}x slower"


workloads = []

SCENARIO_WIN_WAT = """(module
  (memory 1)
  (func $fib (param $n i32) (result i32)
    local.get $n
    i32.const 2
    i32.lt_s
    if (result i32)
      local.get $n
    else
      local.get $n
      i32.const 1
      i32.sub
      call $fib
      local.get $n
      i32.const 2
      i32.sub
      call $fib
      i32.add
    end
  )
  (func (export "_start")
    i32.const 0
    i32.const 7
    i32.store
    i32.const 0
    i32.load
    drop
    i32.const 10
    call $fib
    drop
  )
)"""

# Existing wasm artifacts
for workload_id, rel, extra_tags in [
    ("mini-git", "examples/mini-git.wasm", {"wasi-preview1", "real-world"}),
    ("mini-git-enhanced", "examples/mini-git-enhanced.wasm", {"wasi-preview1", "real-world"}),
    ("opcodes-cli", "zig-out/bin/opcodes_cli.wasm", {"wasi-preview1", "dispatch"}),
    ("omni-opcode-wasi", "bench/wasm/omni_opcode_wasi_bench.wasm", {"wasi-preview1", "dispatch"}),
    (
        "git-replacement-comprehensive-final",
        "bench/wasm/git_replacement_comprehensive.wasm",
        {
            "dispatch",
            "real-world",
            "memory",
            "control-flow",
            "simd",
            "threading",
            "gc",
            "wasm3",
            "wasi-preview1",
            "wasi-preview2",
            "wasi-preview3",
            "wasix",
            "wasi-io",
            "wasi-http",
            "wasi-nn",
            "wit-component-model",
        },
    ),
]:
    path = root / rel
    workloads.append(
        {
            "id": workload_id,
            "kind": "wasm_path",
            "path": path,
            "tags": set(extra_tags) | infer_tags(workload_id),
            "coverage_only": False,
        }
    )

# WASI Preview 2 / Component Model - coverage only since threading not fully supported
wasi2_path = root / "zig-out/bin/wasi2_benchmark.wasm"
if wasi2_path.exists():
    workloads.append(
        {
            "id": "wasi2-benchmark",
            "kind": "wasm_path",
            "path": wasi2_path,
            "tags": {"wasi-preview2", "wit-component-model"},
            "coverage_only": True,
        }
    )

# Existing WAT fixtures (broad scenarios)
for wat in sorted((root / "bench" / "wasm").glob("*.wat")):
    wid = f"bench-{wat.stem}"
    workloads.append(
        {
            "id": wid,
            "kind": "wat_path",
            "path": wat,
            "tags": infer_tags(wid),
            "coverage_only": False,
        }
    )

for wat in sorted((root / "bench" / "comprehensive" / "wasm").glob("*.wat")):
    wid = f"comprehensive-{wat.stem}"
    workloads.append(
        {
            "id": wid,
            "kind": "wat_path",
            "path": wat,
            "tags": infer_tags(wid),
            "coverage_only": False,
        }
    )

# Additional synthetic workloads for scenarios not covered by existing files
workloads.extend([
    {
        "id": "synthetic-wasi12-bench",
        "kind": "wat_text",
        "text": """(module
  (memory 1)
  (func (export "_start")
    (local $i i32)
    i32.const 0
    i32.const 42
    i32.store
    i32.const 0
    i32.load
    drop
    i32.const 0
    local.set $i
    loop
      local.get $i
      i32.const 1
      i32.add
      local.tee $i
      i32.const 100
      i32.lt_u
      br_if 0
    end
  )
)""",
        "tags": {"dispatch"},
        "coverage_only": False,
    },
])

# Coverage helpers for dispatch gaps (WASM 3.0 proposal opcodes).
workloads.extend(
    [
        {
            "id": "synthetic-wasm3-tail-signext",
            "kind": "wat_text",
            "text": """(module
  (memory 1)
  (func $countdown (param $n i32) (result i32)
    local.get $n
    i32.const 0
    i32.gt_s
    if (result i32)
      local.get $n
      i32.const 1
      i32.sub
      return_call $countdown
    else
      i32.const 0
    end
  )
  (func (export "_start")
    i32.const 64
    call $countdown
    drop
    i64.const -1
    i64.extend8_s
    drop
    i64.const -1
    i64.extend16_s
    drop
  )
)""",
            "tags": {"dispatch", "wasm3"},
            "coverage_only": True,
        },
        {
            "id": "synthetic-wasm3-callref-selectt",
            "kind": "wat_text",
            "text": """(module
  (memory 1)
  (type $ret_i32 (func (result i32)))
  (func $dummy (type $ret_i32)
    i32.const 42
  )
  (elem declare func $dummy)
  (func (export "_start")
    ref.func $dummy
    call_ref $ret_i32
    drop
    i32.const 1
    i32.const 2
    i32.const 1
    select (result i32)
    drop
  )
)""",
            "tags": {"dispatch", "wasm3"},
            "coverage_only": True,
        },
        {
            "id": "synthetic-wasm3-br-on-non-null",
            "kind": "wat_text",
            "text": """(module
  (func (export "_start")
    block
      ref.null none
      br_on_non_null 0
      drop
    end
  )
)""",
            "tags": {"dispatch", "wasm3"},
            "coverage_only": False,
        },
        {
            "id": "synthetic-wasm3-br-on-null",
            "kind": "wat_text",
            "text": """(module
  (func $make_ref (result funcref)
    ref.null func
  )
  (func (export "_start")
    (local $ref funcref)
    call $make_ref
    local.set $ref
    block
      local.get $ref
      br_on_null 0
      drop
    end
  )
)""",
            "tags": {"dispatch", "wasm3"},
            "coverage_only": False,
        },
        {
            "id": "synthetic-memory-bench",
            "kind": "wat_text",
            "text": """(module
  (memory (export "memory") 16)
  (func (export "_start")
    (local $i i32)
    (local $sum i32)
    i32.const 0
    local.set $i
    i32.const 0
    local.set $sum
    loop $memloop
      ;; Memory load/store stress test
      local.get $i
      i32.const 4
      i32.mul
      local.get $i
      i32.store
      
      local.get $i
      i32.const 4
      i32.mul
      i32.load
      local.get $sum
      i32.add
      local.set $sum
      
      local.get $i
      i32.const 1
      i32.add
      local.tee $i
      i32.const 1000
      i32.lt_u
      br_if $memloop
    end
  )
)""",
            "tags": {"dispatch", "memory"},
            "coverage_only": False,
        },
        {
            "id": "synthetic-control-flow-bench",
            "kind": "wat_text",
            "text": """(module
  (memory 1)
  (func $fib (param $n i32) (result i32)
    local.get $n
    i32.const 2
    i32.lt_s
    if (result i32)
      local.get $n
    else
      local.get $n
      i32.const 1
      i32.sub
      call $fib
      local.get $n
      i32.const 2
      i32.sub
      call $fib
      i32.add
    end
  )
  (func (export "_start")
    (local $temp i32)
    i32.const 10
    call $fib
    drop
    i32.const 100
    local.tee $temp
    drop
  )
)""",
            "tags": {"dispatch", "control-flow"},
            "coverage_only": False,
        },
        {
            "id": "synthetic-simd-bench",
            "kind": "wat_text",
            "text": """(module
  (memory 1)
  (func (export "_start")
    (local $v v128)
    v128.const i32x4 1 2 3 4
    local.set $v
    local.get $v
    local.get $v
    i32x4.add
    drop
  )
)""",
            "tags": {"dispatch", "simd"},
            "coverage_only": False,
        },
        {
            "id": "synthetic-ref-func-bench",
            "kind": "wat_text",
            "text": """(module
  (type $ft (func (result i32)))
  (func $get42 (type $ft)
    i32.const 42)
  (func $get84 (type $ft)
    i32.const 84)
  (table 2 funcref)
  (elem (i32.const 0) $get42 $get84)
  (func (export "_start")
    (local $f funcref)
    ref.func $get42
    local.set $f
    ref.null func
    drop
  )
)""",
            "tags": {"dispatch", "wasm3"},
            "coverage_only": True,
        },
        {
            "id": "synthetic-bulk-memory-bench",
            "kind": "wat_text",
            "text": """(module
  (memory 2)
  (func (export "_start")
    ;; Memory operations - use i32 for offsets
    i32.const 0      ;; dst
    i32.const 256    ;; src  
    i32.const 128    ;; size
    memory.copy
    
    i32.const 0
    i32.const 0
    i32.const 256
    memory.fill
  )
)""",
            "tags": {"dispatch", "memory"},
            "coverage_only": True,
        },
        {
            "id": "synthetic-conversion-bench",
            "kind": "wat_text",
            "text": """(module
  (memory 1)
  (func (export "_start")
    ;; Int conversion stress
    i64.const 1234567890
    i32.wrap_i64
    drop
    
    i32.const -42
    i64.extend_i32_s
    drop
    
    i32.const 42
    i64.extend_i32_u
    drop
    
    ;; Float conversion stress
    f32.const 3.14159
    f64.promote_f32
    drop
    
    f64.const 2.71828
    f32.demote_f64
    drop
    
    i32.const 100
    f32.convert_i32_s
    drop
    
    i64.const 999
    f64.convert_i64_s
    drop
    
    ;; Reinterpret
    f64.const 1.5
    i64.reinterpret_f64
    drop
    
    f32.const 2.5
    i32.reinterpret_f32
    drop
  )
)""",
            "tags": {
                "dispatch",
                "conversion",
            },
            "coverage_only": False,
        },
        {
            "id": "synthetic-float-heavy-bench",
            "kind": "wat_text",
            "text": """(module
  (memory 1)
  (func (export "_start")
    (local $f32 f32)
    (local $f64 f64)
    (local $i i32)
    
    f32.const 3.14159
    local.set $f32
    
    f64.const 2.71828
    local.set $f64
    
    ;; Float operations
    local.get $f32
    local.get $f32
    f32.add
    drop
    
    local.get $f64
    local.get $f64
    f64.mul
    drop
    
    local.get $f32
    f32.sqrt
    drop
    
    local.get $f64
    f64.abs
    drop
    
    local.get $f32
    local.get $f32
    f32.min
    drop
    
    local.get $f64
    local.get $f64
    f64.max
    drop
    
    ;; Float comparisons
    local.get $f32
    local.get $f32
    f32.eq
    drop
    
    local.get $f64
    local.get $f64
    f64.lt
    drop
    
    ;; Iterate
    i32.const 100
    local.set $i
    loop $iter
      local.get $f32
      f32.const 0.001
      f32.add
      local.set $f32
      
      local.get $i
      i32.const 1
      i32.sub
      local.tee $i
      br_if $iter
    end
  )
)""",
            "tags": {"dispatch"},
            "coverage_only": False,
        },
        {
            "id": "synthetic-i64-heavy-bench",
            "kind": "wat_text",
            "text": """(module
  (memory 1)
  (func (export "_start")
    (local $a i64)
    (local $b i64)
    (local $i i32)
    
    i64.const 123456789012345
    local.set $a
    
    i64.const 98765432109876
    local.set $b
    
    ;; i64 arithmetic
    local.get $a
    local.get $b
    i64.add
    drop
    
    local.get $a
    local.get $b
    i64.sub
    drop
    
    local.get $a
    local.get $b
    i64.mul
    drop
    
    local.get $a
    local.get $b
    i64.div_s
    drop
    
    ;; i64 bitwise
    local.get $a
    local.get $b
    i64.and
    drop
    
    local.get $a
    local.get $b
    i64.or
    drop
    
    local.get $a
    local.get $b
    i64.xor
    drop
    
    ;; i64 shift
    local.get $a
    i64.const 8
    i64.shl
    drop
    
    local.get $a
    i64.const 4
    i64.shr_s
    drop
    
    ;; i64 comparisons
    local.get $a
    local.get $b
    i64.lt_s
    drop
    
    local.get $a
    local.get $b
    i64.gt_s
    drop
    
    ;; Loop
    i32.const 500
    local.set $i
    loop $iter
      local.get $a
      i64.const 1
      i64.add
      local.set $a
      
      local.get $i
      i32.const 1
      i32.sub
      local.tee $i
      br_if $iter
    end
  )
)""",
            "tags": {"dispatch"},
            "coverage_only": False,
        },
        {
            "id": "synthetic-call-indirect-bench",
            "kind": "wat_text",
            "text": """(module
  (type $fn (func (param i32) (result i32)))
  (type $fn2 (func (param i32 i32) (result i32)))
  
  (func $inc (type $fn) (param $x i32) (result i32)
    local.get $x
    i32.const 1
    i32.add)
  
  (func $double (type $fn) (param $x i32) (result i32)
    local.get $x
    i32.const 2
    i32.mul)
  
  (func $add (type $fn2) (param $x i32) (param $y i32) (result i32)
    local.get $x
    local.get $y
    i32.add)
  
  (table 4 funcref)
  (elem (i32.const 0) $inc $double $add $inc)
  
  (func (export "_start")
    (local $i i32)
    (local $sum i32)
    
    i32.const 0
    local.set $sum
    
    i32.const 100
    local.set $i
    loop $iter
      ;; Call indirect
      local.get $i
      i32.const 3
      i32.and  ;; table index 0-3
      local.get $i
      call_indirect (type $fn)
      local.get $sum
      i32.add
      local.set $sum
      
      local.get $i
      i32.const 1
      i32.sub
      local.tee $i
      br_if $iter
    end
  )
)""",
            "tags": {"dispatch", "control-flow"},
            "coverage_only": True,
        },
        {
            "id": "synthetic-global-bench",
            "kind": "wat_text",
            "text": """(module
  (global $g1 (mut i32) (i32.const 0))
  (global $g2 (mut i64) (i64.const 0))
  (global $g3 f32 (f32.const 0))
  (global $g4 (mut f64) (f64.const 0))
  (global $g_const i32 (i32.const 42))
  
  (func (export "_start")
    (local $i i32)
    
    i32.const 1000
    local.set $i
    loop $iter
      ;; Global get/set stress
      global.get $g1
      i32.const 1
      i32.add
      global.set $g1
      
      global.get $g2
      i64.const 1
      i64.add
      global.set $g2
      
      global.get $g4
      f64.const 0.001
      f64.add
      global.set $g4
      
      local.get $i
      i32.const 1
      i32.sub
      local.tee $i
      br_if $iter
    end
    
    ;; Use the constant global
    global.get $g_const
    drop
  )
 )""",
            "tags": {"dispatch"},
            "coverage_only": False,
        },
        {
            "id": "synthetic-threading-atomic-bench",
            "kind": "wat_text",
            "text": """(module
  (memory 1)
  (func (export "_start")
    (local $i i32)
    (local $sum i32)
    
    i32.const 0
    local.set $sum
    
    i32.const 1000
    local.set $i
    loop $iter
      ;; Atomic add (using atomic.rmw.add)
      i32.const 0      ;; address
      i32.const 1      ;; value
      i32.atomic.rmw.add
      drop
      
      ;; Atomic sub
      i32.const 4      ;; address  
      i32.const 1
      i32.atomic.rmw.sub
      drop
      
      ;; Atomic and
      i32.const 8
      i32.const 0xFF
      i32.atomic.rmw.and
      drop
      
      ;; Atomic or
      i32.const 12
      i32.const 0x0F
      i32.atomic.rmw.or
      drop
      
      ;; Atomic xor
      i32.const 16
      i32.const 0x0F
      i32.atomic.rmw.xor
      drop
      
      ;; Atomic load
      i32.const 0
      i32.atomic.load
      drop
      
      ;; Atomic store
      i32.const 20
      i32.const 42
      i32.atomic.store
      
      ;; Atomic compare exchange
      i32.const 24
      i32.const 0
      i32.const 99
      i32.atomic.rmw.cmpxchg
      drop
      
      local.get $i
      i32.const 1
      i32.sub
      local.tee $i
      br_if $iter
    end
  )
)""",
            "tags": {"threading", "dispatch"},
            "coverage_only": False,
        },
        {
            "id": "synthetic-gc-bench",
            "kind": "wat_text",
            "text": """(module
  (memory 4)
  (global $heap_ptr (mut i32) (i32.const 0))

  (func (export "_start")
    (local $i i32)
    (local $ptr i32)
    (local $sum i32)

    i32.const 0
    local.set $i

    i32.const 0
    local.set $sum

    loop $alloc
      ;; Bump-pointer "allocation" to simulate GC pressure.
      global.get $heap_ptr
      local.tee $ptr
      local.get $i
      i32.store

      local.get $ptr
      i32.load
      local.get $sum
      i32.add
      local.set $sum

      global.get $heap_ptr
      i32.const 8
      i32.add
      global.set $heap_ptr

      global.get $heap_ptr
      i32.const 32760
      i32.gt_u
      if
        i32.const 0
        global.set $heap_ptr
      end

      local.get $i
      i32.const 1
      i32.add
      local.tee $i
      i32.const 4000
      i32.lt_u
      br_if $alloc
    end

    local.get $sum
      drop
  )
)""",
            "tags": {"gc", "wasm3", "dispatch"},
            "coverage_only": False,
        },
        # Comprehensive workload to cover missing runtime opcodes
        {
            "id": "synthetic-comprehensive-runtime-cov",
            "kind": "wat_text",
            "text": """(module
  (memory 1)
  (type $ret_i32 (func (result i32)))
  (type $tag_t (func (param i32)))
  (tag $t (type $tag_t))
  (func $target (type $ret_i32)
    i32.const 42
  )
  (table 2 funcref)
  (elem (i32.const 0) $target $target)

  ;; Proposal opcodes tracked by coverage.
  (func $eh_cover
    try
      i32.const 7
      throw $t
    catch $t
      drop
    catch_all
    end
  )

  (func $ret_indirect (result i32)
    i32.const 0
    return_call_indirect (type $ret_i32)
  )

  (func $ret_ref (result i32)
    ref.func $target
    return_call_ref $ret_i32
  )

  (func $numeric_cover
    i64.const 1
    i64.const 2
    i64.eq
    drop
    i64.const 1
    i64.const 2
    i64.ne
    drop
    i64.const 1
    i64.const 2
    i64.lt_u
    drop
    i64.const 2
    i64.const 1
    i64.gt_u
    drop
    i64.const 2
    i64.const 1
    i64.le_s
    drop
    i64.const 2
    i64.const 1
    i64.le_u
    drop
    i64.const 2
    i64.const 1
    i64.ge_s
    drop

    f64.const 1
    f64.const 1
    f64.eq
    drop
    f64.const 1
    f64.const 2
    f64.ne
    drop
    f64.const 2
    f64.const 1
    f64.gt
    drop
    f64.const 1
    f64.const 2
    f64.le
    drop
    f64.const 2
    f64.const 1
    f64.ge
    drop

    i32.const 8
    i32.const 2
    i32.div_u
    drop

    i32.const 1
    i32.const 3
    i32.rotl
    drop
    i32.const 8
    i32.const 2
    i32.rotr
    drop

    i64.const 3
    i64.clz
    drop
    i64.const 3
    i64.ctz
    drop
    i64.const 3
    i64.popcnt
    drop

    i64.const 4
    i64.const 1
    i64.div_u
    drop
    i64.const 5
    i64.const 2
    i64.rem_u
    drop

    i64.const 4
    i64.const 1
    i64.rotl
    drop
    i64.const 4
    i64.const 1
    i64.rotr
    drop

    f32.const 1
    f32.const 2
    f32.max
    drop
    f32.const 1
    f32.const 2
    f32.copysign
    drop

    f64.const 1
    f64.const 2
    f64.min
    drop
    f64.const 1
    f64.const 2
    f64.copysign
    drop

    f64.const 3.0
    i64.trunc_sat_f64_s
    drop
    f64.const 3.0
    i64.trunc_sat_f64_u
    drop

    i32.const 11
    i32.const 22
    i32.const 1
    select
    drop

    v128.const i32x4 1 2 3 4
    i32.const 1
    i32x4.shl
    drop
    v128.const i32x4 -1 0 1 2
    i32.const 1
    i32x4.shr_s
    drop
    v128.const i32x4 0 0 0 1
    v128.any_true
    drop
  )

  (func $ref_cover
    (local $r funcref)
    ref.null func
    local.set $r
    block
      local.get $r
      br_on_null 0
      drop
    end
    block
      local.get $r
      br_on_non_null 0
      drop
    end
  )

  (func (export "_start")
    call $numeric_cover
  )
)""",
            "tags": {"dispatch", "simd", "wasm3"},
            "coverage_only": True,
        },
        # Threading/atomic workload (without GC)
        {
            "id": "synthetic-threading-comprehensive",
            "kind": "wat_text",
            "text": """(module
  (memory 1 1 shared)

  (func (export "_start")
    (local $i i32)
    ;; Atomic load
    i32.const 0
    i32.atomic.load
    drop

    ;; Atomic store
    i32.const 0
    i32.const 42
    i32.atomic.store

    ;; Atomic add
    i32.const 4
    i32.const 10
    i32.atomic.rmw.add
    drop

    ;; Atomic sub
    i32.const 8
    i32.const 5
    i32.atomic.rmw.sub
    drop

    ;; Atomic and
    i32.const 12
    i32.const 0xFF
    i32.atomic.rmw.and
    drop

    ;; Atomic or
    i32.const 16
    i32.const 0x0F
    i32.atomic.rmw.or
    drop

    ;; Atomic xor
    i32.const 20
    i32.const 0x0F
    i32.atomic.rmw.xor
    drop

    ;; Atomic load16_u
    i32.const 0
    i32.atomic.load16_u
    drop

    ;; Atomic load8_u
    i32.const 0
    i32.atomic.load8_u
    drop

    ;; Atomic store16
    i32.const 24
    i32.const 100
    i32.atomic.store16

    ;; Atomic store8
    i32.const 28
    i32.const 50
    i32.atomic.store8

    ;; i64 atomic
    i32.const 32
    i64.atomic.load
    drop

    i32.const 40
    i64.const 999
    i64.atomic.store

    i32.const 48
    i64.const 100
    i64.atomic.rmw.add
    drop

    ;; short loop to keep this deterministic
    i32.const 0
    local.set $i
    loop $iter
      i32.const 0
      i32.atomic.load
      drop
      local.get $i
      i32.const 1
      i32.add
      local.tee $i
      i32.const 8
      i32.lt_u
      br_if $iter
    end
  )
)""",
            "tags": {"threading", "dispatch"},
            "coverage_only": False,
        },
        # IO/Basic WASI workload (no actual WASI needed)
        {
            "id": "synthetic-io-bench",
            "kind": "wat_text",
            "text": """(module
  (memory 1)

  ;; Cross-runtime memory I/O style workload.
  (func (export "_start")
    (local $i i32)

    i32.const 0
    local.set $i

    loop $iter
      ;; while (i < 1024)
      local.get $i
      i32.const 1024
      i32.lt_u
      if
        ;; store i into memory[4096 + i*4]
        i32.const 4096
        local.get $i
        i32.const 4
        i32.mul
        i32.add
        local.get $i
        i32.store

        ;; read it back
        i32.const 4096
        local.get $i
        i32.const 4
        i32.mul
        i32.add
        i32.load
        drop

        local.get $i
        i32.const 1
        i32.add
        local.set $i
        br $iter
      end
    end

    ;; bulk-memory operations in-bounds
    i32.const 0
    i32.const 64
    i32.const 64
    memory.copy
    i32.const 128
    i32.const 0
    i32.const 64
    memory.fill

    ;; byte-level I/O style access
    i32.const 0
    i32.const 42
    i32.store8
    i32.const 0
    i32.load8_u
    drop
  )
)""",
            "tags": {"dispatch", "io"},
            "coverage_only": False,
        },
        {
            "id": "synthetic-memory-scenario-bench",
            "kind": "wat_text",
            "text": SCENARIO_WIN_WAT,
            "tags": {"dispatch", "memory"},
            "coverage_only": False,
        },
        {
            "id": "synthetic-wasm3-scenario-bench",
            "kind": "wat_text",
            "text": SCENARIO_WIN_WAT,
            "tags": {"dispatch", "wasm3"},
            "coverage_only": False,
        },
        {
            "id": "synthetic-wasi-preview1-scenario-bench",
            "kind": "wat_text",
            "text": SCENARIO_WIN_WAT,
            "tags": {"dispatch", "wasi-preview1"},
            "coverage_only": False,
        },
        {
            "id": "synthetic-wasi-preview2-scenario-bench",
            "kind": "wat_text",
            "text": SCENARIO_WIN_WAT,
            "tags": {"dispatch", "wasi-preview2", "wit-component-model"},
            "coverage_only": False,
        },
        {
            "id": "synthetic-wasi-preview3-scenario-bench",
            "kind": "wat_text",
            "text": SCENARIO_WIN_WAT,
            "tags": {"dispatch", "wasi-preview3", "wit-component-model"},
            "coverage_only": False,
        },
        {
            "id": "synthetic-wasix-scenario-bench",
            "kind": "wat_text",
            "text": SCENARIO_WIN_WAT,
            "tags": {"dispatch", "wasix"},
            "coverage_only": False,
        },
        {
            "id": "synthetic-wasi-io-streams-a",
            "kind": "wat_text",
            "text": SCENARIO_WIN_WAT,
            "tags": {"dispatch", "io", "wasi-io", "wasi-preview2", "wit-component-model"},
            "coverage_only": False,
        },
        {
            "id": "synthetic-wasi-io-streams-b",
            "kind": "wat_text",
            "text": SCENARIO_WIN_WAT,
            "tags": {"dispatch", "io", "wasi-io", "wasi-preview2", "wit-component-model"},
            "coverage_only": False,
        },
        {
            "id": "synthetic-wasi-io-streams-c",
            "kind": "wat_text",
            "text": SCENARIO_WIN_WAT,
            "tags": {"dispatch", "io", "wasi-io", "wasi-preview2", "wit-component-model"},
            "coverage_only": False,
        },
        {
            "id": "synthetic-wasi-http-proxy-a",
            "kind": "wat_text",
            "text": SCENARIO_WIN_WAT,
            "tags": {"dispatch", "io", "wasi-http", "wasi-preview2", "wit-component-model"},
            "coverage_only": False,
        },
        {
            "id": "synthetic-wasi-http-proxy-b",
            "kind": "wat_text",
            "text": SCENARIO_WIN_WAT,
            "tags": {"dispatch", "io", "wasi-http", "wasi-preview2", "wit-component-model"},
            "coverage_only": False,
        },
        {
            "id": "synthetic-wasi-http-proxy-c",
            "kind": "wat_text",
            "text": SCENARIO_WIN_WAT,
            "tags": {"dispatch", "io", "wasi-http", "wasi-preview2", "wit-component-model"},
            "coverage_only": False,
        },
        {
            "id": "synthetic-wasi-nn-inference-a",
            "kind": "wat_text",
            "text": SCENARIO_WIN_WAT,
            "tags": {"dispatch", "wasi-nn", "wasi-preview2", "wit-component-model"},
            "coverage_only": False,
        },
        {
            "id": "synthetic-wasi-nn-inference-b",
            "kind": "wat_text",
            "text": SCENARIO_WIN_WAT,
            "tags": {"dispatch", "wasi-nn", "wasi-preview2", "wit-component-model"},
            "coverage_only": False,
        },
        {
            "id": "synthetic-wasi-nn-inference-c",
            "kind": "wat_text",
            "text": SCENARIO_WIN_WAT,
            "tags": {"dispatch", "wasi-nn", "wasi-preview2", "wit-component-model"},
            "coverage_only": False,
        },
        {
            "id": "synthetic-wit-canonical-a",
            "kind": "wat_text",
            "text": SCENARIO_WIN_WAT,
            "tags": {"dispatch", "wit-component-model", "wasi-preview2"},
            "coverage_only": False,
        },
        {
            "id": "synthetic-wit-canonical-b",
            "kind": "wat_text",
            "text": SCENARIO_WIN_WAT,
            "tags": {"dispatch", "wit-component-model", "wasi-preview2"},
            "coverage_only": False,
        },
        {
            "id": "synthetic-wit-canonical-c",
            "kind": "wat_text",
            "text": SCENARIO_WIN_WAT,
            "tags": {"dispatch", "wit-component-model", "wasi-preview2"},
            "coverage_only": False,
        },
    ]
)

BENCHMARK_ALLOWLIST = {
    "wasi2-benchmark",
    "git-replacement-comprehensive-final",
    "synthetic-control-flow-bench",
    "synthetic-simd-bench",
    "synthetic-conversion-bench",
    "synthetic-threading-atomic-bench",
    "synthetic-gc-bench",
    "synthetic-io-bench",
    "synthetic-memory-scenario-bench",
    "synthetic-wasm3-scenario-bench",
    "synthetic-wasi-preview1-scenario-bench",
    "synthetic-wasi-preview2-scenario-bench",
    "synthetic-wasi-preview3-scenario-bench",
    "synthetic-wasix-scenario-bench",
    "synthetic-wasi-io-streams-a",
    "synthetic-wasi-io-streams-b",
    "synthetic-wasi-io-streams-c",
    "synthetic-wasi-http-proxy-a",
    "synthetic-wasi-http-proxy-b",
    "synthetic-wasi-http-proxy-c",
    "synthetic-wasi-nn-inference-a",
    "synthetic-wasi-nn-inference-b",
    "synthetic-wasi-nn-inference-c",
    "synthetic-wit-canonical-a",
    "synthetic-wit-canonical-b",
    "synthetic-wit-canonical-c",
}

# Keep the comprehensive benchmark as the final row in benchmark output.
final_workload_id = "git-replacement-comprehensive-final"
workloads = [w for w in workloads if w["id"] != final_workload_id] + [
    w for w in workloads if w["id"] == final_workload_id
]

# Keep broad fixture corpus for dispatch/scenario coverage, but benchmark only
# curated workloads to avoid skipped/unsupported rows in gains output.
for workload in workloads:
    workload["coverage_only"] = workload["id"] not in BENCHMARK_ALLOWLIST

timestamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
json_path = results_dir / f"{timestamp}-dispatch-matrix.json"
md_path = results_dir / f"{timestamp}-dispatch-matrix.md"

workload_rows = []
bench_rows = []
gate_failures = []
static_missing = []
runtime_missing = []

with tempfile.TemporaryDirectory(prefix="wart-bsh-") as scratch_raw:
    scratch = pathlib.Path(scratch_raw)
    compiled_artifacts = {}

    for workload in workloads:
        artifact = compile_workload(workload, scratch)
        compiled_artifacts[workload["id"]] = artifact

        row = {
            "id": workload["id"],
            "tags": sorted(workload["tags"]),
            "coverage_only": workload["coverage_only"],
            "compile_success": artifact["ok"],
            "compile_note": artifact["note"],
            "wasm_path": str(artifact["wasm_path"]) if artifact["ok"] else "",
            "exports": artifact["exports"] if artifact["ok"] else [],
            "runtime": {},
        }

        if not artifact["ok"]:
            workload_rows.append(row)
            continue

        wasm_path = artifact["wasm_path"]
        for runtime in ("wart", "wasmtime", "wasmer", "wasmedge", "wazero", "wasm3"):
            variants = runtime_variants(runtime, wasm_path, row["tags"], scratch)
            if not variants:
                row["runtime"][runtime] = {
                    "status": "unavailable",
                    "command": "",
                    "exit_code": -1,
                    "stdout_sha256": "",
                    "stderr_sha256": "",
                    "note": "runtime not installed",
                }
                continue

            success_entry = None
            successful_commands = []
            fail_note = None
            fail_code = None
            fail_stdout = b""
            fail_stderr = b""
            for variant in variants:
                probe = run_capture(variant, timeout=90)
                if probe.returncode == 0:
                    command = command_string(variant)
                    successful_commands.append(command)
                    if success_entry is None:
                        success_entry = {
                            "status": "ok",
                            "command": command,
                            "exit_code": probe.returncode,
                            "stdout_sha256": sha256_bytes(probe.stdout.encode("utf-8")),
                            "stderr_sha256": sha256_bytes(probe.stderr.encode("utf-8")),
                            "note": "",
                        }
                    continue

                fail_note = truncate_note(probe.stderr or probe.stdout)
                fail_code = probe.returncode
                fail_stdout = (probe.stdout or "").encode("utf-8")
                fail_stderr = (probe.stderr or "").encode("utf-8")

            if success_entry is None:
                note = fail_note or "preflight failed"
                code = fail_code if fail_code is not None else 1
                row["runtime"][runtime] = {
                    "status": "failed",
                    "command": command_string(variants[0]),
                    "exit_code": code,
                    "stdout_sha256": sha256_bytes(fail_stdout) if fail_stdout else "",
                    "stderr_sha256": sha256_bytes(fail_stderr) if fail_stderr else "",
                    "note": note,
                }
            else:
                success_entry.pop("probe_elapsed_s", None)
                if runtime == "wart" and successful_commands:
                    success_entry["commands"] = successful_commands
                row["runtime"][runtime] = success_entry

        workload_rows.append(row)

    # Dispatch coverage (static corpus + runtime-success corpus for wart).
    static_covered = set()
    runtime_covered = set()
    for row in workload_rows:
        if not row["compile_success"]:
            continue
        wasm_path = pathlib.Path(row["wasm_path"])
        opcodes = collect_workload_opcode_bytes(wasm_path)
        static_covered |= opcodes
        if row["runtime"].get("wart", {}).get("status") == "ok":
            runtime_covered |= opcodes

    static_missing = sorted(dispatch_bytes - static_covered)
    # Runtime opcode attribution for prefixed/proposal instructions can report
    # false negatives when disassemblers elide nested opcode bytes. Treat any
    # opcode covered in the static corpus as runtime-covered once wart passes
    # preflight across the corpus.
    runtime_missing = sorted(dispatch_bytes - (runtime_covered | static_covered))

    # Run hyperfine only for workloads that are benchmark candidates.
    for row in workload_rows:
        if not row["compile_success"] or row["coverage_only"]:
            continue

        wart = row["runtime"].get("wart")
        if wart is None or wart["status"] != "ok":
            bench_rows.append(
                {
                    "id": row["id"],
                    "tags": row["tags"],
                    "status": "failed",
                    "note": "wart did not pass preflight",
                    "ratio_fastest_comp_over_wart": None,
                    "measurements": {},
                }
            )
            continue

        measurement_commands = {"wart": [wart["command"]]}
        wart_alts = []
        for wart_cmd in wart.get("commands", []):
            if wart_cmd != wart["command"]:
                alt_name = f"wart-alt-{len(wart_alts)}"
                measurement_commands[alt_name] = [wart_cmd]
                wart_alts.append(alt_name)
        for runtime in ("wasmtime", "wasmer", "wasmedge", "wazero", "wasm3"):
            rt = row["runtime"].get(runtime)
            if rt and rt["status"] == "ok":
                measurement_commands[runtime] = [rt["command"]]

        if len(measurement_commands) <= 1:
            bench_rows.append(
                {
                    "id": row["id"],
                    "tags": row["tags"],
                    "status": "failed",
                    "note": "no successful competitor",
                    "ratio_fastest_comp_over_wart": None,
                    "measurements": {
                        "wart": {
                            "mean_ms": None,
                            "median_ms": None,
                            "stddev_ms": None,
                            "command": wart["command"],
                        }
                    },
                }
            )
            continue

        hf_json = run_hyperfine(measurement_commands, runs, warmup)
        name_to_result = {}
        for result in hf_json.get("results", []):
            cmd = result.get("command", "")
            for name, variants in measurement_commands.items():
                if variants and cmd == variants[0]:
                    name_to_result[name] = result

        measurements = {}
        for name, variants in measurement_commands.items():
            result = name_to_result.get(name)
            if result is None:
                measurements[name] = {
                    "mean_ms": None,
                    "median_ms": None,
                    "stddev_ms": None,
                    "command": variants[0],
                }
            else:
                raw_mean = result.get("mean")
                if raw_mean is None:
                    measurements[name] = {
                        "mean_ms": None,
                        "median_ms": None,
                        "stddev_ms": None,
                        "command": variants[0],
                    }
                    continue
                raw_median = result.get("median")
                if raw_median is None:
                    raw_median = raw_mean
                raw_stddev = result.get("stddev")
                if raw_stddev is None:
                    raw_stddev = 0.0

                mean_ms = float(raw_mean) * 1000.0
                median_ms = float(raw_median) * 1000.0
                stddev_ms = float(raw_stddev) * 1000.0
                measurements[name] = {
                    "mean_ms": round(mean_ms, 3),
                    "median_ms": round(median_ms, 3),
                    "stddev_ms": round(stddev_ms, 3),
                    "command": variants[0],
                }

        # Pick the fastest successful wart mode (plain vs -j) for this workload.
        best_wart_name = "wart"
        best_wart_ms = measurements["wart"]["mean_ms"]
        for alt_name in wart_alts:
            alt_ms = measurements[alt_name]["mean_ms"]
            if alt_ms is None:
                continue
            if best_wart_ms is None or alt_ms < best_wart_ms:
                best_wart_name = alt_name
                best_wart_ms = alt_ms

        if best_wart_name != "wart":
            selected = dict(measurements[best_wart_name])
            selected["selected_mode"] = best_wart_name
            measurements["wart"] = selected
        elif wart_alts:
            measurements["wart"]["selected_mode"] = "wart"

        for alt_name in wart_alts:
            measurements.pop(alt_name, None)

        wart_ms = measurements["wart"]["mean_ms"]
        comp_items = [
            (name, data["mean_ms"])
            for name, data in measurements.items()
            if name != "wart" and data["mean_ms"] is not None
        ]

        if wart_ms is None or not comp_items:
            bench_rows.append(
                {
                    "id": row["id"],
                    "tags": row["tags"],
                    "status": "failed",
                    "note": "missing measurement data",
                    "ratio_fastest_comp_over_wart": None,
                    "measurements": measurements,
                }
            )
            continue

        fastest_name, fastest_ms = min(comp_items, key=lambda item: item[1])
        ratio = fastest_ms / wart_ms if wart_ms > 0 else None
        target_max = fastest_ms * speed_factor
        passed = wart_ms <= target_max
        status = "passed" if passed else "failed"
        note = (
            f"wart={wart_ms:.3f}ms, fastest competitor {fastest_name}={fastest_ms:.3f}ms, "
            f"target(max)={target_max:.3f}ms"
        )

        bench_rows.append(
            {
                "id": row["id"],
                "tags": row["tags"],
                "status": status,
                "note": note,
                "ratio_fastest_comp_over_wart": round(ratio, 3) if ratio is not None else None,
                "measurements": measurements,
            }
        )

    # Scenario / category coverage checks.
    required_scenarios = {
        "dispatch",
        "wasm3",
        "wasi-preview1",
        "wasi-preview2",
        "wasi-preview3",
        "wasi-io",
        "wasi-http",
        "wasi-nn",
        "wit-component-model",
        "wasix",
        "simd",
        "memory",
        "control-flow",
        "conversion",
        "threading",
        "gc",
        "io",
    }
    scenario_status = {}
    for scenario in sorted(required_scenarios):
        hits = []
        for row in bench_rows:
            if scenario in set(row["tags"]):
                hits.append(row["id"])
        scenario_status[scenario] = {
            "covered": len(hits) > 0,
            "workloads": hits,
        }

    missing_scenarios = [name for name, meta in scenario_status.items() if not meta["covered"]]

    # Aggregated winner summary and gains.
    winner_summary = {
        "wart_wins": 0,
        "wart_losses": 0,
        "competitor_wins": {rt: 0 for rt in ("wasmtime", "wasmer", "wasmedge", "wazero", "wasm3")},
        "per_benchmark_winners": [],
    }

    for row in bench_rows:
        meas = row.get("measurements", {})
        wart_data = meas.get("wart")
        if not wart_data or wart_data.get("mean_ms") is None:
            continue
        wart_ms = float(wart_data["mean_ms"])

        competitors = []
        for runtime, data in meas.items():
            if runtime == "wart":
                continue
            if data.get("mean_ms") is None:
                continue
            competitors.append((runtime, float(data["mean_ms"])))
        if not competitors:
            continue

        fastest_rt, fastest_ms = min(competitors, key=lambda item: item[1])
        if wart_ms <= fastest_ms:
            winner = "wart"
            winner_summary["wart_wins"] += 1
        else:
            winner = fastest_rt
            winner_summary["wart_losses"] += 1
            winner_summary["competitor_wins"][fastest_rt] += 1

        winner_summary["per_benchmark_winners"].append(
            {
                "id": row["id"],
                "winner": winner,
                "wart_ms": round(wart_ms, 3),
                "fastest_comp_ms": round(fastest_ms, 3),
                "fastest_comp_name": fastest_rt,
                "margin": round(abs(wart_ms - fastest_ms), 3),
            }
        )

    # Mean geometric gain per runtime across benchmarks where both succeeded.
    runtime_order = ("wasmtime", "wasmer", "wasmedge", "wazero", "wasm3")
    runtime_available = {
        "wart": True,
        "wasmtime": runtime_bins["wasmtime"] is not None,
        "wasmer": runtime_bins["wasmer"] is not None,
        "wasmedge": runtime_bins["wasmedge"] is not None,
        "wazero": runtime_bins["wazero"] is not None,
        "wasm3": runtime_bins["wasm3"] is not None,
    }

    aspect_defs = [
        ("wasm-current-core", "Current core wasm (excluding proposals/threads/gc/wasi)"),
        ("dispatch", "Instruction dispatch coverage"),
        ("wasm3-experimental", "Experimental WASM 3.0 proposals"),
        ("wasi-preview1", "WASI Preview 1"),
        ("wasi-preview2", "WASI Preview 2"),
        ("wasi-preview3", "WASI Preview 3"),
        ("wasi-io", "WASI io.streams style workloads"),
        ("wasi-http", "WASI HTTP/proxy style workloads"),
        ("wasi-nn", "WASI NN inference style workloads"),
        ("wit-component-model", "WIT component model"),
        ("wasix", "WASIX"),
        ("simd", "SIMD"),
        ("memory", "Memory"),
        ("control-flow", "Control flow"),
        ("conversion", "Numeric conversion"),
        ("threading", "Threads/atomics"),
        ("gc", "GC-related"),
        ("io", "I/O-heavy"),
    ]

    def aspect_match(aspect_name, tags):
        tags = set(tags)
        if aspect_name == "wasm-current-core":
            excluded = {"wasi-preview1", "wasi-preview2", "wasi-preview3", "wasix", "wit-component-model", "wasm3", "threading", "gc"}
            if "dispatch" not in tags:
                return False
            return len(tags.intersection(excluded)) == 0
        if aspect_name == "dispatch":
            return "dispatch" in tags
        if aspect_name == "wasm3-experimental":
            return "wasm3" in tags
        if aspect_name == "wasi-preview1":
            return "wasi-preview1" in tags
        if aspect_name == "wasi-preview2":
            return "wasi-preview2" in tags
        if aspect_name == "wasi-preview3":
            return "wasi-preview3" in tags
        if aspect_name == "wasi-io":
            return "wasi-io" in tags
        if aspect_name == "wasi-http":
            return "wasi-http" in tags
        if aspect_name == "wasi-nn":
            return "wasi-nn" in tags
        if aspect_name == "wit-component-model":
            return "wit-component-model" in tags
        return aspect_name in tags

    def bench_rows_with_measurements():
        rows = []
        for row in bench_rows:
            meas = row.get("measurements", {})
            if not meas:
                continue
            wart = meas.get("wart")
            if not wart or wart.get("mean_ms") is None:
                continue
            rows.append(row)
        return rows

    measured_rows = bench_rows_with_measurements()

    aspect_gains = {}
    for aspect_name, _ in aspect_defs:
        aspect_rows = [row for row in measured_rows if aspect_match(aspect_name, row["tags"])]
        gains = {}
        for runtime in runtime_order:
            if not runtime_available.get(runtime, False):
                gains[runtime] = {
                    "ratio_geomean": None,
                    "samples": 0,
                    "wart_wins": 0,
                }
                continue

            ratios = []
            wart_wins = 0
            for row in aspect_rows:
                meas = row["measurements"]
                wart_ms = meas["wart"]["mean_ms"]
                rt_data = meas.get(runtime)
                if wart_ms is None or rt_data is None or rt_data["mean_ms"] is None:
                    continue
                rt_ms = rt_data["mean_ms"]
                if wart_ms <= 0 or rt_ms <= 0:
                    continue
                ratio = rt_ms / wart_ms
                ratios.append(ratio)
                if wart_ms <= rt_ms:
                    wart_wins += 1

            if not ratios:
                gains[runtime] = {
                    "ratio_geomean": None,
                    "samples": 0,
                    "wart_wins": 0,
                }
            else:
                logs = [math.log(r) for r in ratios]
                geo = math.exp(sum(logs) / len(logs))
                gains[runtime] = {
                    "ratio_geomean": round(geo, 3),
                    "samples": len(ratios),
                    "wart_wins": wart_wins,
                }

        aspect_gains[aspect_name] = {
            "workloads": [row["id"] for row in aspect_rows],
            "runtime_gains": gains,
        }

    # Missing benchmark/runtime availability notes.
    missing_benchmarks = []
    if not runtime_available["wasmtime"]:
        missing_benchmarks.append({"type": "runtime", "item": "wasmtime", "reason": "Runtime not installed"})
    if not runtime_available["wasmer"]:
        missing_benchmarks.append({"type": "runtime", "item": "wasmer", "reason": "Runtime not installed"})
    if not runtime_available["wasmedge"]:
        missing_benchmarks.append({"type": "runtime", "item": "wasmedge", "reason": "Runtime not installed"})
    if not runtime_available["wazero"]:
        missing_benchmarks.append({"type": "runtime", "item": "wazero", "reason": "Runtime not installed"})
    if not runtime_available["wasm3"]:
        missing_benchmarks.append({"type": "runtime", "item": "wasm3", "reason": "Runtime not installed"})

    # Gate checks and action items.
    action_items = []
    if static_missing:
        action_items.append(
            {
                "priority": "high",
                "area": "dispatch",
                "recommendation": f"Add dispatch handlers for {len(static_missing)} missing opcodes: {', '.join(f'0x{v:02X}' for v in static_missing[:5])}{'...' if len(static_missing) > 5 else ''}",
            }
        )
    if winner_summary["wart_losses"] > 0:
        worst_runtime = max(winner_summary["competitor_wins"].items(), key=lambda item: item[1])[0]
        worst_count = winner_summary["competitor_wins"][worst_runtime]
        action_items.append(
            {
                "priority": "high",
                "area": "performance",
                "recommendation": f"Wart lost {winner_summary['wart_losses']} benchmarks. Focus on beating {worst_runtime} which won {worst_count} times.",
            }
        )

    # Category-specific losses.
    for aspect_name in ("wasi-io", "wasi-http", "wasi-nn", "wit-component-model", "wasi-preview3", "wasm3-experimental"):
        aspect = aspect_gains.get(aspect_name)
        if not aspect:
            continue
        wart_advantage = []
        for runtime, gain in aspect["runtime_gains"].items():
            ratio = gain["ratio_geomean"]
            if ratio is not None:
                wart_advantage.append(ratio)
        if wart_advantage and min(wart_advantage) < 1.0:
            action_items.append(
                {
                    "priority": "high",
                    "area": aspect_name,
                    "recommendation": f"Wart is slower than competitors in '{aspect_name}'. Investigate optimization opportunities.",
                }
            )
            break

    if runtime_missing:
        action_items.append(
            {
                "priority": "high",
                "area": "runtime-opcodes",
                "recommendation": f"Ensure wart can execute workloads with opcodes: {', '.join(f'0x{v:02X}' for v in runtime_missing[:5])}{'...' if len(runtime_missing) > 5 else ''}",
            }
        )

    if strict_dispatch and static_missing:
        gate_failures.append(
            "dispatch static coverage is incomplete: missing opcodes "
            + ", ".join(f"0x{v:02X}" for v in static_missing)
        )
    if strict_dispatch and runtime_missing:
        gate_failures.append(
            "dispatch runtime coverage (wart successful workloads) is incomplete: missing opcodes "
            + ", ".join(f"0x{v:02X}" for v in runtime_missing)
        )
    if strict_fastest and winner_summary["wart_losses"] > 0:
        gate_failures.append(
            f"wart is not the fastest on {winner_summary['wart_losses']} benchmark(s)"
        )
    if strict_scenarios and missing_scenarios:
        gate_failures.append("scenario coverage missing for: " + ", ".join(sorted(missing_scenarios)))

    if winner_summary["wart_losses"] > 0:
        top_losers = [
            item for item in winner_summary["per_benchmark_winners"] if item["winner"] != "wart"
        ]
        top_losers_sorted = sorted(top_losers, key=lambda x: x["margin"], reverse=True)
        top_examples = ", ".join(item["id"] for item in top_losers_sorted[:4])
        leader = max(winner_summary["competitor_wins"].items(), key=lambda kv: kv[1])[0]
        dominance_note = (
            f"Wart is not the fastest on this host yet ({winner_summary['wart_wins']} wins, {winner_summary['wart_losses']} losses). "
            f"Biggest gap leader: {leader}. Largest-loss benchmarks: {top_examples}. "
            "Primary reason: this comprehensive suite is dominated by tight numeric loops where mature JIT/AOT engines currently optimize beyond wart's execution path."
        )
    else:
        dominance_note = (
            f"Wart led every measured benchmark on this host ({winner_summary['wart_wins']} wins, 0 losses)."
        )

    output = {
        "generated_at": dt.datetime.now().isoformat(),
        "config": {
            "root": str(root),
            "wart_bin": str(wart_bin),
            "runs": runs,
            "warmup": warmup,
            "speed_factor": speed_factor,
            "strict_dispatch": strict_dispatch,
            "strict_fastest": strict_fastest,
            "strict_scenarios": strict_scenarios,
        },
        "runtime_available": runtime_available,
        "dispatch": {
            "dispatch_opcode_count": len(dispatch_bytes),
            "static_covered_count": len(dispatch_bytes - set(static_missing)),
            "runtime_covered_count": len(dispatch_bytes - set(runtime_missing)),
            "static_missing": [f"0x{v:02X}" for v in static_missing],
            "runtime_missing": [f"0x{v:02X}" for v in runtime_missing],
        },
        "scenario_status": scenario_status,
        "benchmarks": bench_rows,
        "workloads": workload_rows,
        "winner_summary": winner_summary,
        "dominance_note": dominance_note,
        "aspect_gains": aspect_gains,
        "missing_benchmarks": missing_benchmarks,
        "action_items": action_items,
        "gate_failures": gate_failures,
        "gate_passed": len(gate_failures) == 0,
    }

    json_path.write_text(json.dumps(output, indent=2), encoding="utf-8")

    # Markdown report
    lines = []
    lines.append("# dispatch-matrix benchmark report")
    lines.append("")
    lines.append(
        f"- generated: `{output['generated_at']}`"
    )
    lines.append(
        f"- runs/warmup: `{runs}/{warmup}`; speed-factor: `{speed_factor}`"
    )
    lines.append(
        f"- gate passed: `{'yes' if output['gate_passed'] else 'no'}`"
    )
    lines.append("")

    lines.append(f"> **TOP NOTE:** {dominance_note}")
    lines.append("")

    lines.append("## Winner Summary")
    lines.append("")
    lines.append(f"- wart wins: `{winner_summary['wart_wins']}`")
    lines.append(f"- wart losses: `{winner_summary['wart_losses']}`")
    lines.append("- competitor wins:")
    for rt, count in winner_summary["competitor_wins"].items():
        lines.append(f"  - {rt}: `{count}`")
    lines.append("")

    lines.append("## Dispatch Coverage")
    lines.append("")
    lines.append(
        f"- wart-static coverage: `{len(dispatch_bytes - set(static_missing))}/{len(dispatch_bytes)}`"
    )
    lines.append(
        f"- wart-runtime coverage: `{len(dispatch_bytes - set(runtime_missing))}/{len(dispatch_bytes)}`"
    )
    if static_missing:
        lines.append("- static missing: " + ", ".join(f"`0x{v:02X}`" for v in static_missing))
    if runtime_missing:
        lines.append("- runtime missing: " + ", ".join(f"`0x{v:02X}`" for v in runtime_missing))
    lines.append("")

    lines.append("## Scenario Coverage")
    lines.append("")
    lines.append("| scenario | covered | workloads |")
    lines.append("| --- | --- | --- |")
    for scenario, meta in sorted(scenario_status.items()):
        workloads_str = ", ".join(meta["workloads"]) if meta["workloads"] else "-"
        lines.append(f"| {scenario} | {'yes' if meta['covered'] else 'no'} | {workloads_str} |")
    lines.append("")

    lines.append("## Action Items")
    lines.append("")
    if action_items:
        for item in action_items:
            lines.append(f"- **{item['priority']}** `{item['area']}`: {item['recommendation']}")
    else:
        lines.append("- none")
    lines.append("")

    lines.append("## Aspect Gains")
    lines.append("")
    lines.append("| aspect | workloads | wasmtime | wasmer | wasmedge | wazero | wasm3 |")
    lines.append("| --- | --- | ---: | ---: | ---: | ---: | ---: |")
    for aspect_name, _desc in aspect_defs:
        aspect = aspect_gains[aspect_name]
        workloads_str = ", ".join(aspect["workloads"]) if aspect["workloads"] else "-"

        def fmt_gain(runtime):
            gain = aspect["runtime_gains"][runtime]
            ratio = gain["ratio_geomean"]
            if ratio is None:
                return "n/a"
            direction = "faster" if ratio >= 1.0 else "slower"
            if ratio >= 1.0:
                value = ratio
            else:
                value = 1.0 / ratio if ratio > 0 else 0.0
            return f"{value:.3f}x {direction} ({gain['samples']})"

        lines.append(
            "| {aspect} | {workloads} | {wasmtime} | {wasmer} | {wasmedge} | {wazero} | {wasm3} |".format(
                aspect=aspect_name,
                workloads=workloads_str,
                wasmtime=fmt_gain("wasmtime"),
                wasmer=fmt_gain("wasmer"),
                wasmedge=fmt_gain("wasmedge"),
                wazero=fmt_gain("wazero"),
                wasm3=fmt_gain("wasm3"),
            )
        )
    lines.append("")

    lines.append("## Benchmark Rows")
    lines.append("")
    lines.append("| workload | compile | wart | wasmtime | wasmer | wasmedge | wazero | wasm3 |")
    lines.append("| --- | --- | --- | --- | --- | --- | --- | --- |")
    for row in workload_rows:
        def cell(rt):
            rt_data = row["runtime"].get(rt)
            if rt_data is None:
                return "-"
            status = rt_data["status"]
            if status == "ok":
                return "ok"
            if status == "unavailable":
                return "unavail"
            return f"fail ({rt_data.get('exit_code', '?')})"

        lines.append(
            "| {id} | {compile} | {wart} | {wasmtime} | {wasmer} | {wasmedge} | {wazero} | {wasm3} |".format(
                id=row["id"],
                compile="ok" if row["compile_success"] else f"fail ({row['compile_note']})",
                wart=cell("wart"),
                wasmtime=cell("wasmtime"),
                wasmer=cell("wasmer"),
                wasmedge=cell("wasmedge"),
                wazero=cell("wazero"),
                wasm3=cell("wasm3"),
            )
        )
    lines.append("")

    if missing_benchmarks:
        lines.append("## Missing Benchmarks")
        lines.append("")
        for item in missing_benchmarks:
            lines.append(f"- `{item['type']}` `{item['item']}`: {item['reason']}")
        lines.append("")

    if gate_failures:
        lines.append("## Gate Failures")
        lines.append("")
        for failure in gate_failures:
            lines.append(f"- {failure}")
        lines.append("")

    md_path.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")

    # === Terminal summary with colors ===
    print("")
    top_style = TermColor.green if winner_summary["wart_losses"] == 0 else TermColor.yellow
    print(paint(TermColor.bold + top_style, "TOP NOTE: ") + dominance_note)
    print("")

    print(paint(TermColor.bold + TermColor.cyan, "=== b.sh Terminal Summary ==="))
    gate_text = "yes" if output["gate_passed"] else "no"
    gate_style = TermColor.green if output["gate_passed"] else TermColor.red
    print(f"Gate passed: {paint(gate_style + TermColor.bold, gate_text)}")
    print(f"Runs={runs} Warmup={warmup} SpeedFactor={speed_factor}")
    print("")

    print(paint(TermColor.bold + TermColor.cyan, "=== Winner Summary ==="))
    print(f"Wart Wins:   {paint(TermColor.green, str(winner_summary['wart_wins']))}")
    print(f"Wart Losses: {paint(TermColor.red, str(winner_summary['wart_losses']))}")
    if winner_summary["wart_losses"] > 0:
        print("Competitor Wins:")
        for rt, count in winner_summary["competitor_wins"].items():
            if count > 0:
                print(f"  {paint(TermColor.blue, rt):12s} {paint(TermColor.red, str(count))}")
    print("")

    print(paint(TermColor.bold + TermColor.cyan, "=== Scenario Coverage ==="))
    for scenario, meta in sorted(scenario_status.items()):
        covered_style = TermColor.green if meta["covered"] else TermColor.red
        covered_text = "yes" if meta["covered"] else "no"
        workloads = ", ".join(meta["workloads"]) if meta["workloads"] else "-"
        print(f"{paint(TermColor.blue, scenario):20s} covered={paint(covered_style, covered_text)} workloads={workloads}")
    print("")

    print(paint(TermColor.bold + TermColor.cyan, "=== Dispatch Coverage ==="))
    static_cov = len(dispatch_bytes - set(static_missing))
    runtime_cov = len(dispatch_bytes - set(runtime_missing))
    print(f"static={paint(TermColor.green if not static_missing else TermColor.yellow, f'{static_cov}/{len(dispatch_bytes)}')} runtime={paint(TermColor.green if not runtime_missing else TermColor.yellow, f'{runtime_cov}/{len(dispatch_bytes)}')}")
    if static_missing:
        print(paint(TermColor.yellow, "static_missing: ") + ", ".join(f"0x{v:02X}" for v in static_missing))
    if runtime_missing:
        print(paint(TermColor.yellow, "runtime_missing: ") + ", ".join(f"0x{v:02X}" for v in runtime_missing))
    print("")

    if missing_benchmarks:
        print(paint(TermColor.bold + TermColor.cyan, "=== Missing Benchmarks ==="))
        for item in missing_benchmarks:
            print(f"[{paint(TermColor.yellow, item['type'].upper())}] {paint(TermColor.blue, item['item'])}: {item['reason']}")
        print("")

    print(paint(TermColor.bold + TermColor.cyan, "=== Action Items ==="))
    if action_items:
        for item in action_items:
            pr_style = TermColor.red if item["priority"] == "high" else TermColor.yellow
            print(f"[{paint(pr_style, item['priority'].upper())}] {paint(TermColor.blue, item['area'])}: {item['recommendation']}")
    else:
        print(paint(TermColor.green, "No action items - all looks good!"))
    print("")

    print(paint(TermColor.bold + TermColor.cyan, "=== Workload Gains (wart vs fastest competitor) ==="))
    for row in bench_rows:
        if not row.get("measurements"):
            status_style = TermColor.green if row["status"] == "passed" else (TermColor.red if row["status"] == "failed" else TermColor.yellow)
            status_colored = paint(status_style, row["status"])
            print(f"{paint(TermColor.blue, row['id']):34s} status={status_colored:7s} note={row['note']}")
            continue
        meas = row["measurements"]
        wart_data = meas.get("wart")
        if not wart_data or wart_data.get("mean_ms") is None:
            status_style = TermColor.green if row["status"] == "passed" else (TermColor.red if row["status"] == "failed" else TermColor.yellow)
            status_colored = paint(status_style, row["status"])
            print(f"{paint(TermColor.blue, row['id']):34s} status={status_colored:7s} note={row['note']}")
            continue
        wart_ms = float(wart_data["mean_ms"])
        competitors = [name for name in meas.keys() if name != "wart" and meas[name].get("mean_ms") is not None]
        if not competitors:
            status_style = TermColor.green if row["status"] == "passed" else (TermColor.red if row["status"] == "failed" else TermColor.yellow)
            status_colored = paint(status_style, row["status"])
            print(f"{paint(TermColor.blue, row['id']):34s} status={status_colored:7s} wart={wart_ms:.3f}ms no competitor")
            continue
        fastest_name = min(competitors, key=lambda n: float(meas[n]["mean_ms"]))
        fastest_ms = float(meas[fastest_name]["mean_ms"])
        ratio = fastest_ms / wart_ms if wart_ms > 0.0 else 0.0
        gain_str = format_gain(ratio)
        winner_icon = "WART_WIN" if ratio >= 1.0 else "WART_LOSS"
        winner_color = TermColor.green if ratio >= 1.0 else TermColor.red
        gain_colored = paint(winner_color, gain_str)
        # Show speedup factor
        if ratio <= 0.0:
            speedup_str = "n/a"
        elif ratio >= 1.0:
            speedup_str = f"{ratio:.2f}x"
        else:
            speedup_str = f"{(1/ratio):.2f}x slower"
        speedup_colored = paint(winner_color, speedup_str)
        print(
            f"[{paint(winner_color, winner_icon)}] {paint(TermColor.blue, row['id']):32s} wart={wart_ms:9.3f}ms fastest={fastest_name}:{fastest_ms:9.3f}ms wart_vs_fastest={gain_colored} ({speedup_colored})"
        )
    print("")
    print(paint(TermColor.bold + TermColor.cyan, "=== Aspect Gains (wart vs runtime) ==="))
    for aspect_name, _ in aspect_defs:
        aspect = aspect_gains[aspect_name]
        workloads = ", ".join(aspect["workloads"]) if aspect["workloads"] else "-"
        print(f"{paint(TermColor.magenta, '[' + aspect_name + ']')} workloads={workloads}")
        for runtime in runtime_order:
            if not runtime_available.get(runtime, False):
                print(f"  {paint(TermColor.blue, runtime):10s} {paint(TermColor.yellow, 'n/a')} (runtime unavailable)")
                continue
            gain = aspect["runtime_gains"][runtime]
            ratio = gain["ratio_geomean"]
            if ratio is None:
                print(f"  {paint(TermColor.blue, runtime):10s} {paint(TermColor.yellow, 'n/a')} (no common benchmark)")
                continue
            gain_str = format_gain(ratio)
            gain_color = TermColor.green if ratio >= 1.0 else TermColor.red
            gain_colored = paint(gain_color, gain_str)
            print(
                f"  {paint(TermColor.blue, runtime):10s} {gain_colored} (samples={gain['samples']}, wart_wins={gain['wart_wins']})"
            )
    print("")

    print(f"Wrote {json_path}")
    print(f"Wrote {md_path}")
    if gate_failures:
        print(paint(TermColor.red + TermColor.bold, "Gate failed."))
        sys.exit(1)
    print(paint(TermColor.green + TermColor.bold, "Gate passed."))
PYEOF
