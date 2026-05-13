# Running WASM

## Basic Execution

```bash
wart run module.wasm
wart module.wasm  # shorthand
```

## Passing Arguments

Arguments after the WASM file are passed to the module:

```bash
wart echo.wasm hello world
```

## Environment Variables

Control wart behavior:

| Variable | Description |
|----------|-------------|
| `WX_DUMP_STDIO` | Dump stdio buffers for debugging |
| `WX_DUMP_TABLE` | Dump function table for debugging |
| `WX_WASI_DEBUG` | Enable WASI debugging |

## Exit Codes

- `0`: Success
- `1`: General error
- Other: Process exit code from WASM

## JIT Mode

Enable experimental JIT compilation:

```bash
wart --jit module.wasm
```

## AOT Mode

Compile and run in one step:

```bash
wart --aot module.wasm -o module_native
./module_native
```

## Running Components

wart supports WebAssembly components:

```bash
wart component.wasm
```

## Debugging

Enable verbose output:

```bash
wart --debug module.wasm
wart -V 2 module.wasm  # More verbose
```
