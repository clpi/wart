# WASI Preview 3

Experimental support for the latest WASI development version.

## Status

Preview 3 is under active development and may change. wart provides basic support.

## Implementation

```zig
const wasi3 = @import("wasm/wasi3.zig");
```

## Key Differences from Preview 2

- Revised API surface
- Enhanced async support
- Improved error handling

## Usage

```bash
wart preview3_module.wasm
```

## Supported Features

- Basic CLI operations
- Standard streams
- Process exit

## Limitations

- Work in progress
- APIs may change
- Not recommended for production
