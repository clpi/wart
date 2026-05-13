# Contributing to wart

## Getting Started

```bash
git clone https://github.com/clpi/wart.git
cd wart
zig build
zig build test
```

If you use Nix:

```bash
nix build
nix develop
```

## Development Workflow

1. Create a branch for one focused change.
2. Make the smallest coherent change that fixes the issue or improves the code.
3. Run `zig fmt` on modified Zig files.
4. Run `zig build` and `zig build test`.
5. If the change touches benchmarking or conformance, run the relevant harness:

```bash
bash scripts/run-benchmarks.sh --profile core-universal
bash scripts/run-spec-tests.sh --profile all
```

## Runtime And CLI Checks

```bash
./zig-out/bin/wart --help
./zig-out/bin/wart examples/simple.wasm
./zig-out/bin/wart inspect capabilities --format json
```

## Coding Guidelines

- Prefer removing dead code and duplication over adding another compatibility layer.
- Keep production code free of mock behavior unless the command explicitly reports it as unsupported.
- Use `std.wasm` and shared runtime modules instead of duplicating opcode or feature tables.
- Keep comments short and useful.
- Do not add benchmark or feature claims without fresh artifacts that prove them.

## Benchmarks

Use the pinned harness rather than the old ad hoc scripts:

```bash
bash bench.sh
bash bench/run.sh --profile core-universal
bash scripts/run-benchmarks.sh --profile preview1
```

## Pull Requests

- Use short imperative commit messages.
- Describe the motivation and the validation commands you ran.
- Include benchmark or verification artifacts when those results are part of the change.
