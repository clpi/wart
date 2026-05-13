# Contributing

## Getting Started

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests: `zig build test`
5. Format code: `zig fmt src/`
6. Submit a pull request

## Code Guidelines

### Formatting

Always run `zig fmt` before committing:

```bash
zig fmt src/
```

### Architecture

- Use Zig 0.16-era APIs
- Thread `std.Io` explicitly (no global IO)
- Use `std.wasm` enums for opcodes
- Prefer `std.heap.c_allocator` in production code

### Commit Messages

- Use short, imperative summaries
- Include commands you ran for behavior changes

Example:
```
Add support for WASI fd_advise

- Implement fd_advise syscall in wasi.zig
- Add test case in test/wasi_test.zig
- Verified with: zig build test
```

## Testing

Write tests for new functionality:

```zig
test "new feature" {
    const allocator = std.testing.allocator;
    // ...
}
```

Run tests:
```bash
zig build test
```

## Benchmark Changes

If you change performance-sensitive code:

1. Run baseline benchmark: `./b.sh`
2. Make changes
3. Run benchmark again
4. Compare results in `bench/results/`

Do not claim performance improvements without benchmark artifacts.

## Pull Request Process

1. Ensure tests pass
2. Update documentation if needed
3. Add changelog entry for significant changes
4. Request review

## Code of Conduct

Be respectful and inclusive. Report issues to maintainers.
