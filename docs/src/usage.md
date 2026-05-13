# Usage

## Global Flags

These flags apply to all commands:

| Flag | Description |
|------|-------------|
| `-d, --debug` | Enable debug output |
| `-j, --jit` | Enable JIT compilation (experimental) |
| `-a, --aot` | Enable AOT compilation |
| `-w, --wat` | Treat input as WAT format |
| `--no-validate` | Skip module validation |
| `--color` | Force color output |
| `--no-color` | Disable color output |
| `-V, --verbose` | Set verbosity level |

## Commands

### `wart run` (default)

Run a WebAssembly module:

```bash
wart run module.wasm [args...]
wart module.wasm [args...]  # shorthand
```

### `wart inspect`

Inspect module structure:

```bash
wart inspect module.wasm
wart inspect capabilities   # Show runtime capabilities
```

### `wart compile`

Compile WASM to native executable:

```bash
wart compile module.wasm -o output
wart compile module.wasm --target x86_64
```

### `wart bench`

Run benchmarks:

```bash
wart bench                    # Run benchmark suite
wart bench module.wasm        # Benchmark a specific module
wart bench run --profile core-universal
```

### `wart shell` / `wart repl` / `wart sh`

Interactive REPL:

```bash
wart shell
wart shell module.wasm  # Preload a module
wart repl module.wat    # Alias
wart sh module.c        # Alias
```

### `wart verify`

Run spec verification:

```bash
wart verify --profile all
```

### `wart config`

Manage configuration:

```bash
wart config list
wart config init
wart config get key
wart config set key value
wart config set key=value
```

Wart stores user config at:
- Unix/macOS: `~/.config/wart/config.toml`
- Windows: `%APPDATA%\\wart\\config.toml`

### `wart init`

Initialize a new project:

```bash
wart init [path]
wart init --template library
wart init --template application
```

### `wart completion`

Generate shell completions:

```bash
wart completion bash > ~/.local/share/bash-completion/completions/wart
wart completion zsh > ~/.zsh/completions/_wart
wart completion fish > ~/.config/fish/completions/wart.fish
```
