# Example Workloads

This directory contains sample source files, `.wat` fixtures, and prebuilt `.wasm` inputs used for smoke tests and benchmarking.

## Rebuild WAT Fixtures

```bash
for f in examples/*.wat; do
  wat2wasm "$f" -o "${f%.wat}.wasm"
done
```

## Run a Fixture

```bash
zig build
./zig-out/bin/wart examples/simple.wasm
```

For cross-runtime timing runs, use the [benchmark documentation](../bench/README.md).
