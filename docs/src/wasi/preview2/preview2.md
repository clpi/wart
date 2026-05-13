# WASI Preview 2

WASI Preview 2 uses the component model with typed interfaces.

## Component Model

Preview 2 modules are WebAssembly components rather than core modules:

```bash
# Run a component
wart component.wasm
```

## Supported Interfaces

### `wasi:cli/environment`

Access to environment variables and arguments.

### `wasi:cli/exit`

Program termination.

### `wasi:io/streams`

Input/output streams.

### `wasi:filesystem/types`

Filesystem operations through typed handles.

### `wasi:sockets/tcp-tcp-sockets`

TCP networking.

## Implementation

```zig
const Preview2 = @import("wasm/wasi/preview2.zig").Preview2;
```

## Component Detection

wart detects components by the magic number:

```
0x00 0x61 0x73 0x6D 0x0D 0x00 0x01 0x00
```

## Layer 1 Support

Basic Layer 1 components with WASI Preview 2 are supported:

```zig
const ComponentLayer1 = @import("wasm/component_parser_layer1.zig");
var parser = ComponentLayer1.ComponentLayer1Parser.init(allocator, io, bytes);
try parser.parse();
```

## Limitations

- Partial implementation of all interfaces
- Some async operations not supported
- Memory management limited
