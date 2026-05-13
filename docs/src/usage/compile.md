# Compiling to Native

## Basic Compilation

```bash
wart compile module.wasm -o output_binary
```

## Optimization Levels

```bash
wart compile module.wasm -O debug      # Debug builds
wart compile module.wasm -O fast       # Fast compilation
wart compile module.wasm -O aggressive # Maximum optimization (default)
```

## Cross-Compilation

Specify target architecture:

```bash
wart compile module.wasm --target x86_64
wart compile module.wasm --target aarch64
```

## Supported Hosts

AOT compilation supports:
- Linux (x86_64, aarch64)
- macOS (x86_64, aarch64)
- Windows (x86_64)

## How It Works

1. WASM module is parsed and validated
2. Functions are compiled to native code
3. Runtime support code is linked
4. Executable is generated

## Limitations

- Non-portable: compiled code runs only on target architecture
- Some dynamic features may have overhead
- Initial compilation time vs runtime tradeoff
