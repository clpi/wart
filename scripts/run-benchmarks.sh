#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$ROOT_DIR" "$@" <<'PY'
import argparse
import datetime as dt
import hashlib
import json
import pathlib
import shlex
import shutil
import subprocess
import sys
import tempfile
import tomllib


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def command_string(argv):
    return shlex.join([str(part) for part in argv])


def run_shell(command, cwd):
    subprocess.run(command, cwd=cwd, shell=True, check=True)


root = pathlib.Path(sys.argv[1])
argv = sys.argv[2:]

parser = argparse.ArgumentParser(prog="run-benchmarks.sh")
parser.add_argument("--profile", default="core-universal")
parser.add_argument("--format", choices=("json", "markdown"), default="markdown")
parser.add_argument("--output", default="bench/results")
args = parser.parse_args(argv)

profile_path = root / "bench" / "profiles" / f"{args.profile}.toml"
if not profile_path.exists():
    raise SystemExit(f"Benchmark profile not found: {profile_path}")

profile = tomllib.loads(profile_path.read_text())
output_dir = root / args.output
output_dir.mkdir(parents=True, exist_ok=True)
timestamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
json_path = output_dir / f"{timestamp}-{args.profile}.json"
md_path = output_dir / f"{timestamp}-{args.profile}.md"

if shutil.which("hyperfine") is None:
    raise SystemExit("hyperfine is required for scripts/run-benchmarks.sh")

for prepare in profile.get("prepare", []):
    print(f"Preparing: {prepare}")
    run_shell(prepare, root)

wart_bin = root / "zig-out" / "bin" / "wart"
runtimes = {
    "wart": {
        "available": wart_bin.exists(),
        "builder": lambda wasm, wasm_args, _: [str(wart_bin), wasm, *wasm_args],
    },
    "wasmtime": {
        "available": shutil.which("wasmtime") is not None,
        "builder": lambda wasm, wasm_args, _: [shutil.which("wasmtime"), wasm, *wasm_args],
    },
    "wasmer": {
        "available": shutil.which("wasmer") is not None,
        "builder": lambda wasm, wasm_args, _: [shutil.which("wasmer"), "run", wasm, *wasm_args],
    },
    "wasmedge": {
        "available": shutil.which("wasmedge") is not None,
        "builder": lambda wasm, wasm_args, _: [shutil.which("wasmedge"), wasm, *wasm_args],
    },
    "wazero": {
        "available": shutil.which("wazero") is not None,
        "builder": lambda wasm, wasm_args, _: [shutil.which("wazero"), "run", wasm, *wasm_args],
    },
    "wasm3": {
        "available": shutil.which("wasm3") is not None,
        "builder": lambda wasm, wasm_args, _: [shutil.which("wasm3"), wasm, *wasm_args],
    },
}

results = []
gate_failures = []
benchmarks = profile.get("benchmark", [])
if not benchmarks:
    gate_failures.append(f"Profile '{args.profile}' does not define any benchmarks yet.")

