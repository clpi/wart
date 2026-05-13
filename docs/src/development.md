# Development

## Building

```bash
# Debug build (fast compile, slow runtime)
zig build

# Release build
zig build -Drelease=true

# With LLVM (best performance)
zig build -Duse-llvm=true -Drelease=true

# Small binary
zig build -Dsmall=true
```

## Running Tests

```bash
# All tests
zig build test

# Specific test file
zig test test/minimal_test.zig
zig test test/features_test.zig
```

## Code Style

- Run `zig fmt` before committing
- Use snake_case for files/functions
- Use UpperCamelCase for types
- Thread `std.Io` explicitly through APIs
- Use `std.wasm` enums for opcodes

## Project Structure

```
src/
├── main.zig          # Entry point
├── cmd.zig           # CLI dispatcher
├── root.zig          # Library root
├── cmd/              # Command implementations
│   ├── common.zig    # Shared types
│   ├── execution.zig # Run/Inspect execution
│   └── *.zig         # Individual commands
├── wasm/             # Runtime core
│   ├── runtime.zig   # Interpreter loop
│   ├── module.zig    # Module decoder
│   ├── op.zig        # Opcode definitions
│   ├── wasi.zig      # WASI Preview 1
│   └── wasi/         # WASI submodules
├── util/             # Utilities
│   └── fmt/          # Formatting helpers
└── config/           # Configuration
```

## Nix Development

```bash
# Enter dev shell
nix develop

# Build
nix build

# Debug build
nix build .#debug
```

## Debugging

```bash
# Enable debug logging
wart --debug module.wasm

# WASI debugging
WX_WASI_DEBUG=1 wart module.wasm

# Dump buffers
WX_DUMP_STDIO=1 WX_DUMP_TABLE=1 wart module.wasm
```
