# wart

Experimental WebAssembly runtime and CLI written in Zig.

## Status

This repository contains an interpreter, CLI, benchmark harness, and partial implementations for WASI Preview 1, Preview 2, Preview 3, and WASIX-related modules. It does not currently claim full conformance with the WebAssembly proposals, WASI component model, or WASIX, and benchmark results must be measured locally instead of inferred from checked-in reports.

## Build

```bash
zig build
zig build run -- examples/simple.wasm
zig build test
```

Nix builds are also expected to work:

```bash
nix build
nix build .#debug
nix build .#small
```

## Benchmarking

Use the repository benchmark entry points to compare `wart` against any runtimes installed on your machine:

```bash
zig build bench
bash bench.sh
wart bench
wart bench run --profile core-universal --format markdown --output bench/results
```

`bench.sh` builds `wart`, detects available runtimes, runs shared workloads, and records machine-generated results under `bench/results/` when `hyperfine` is installed. The benchmark scripts do not assume `wart` wins; they report measured timings.

## Verification

Pinned suite and benchmark metadata now live in the repository so claims can be tied to explicit artifacts instead of checked-in summaries:

```bash
bash scripts/fetch-spec-suites.sh
wart verify spec --profile all --format markdown --output artifacts/spec
wart inspect capabilities --format json
```

`wart verify spec` currently reports unsupported upstream runner integrations explicitly rather than pretending the runtime is already conformant.

## Repository Layout

- `src/` contains the CLI, runtime, and WASI-related modules.
- `test/` contains smoke tests and runtime unit tests.
- `examples/` contains small fixtures and sample workloads.
- `bench/` contains benchmark inputs and harnesses.

## Scope

The long-term goal is broader WebAssembly, WASI, and WASIX coverage, but that work is still incomplete. Treat this repository as an in-progress runtime rather than a finished conformance target.
