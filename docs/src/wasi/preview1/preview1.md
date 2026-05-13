# WASI Preview 1

The original WASI specification with file descriptor-based APIs.

## Supported Syscalls

### File Operations

| Syscall | Status |
|---------|--------|
| `fd_read` | ✅ |
| `fd_write` | ✅ |
| `fd_seek` | ✅ |
| `fd_close` | ✅ |
| `fd_stat` | ✅ |
| `fd_pread` | ✅ |
| `fd_pwrite` | ✅ |

### Path Operations

| Syscall | Status |
|---------|--------|
| `path_open` | ✅ |
| `path_create_directory` | ✅ |
| `path_remove_directory` | ✅ |
| `path_unlink_file` | ✅ |
| `path_rename` | ✅ |
| `path_filestat_get` | ✅ |

### Process Operations

| Syscall | Status |
|---------|--------|
| `proc_exit` | ✅ |
| `proc_raise` | ✅ |
| `args_get` | ✅ |
| `args_sizes_get` | ✅ |
| `environ_get` | ✅ |
| `environ_sizes_get` | ✅ |

### Sockets (Partial)

| Syscall | Status |
|---------|--------|
| `sock_open` | ⚠️ Partial |
| `sock_bind` | ⚠️ Partial |
| `sock_connect` | ⚠️ Partial |
| `sock_listen` | ⚠️ Partial |
| `sock_accept` | ⚠️ Partial |

### Clock

| Syscall | Status |
|---------|--------|
| `clock_time_get` | ✅ |
| `clock_res_get` | ✅ |

## Usage

```bash
# Run a Preview 1 module
wart module.wasm

# With arguments
wart echo.wasm "hello world"
```
