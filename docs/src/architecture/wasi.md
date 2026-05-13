# WASI Support

wart implements multiple WASI versions:

## Preview 1 (Legacy)

The original WASI interface with file descriptors:

```zig
const WASI = @import("wasm/wasi.zig");
```

Supported syscalls:
- `fd_read`, `fd_write`, `fd_seek`, `fd_close`
- `path_open`, `path_create_directory`
- `args_get`, `args_sizes_get`
- `environ_get`, `environ_sizes_get`
- `proc_exit`

## Preview 2 (Component Model)

Component-based WASI:

```zig
const Preview2 = @import("wasm/wasi/preview2.zig");
```

Interfaces:
- `wasi:cli/environment`
- `wasi:cli/exit`
- `wasi:io/streams`
- `wasi:filesystem/types`

## Preview 3 (Experimental)

Latest WASI development:

```zig
const Preview3 = @import("wasm/wasi3.zig");
```

## WASIX Extensions

Extended WASI with additional syscalls:

```zig
const WASIX = @import("wasm/wasix.zig");
```

## Preopened Directories

Current directory is preopened by default:

```zig
// Default: fd 3 maps to "."
try runtime.setupWASI(&[_][:0]u8{"program_name"});
```

## Threading

Experimental threading support:

```zig
const threads = @import("wasm/threads.zig");
```
