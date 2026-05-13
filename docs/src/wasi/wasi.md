# WASI Versions

wart supports multiple WASI specification versions:

| Version | Status | Description |
|---------|--------|-------------|
| Preview 1 | Stable | Original WASI with fd-based APIs |
| Preview 2 | Partial | Component-model based |
| Preview 3 | Experimental | Latest development version |
| WASIX | Partial | Extended WASI APIs |

## Version Detection

wart auto-detects WASI version from module imports:

```bash
# Preview 1 module
wart preview1_module.wasm

# Component (Preview 2+)
wart component.wasm
```

## Implementation Files

| File | Purpose |
|------|---------|
| `src/wasm/wasi.zig` | Preview 1 implementation |
| `src/wasm/wasi2.zig` | Preview 2 support |
| `src/wasm/wasi3.zig` | Preview 3 support |
| `src/wasm/wasix.zig` | WASIX extensions |
| `src/wasm/wasi/` | Sub-modules (io, cli, sockets, etc.) |
