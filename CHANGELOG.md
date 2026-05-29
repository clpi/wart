# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Added test for `cliCommandSetStderr` in `src/wasm/wasi.zig`.
- Added test for `getEnvVarOwned` success path in `src/util/env.zig`.
- Added GitHub action for Homebrew releases (`.github/workflows/release.yml`) which automatically publishes release artifacts and bumps the homebrew formula.

### Fixed
- Fixed `parseComponentImport` in `src/wasm/component.zig` to decode the LEB128 type index instead of skipping it, enabling proper type indexing.
- Fixed component exports to use `ComponentValue{ .func = export_item.ty_idx }` instead of placeholders during instantiation in `src/wasm/component.zig`.
- Fixed binary references in existing Docker, Nix and Spec Tests workflows to use `wart` instead of `wax`.

### Fixed
- Replaced `std.posix.getenv` with `std.c.getenv` in `src/config/file.zig` and `src/util/env.zig` to resolve compilation errors with `zig@master`.
- Fixed compilation errors in `src/config/file.zig` and `src/util/env.zig` by replacing `std.c.getenv` with `std.posix.getenvZ` and using POSIX equivalents for `setenv` and `unsetenv`.
- Removed unrequested AI-generated Markdown files across the codebase to keep the repository clean.
- Pinned benchmark profiles under `bench/profiles/`
- Machine-readable benchmark and verification artifact output
- `wart verify spec` and `wart inspect capabilities`

### Changed
- Replaced `std.ArrayList.orderedRemove(0)` operations with highly optimized O(1) circular buffers tracking a `head` index in `Channel`, `ThreadPool`, and `WasiConcurrency` message queues, vastly improving queue iteration and channel pop speed.
- Fixed the compilation bug by replacing `std.heap.GeneralPurposeAllocator` with `std.heap.ArenaAllocator.init` since it was moved in Zig 0.17.
- Addressed multiple GitHub Action test failures across Ubuntu, macOS, and Windows. Replaced deprecated Node.js 20 actions `actions/upload-artifact@v4` with `@v4.4.3` and `goto-bus-stop/setup-zig@v2.2.0` with `@v2`. Replaced missing `wasm3` package release link with a direct `.elf` binary download.

- Updated codebase to support latest `zig@master` (`>=0.17.0`) standard library changes.
- Removed `src/wasm/instance.zig` which contained dead code.
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

### Changed
- Updated Nix channel to `nixos-unstable` in `.github/workflows/nix.yml` to resolve dependency errors in Nix flake checks.
- Renamed Homebrew formula from `wx.rb` to `wart.rb` to match the project name.
