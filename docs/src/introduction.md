# wart

**wart** is an experimental WebAssembly runtime and CLI written in Zig.

## Overview

wart implements a WebAssembly interpreter with partial WASI support across multiple versions:
- WASI Preview 1 (legacy)
- WASI Preview 2 (component model)
- WASI Preview 3 (experimental)
- WASIX extensions

## Features

- **Fast Interpreter**: Opcode dispatch optimized for performance
- **WASI Support**: Run WASI applications with filesystem, network, and process access
- **AOT Compilation**: Compile WASM to native executables
- **Shell Mode**: Interactive REPL for exploring WASM modules
- **Component Model**: Basic support for WebAssembly components
- **Cross-Platform**: Works on Linux, macOS, and Windows

## Status

This is an experimental runtime. It does **not** claim full conformance to any WASM or WASI specification. Use it for development, testing, and experimentation.

## License

MIT License
