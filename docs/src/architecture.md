# Architecture

wart is structured as a modular WebAssembly runtime with these main components:

```
┌─────────────────────────────────────────────────────────────┐
│                        CLI (src/cmd/)                        │
├─────────────────────────────────────────────────────────────┤
│                      Runtime (src/wasm/)                     │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐     │
│  │ Module   │  │ Runtime  │  │   JIT    │  │   AOT    │     │
│  │ Decoder  │  │  Loop    │  │ Compiler │  │ Compiler │     │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘     │
│                     │                                       │
│  ┌──────────────────┴──────────────────┐                   │
│  │            WASI Layer                │                   │
│  │  Preview1 │ Preview2 │ Preview3 │ WASIX │               │
│  └──────────────────────────────────────┘                   │
└─────────────────────────────────────────────────────────────┘
```

## Key Directories

| Directory | Purpose |
|-----------|---------|
| `src/cmd/` | CLI command implementations |
| `src/wasm/` | Core runtime, decoder, execution |
| `src/wasm/wasi/` | WASI system interfaces |
| `src/util/` | Utilities (formatting, colors) |
| `src/config/` | Configuration handling |
| `test/` | Test suites |
| `bench/` | Benchmark workloads |
| `examples/` | Sample WASM programs |

## Entry Points

- `src/main.zig` - Program entry, wires `std.Io.Threaded`
- `src/cmd.zig` - Top-level CLI dispatcher
- `src/root.zig` - Library root for shared library target
