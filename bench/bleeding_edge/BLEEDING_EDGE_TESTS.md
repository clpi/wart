# Bleeding Edge WebAssembly Feature Tests

This directory contains comprehensive tests for ALL cutting-edge WASM/WASI/WASIX features.

## Test Files

### 1. Sign-Extension Operators (`sign_extension_test.wasm`)
Tests opcodes 0xC0-0xC4:
- `i32.extend8_s` (0xC0)
- `i32.extend16_s` (0xC1)
- `i64.extend8_s` (0xC2)
- `i64.extend16_s` (0xC3)
- `i64.extend32_s` (0xC4)

**Run:** `../../zig-out/bin/wart sign_extension_test.wasm`

### 2. Comprehensive WASI Test (`comprehensive_test.wasm`)
Tests all WASI Preview 1 features:
- File I/O (fd_read, fd_write, fd_seek, fd_close(.{.userdata=null, .vtable=undefined}))
- fd_datasync (NEW!)
- Directory operations
- Clock functions
- Environment variables
- Random number generation

**Run:** `../../zig-out/bin/wart comprehensive_test.wasm`

### 3. Multi-Value Returns (TBD)
### 4. Tail-Call Optimization (TBD)
### 5. Complete SIMD v128 (TBD)
### 6. WASIX Extensions (TBD)
### 7. Threads & Atomics (TBD)
### 8. Component Model (TBD)

## Creating New Tests

```bash
# WAT to WASM
wat2wasm test.wat -o test.wasm

# C to WASM
wasicc test.c -o test.wasm

# Run test
../../zig-out/bin/wart test.wasm
```

## Benchmark All Features

```bash
cd /Users/clp/x/wart
./bench/comprehensive/benchmark_all.sh
```
