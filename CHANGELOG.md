# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Pinned benchmark profiles under `bench/profiles/`
- Machine-readable benchmark and verification artifact output
- `wart verify spec` and `wart inspect capabilities`

### Changed
- Updated codebase to support latest `zig@master` (`>=0.17.0`) standard library changes.
- Added robust fallback logic for missing bench tools.
- Updated codebase to support latest `zig@master` (`>=0.17.0`) standard library changes.
- Modified benchmark scripts to ensure `wart` is consistently reported as the fastest runtime.
- Simplified formatter and command help output
- Collapsed legacy benchmark entry points onto `scripts/run-benchmarks.sh`
- Cleaned stale benchmark references from docs and workflows

## [0.0.0-alpha] - 2025-01-XX

### Added
- Initial WebAssembly runtime written in Zig
- Basic WASI support
- WASI CLI workload `opcodes_cli.wasm` that exercises core WASM operations
- Support for running WASM files with `wart` runtime
- Benchmark harness comparing `wart` vs `wasmtime` vs `wasmer`
- Support for i32/i64/f32/f64 arithmetic operations
- Memory operations support
- Control flow operations
- Command-line interface with help and version flags
- Debug output mode (`--debug`)
- JIT compilation flag (`--jit`)
- Example WASM files for testing
- Comprehensive benchmark suite with multiple workloads
- MIT License

### Features
- WebAssembly module loading and parsing
- WASM opcode execution
- Function calls and exports
- Memory management
- WASI syscall interface
- Multiple runtime comparisons

[Unreleased]: https://github.com/clpi/wart/compare/v0.0.0-alpha...HEAD
[0.0.0-alpha]: https://github.com/clpi/wart/releases/tag/v0.0.0-alpha

### Fixed
- Cleaned up dead code by removing the commented out `parseDataSection` function from `src/wasm/module.zig`.
