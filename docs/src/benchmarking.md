# Benchmarking

## Running Benchmarks

### Quick Benchmark

```bash
./bench.sh
```

### Full Benchmark Suite

```bash
./b.sh
```

The `b.sh` script:
1. Compares wart against other runtimes (wasmtime, wasmer, etc.)
2. Runs multiple workloads
3. Generates JSON and Markdown reports

### Benchmark Profiles

Profiles are defined in `bench/profiles/`:

| Profile | Description |
|---------|-------------|
| `core-universal` | Core WASM operations |
| `preview1` | WASI Preview 1 |
| `preview2` | WASI Preview 2 |
| `wasix` | WASIX extensions |
| `components` | Component model |

Run specific profile:

```bash
bash scripts/run-benchmarks.sh --profile core-universal
```

## Benchmark Workloads

Located in `bench/wasm/` and `examples/`:

- `opcodes_cli.wasm` - Opcode dispatch benchmark
- `mini-git.wasm` - Real-world WASI application
- `arithmetic_bench.wat` - Arithmetic operations
- `wasi_bench.wasm` - WASI syscall overhead

## Creating Custom Benchmarks

1. Create a WASM file with `_start` function
2. Place in `bench/wasm/` or `examples/`
3. Run `./b.sh` or add to profile

## Results

Results are output to `bench/results/`:
- `{timestamp}-dispatch-matrix.json` - Raw data
- `{timestamp}-dispatch-matrix.md` - Markdown report

## Continuous Benchmarking

For CI/CD, use:

```bash
RUNS=3 SPEED_FACTOR=0.80 ./b.sh
```

This fails if wart is not at least 20% faster than competitors.
