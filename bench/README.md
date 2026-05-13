# Benchmarking

Use `bench.sh` or `bench/run.sh` as the cross-runtime benchmark entry points:

```bash
bash bench.sh
bash bench/run.sh --profile core-universal
```

For pinned profile runs with output hashing, runtime eligibility checks, and an explicit speed gate, use:

```bash
wart bench run --profile core-universal --format markdown --output bench/results
```

## Prerequisites

- `zig`
- `hyperfine`
- Optional comparison runtimes on `PATH`: `wasmtime`, `wasmer`, `wasmedge`, `wazero`, `wasm3`

## Profiles

Benchmark manifests live under `bench/profiles/` and define:

- workload id and wasm path
- expected exit code
- expected stdout and stderr hashes
- required runtimes
- minimum run count

The harness does not ignore failures. A benchmark only counts when each required runtime exits successfully and matches the pinned output hashes.