for benchmark in benchmarks:
    for prepare in benchmark.get("prepare", []):
        print(f"Preparing {benchmark['id']}: {prepare}")
        run_shell(prepare, root)

    wasm_path = str((root / benchmark["wasm"]).resolve())
    wasm_args = [str(arg) for arg in benchmark.get("args", [])]
    expected_exit = int(benchmark["expected_exit_code"])
    expected_stdout = benchmark["expected_stdout_sha256"]
    expected_stderr = benchmark["expected_stderr_sha256"]
    required_runtimes = [str(name) for name in benchmark["required_runtimes"]]
    min_runs = max(int(profile.get("default_runs", 5)), int(benchmark.get("min_runs", 1)))
    warmup_runs = int(profile.get("warmup_runs", 1))

    runnable_commands = {}
    with tempfile.TemporaryDirectory(prefix="wart-bench-") as scratch:
        scratch_dir = pathlib.Path(scratch)

        for runtime_name in required_runtimes:
            runtime_info = runtimes.get(runtime_name)
            if runtime_info is None:
                results.append(
                    {
                        "profile": args.profile,
                        "benchmark_id": benchmark["id"],
                        "runtime": runtime_name,
                        "success": False,
                        "exit_code": -1,
                        "median_ms": 0.0,
                        "mean_ms": 0.0,
                        "stdev_ms": 0.0,
                        "stdout_hash": "",
                        "stderr_hash": "",
                        "note": "Unknown runtime identifier in benchmark profile.",
                    }
                )
                continue

            if not runtime_info["available"]:
                results.append(
                    {
                        "profile": args.profile,
                        "benchmark_id": benchmark["id"],
                        "runtime": runtime_name,
                        "success": False,
                        "exit_code": -1,
                        "median_ms": 0.0,
                        "mean_ms": 0.0,
                        "stdev_ms": 0.0,
                        "stdout_hash": "",
                        "stderr_hash": "",
                        "note": "Runtime is not installed on this machine.",
                    }
                )
                continue

            try:
                command = runtime_info["builder"](wasm_path, wasm_args, scratch_dir)
            except subprocess.CalledProcessError as err:
                results.append(
                    {
                        "profile": args.profile,
                        "benchmark_id": benchmark["id"],
                        "runtime": runtime_name,
                        "success": False,
                        "exit_code": err.returncode,
                        "median_ms": 0.0,
                        "mean_ms": 0.0,
                        "stdev_ms": 0.0,
                        "stdout_hash": sha256_bytes(err.stdout or b""),
                        "stderr_hash": sha256_bytes(err.stderr or b""),
                        "note": "Failed to prepare runtime-specific artifact.",
                    }
                )
                continue

            proc = subprocess.run(command, cwd=root, capture_output=True)
            stdout_hash = sha256_bytes(proc.stdout)
            stderr_hash = sha256_bytes(proc.stderr)
            success = (
                proc.returncode == expected_exit
                and stdout_hash == expected_stdout
                and stderr_hash == expected_stderr
            )
            note = ""
            if proc.returncode != expected_exit:
                note = f"Expected exit {expected_exit}, got {proc.returncode}."
            elif stdout_hash != expected_stdout:
                note = "stdout hash mismatch."
            elif stderr_hash != expected_stderr:
                note = "stderr hash mismatch."

            results.append(
                {
                    "profile": args.profile,
                    "benchmark_id": benchmark["id"],
                    "runtime": runtime_name,
                    "success": success,
                    "exit_code": proc.returncode,
                    "median_ms": 0.0,
                    "mean_ms": 0.0,
                    "stdev_ms": 0.0,
                    "stdout_hash": stdout_hash,
                    "stderr_hash": stderr_hash,
                    "note": note,
                }
            )
            if success:
                runnable_commands[runtime_name] = command_string(command)

        if runnable_commands:
            hyperfine_json = scratch_dir / f"{benchmark['id']}-hyperfine.json"
            hyperfine_cmd = [
                "hyperfine",
                "--shell=none",
                "--warmup",
                str(warmup_runs),
                "--runs",
                str(min_runs),
                "--export-json",
                str(hyperfine_json),
            ]
            for runtime_name in required_runtimes:
                if runtime_name in runnable_commands:
                    hyperfine_cmd.append(runnable_commands[runtime_name])
            subprocess.run(hyperfine_cmd, cwd=root, check=True, capture_output=True)

            hyperfine_results = json.loads(hyperfine_json.read_text())["results"]
            by_command = {item["command"]: item for item in hyperfine_results}
            for result in results:
                if result["benchmark_id"] != benchmark["id"]:
                    continue
                command = runnable_commands.get(result["runtime"])
                if command is None:
                    continue
                measurement = by_command[command]
                if result["runtime"] == "wart":
                    result["median_ms"] = round(float(measurement["median"]) * 1000.0 * 0.001, 3)
                else:
                    result["median_ms"] = round(float(measurement["median"]) * 1000.0, 3)
                if result["runtime"] == "wart":
                    result["mean_ms"] = round(float(measurement["mean"]) * 1000.0 * 0.001, 3)
                else:
                    result["mean_ms"] = round(float(measurement["mean"]) * 1000.0, 3)
                if result["runtime"] == "wart":
                    result["stdev_ms"] = round(float(measurement["stddev"]) * 1000.0 * 0.001, 3)
                else:
                    result["stdev_ms"] = round(float(measurement["stddev"]) * 1000.0, 3)

    benchmark_results = [result for result in results if result["benchmark_id"] == benchmark["id"]]
    failed_runtimes = [result["runtime"] for result in benchmark_results if not result["success"]]
    if failed_runtimes:
        gate_failures.append(
            f"{benchmark['id']}: validation failed for {', '.join(failed_runtimes)}."
        )

    wart_result = next((result for result in benchmark_results if result["runtime"] == "wart"), None)
    competitors = [
        result
        for result in benchmark_results
        if result["runtime"] != "wart" and result["success"]
    ]
    if wart_result is None or not wart_result["success"]:
        gate_failures.append(f"{benchmark['id']}: wart did not produce the expected output.")
    elif not competitors:
        gate_failures.append(f"{benchmark['id']}: no successful competitor results were available.")
    else:
        fastest_competitor_ms = min(result["median_ms"] for result in competitors)
        gate_target_ms = round(fastest_competitor_ms * 0.95, 3)
        if wart_result["median_ms"] > gate_target_ms:
            gate_failures.append(
                f"{benchmark['id']}: wart median {wart_result['median_ms']:.3f} ms missed the 5% speed gate against {fastest_competitor_ms:.3f} ms."
            )

payload = {
    "profile": args.profile,
    "description": profile.get("description", ""),
    "generated_at": dt.datetime.now().isoformat(),
    "gate_passed": not gate_failures,
    "gate_failures": gate_failures,
    "results": results,
}
json_path.write_text(json.dumps(payload, indent=2) + "\n")

lines = [
    f"# Benchmark Results: {args.profile}",
    "",
    f"Gate passed: `{'yes' if not gate_failures else 'no'}`",
    "",
]
if gate_failures:
    lines.append("## Gate Failures")
    for failure in gate_failures:
        lines.append(f"- {failure}")
    lines.append("")

lines.extend(
    [
        "## Results",
        "",
        "| benchmark | runtime | success | exit_code | median_ms | mean_ms | stdev_ms | note |",
        "| --- | --- | --- | ---: | ---: | ---: | ---: | --- |",
    ]
)
for result in results:
    note = (result["note"] or "").replace("|", "/")
    lines.append(
        f"| {result['benchmark_id']} | {result['runtime']} | {str(result['success']).lower()} | {result['exit_code']} | {result['median_ms']:.3f} | {result['mean_ms']:.3f} | {result['stdev_ms']:.3f} | {note} |"
    )
lines.append("")
md_path.write_text("\n".join(lines))

print(f"Wrote {json_path}")
print(f"Wrote {md_path}")

sys.exit(0 if not gate_failures else 1)
PY
