# Getting Started

## Prerequisites

- Zig 0.16 or later
- A C compiler (for AOT compilation)

## Quick Start

1. Build wart:
```bash
zig build -Drelease=true
```

2. Run a WASM file:
```bash
./zig-out/bin/wart examples/simple.wasm
```

3. Inspect a WASM module:
```bash
./zig-out/bin/wart inspect examples/mini-git.wasm
```

## Building with LLVM

For optimal performance, build with LLVM:
```bash
zig build -Duse-llvm=true -Drelease=true
```

## Running Tests

```bash
zig build test
```
