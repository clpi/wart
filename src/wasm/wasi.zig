const std = @import("std");
const wasm = std.wasm;
// const cwd = std.os.defaultWasiCwd;
// const fstat = std.os.fstat_wasi;
const fmt = @import("../util/fmt.zig");
const Io = std.Io;
const Threaded = Io.Threaded;
const Color = fmt.Color;
const Runtime = @import("runtime.zig");
const Module = @import("module.zig");
const Value = Runtime.Value;
const Streams = @import("wasi/io.zig").Streams;
const CLI = @import("wasi/cli.zig").CLI;
const WasiHttp = @import("wasi/http.zig").WasiHttp;
const WasiNn = @import("wasi/nn.zig").WasiNn;
const Sockets = @import("wasi/sockets.zig");
const Poll = @import("wasi/poll.zig");
const wasi_os = std.os.wasi;
const WASI = @This();

// WASI Versions
pub const Preview1 = @import("wasi/preview1.zig").Preview1;
pub const Preview2 = @import("wasi/preview2.zig").Preview2;

allocator: std.mem.Allocator,
io: std.Io,
args: [][:0]u8,
env: [][:0]u8,
stdout_buffer: std.ArrayList(u8),
debug: bool = false,
// Preopened directories (file descriptors 3+)
preopens: std.ArrayList(Preopen),
// Open file descriptors (fd 4+, after preopens)
open_files: std.ArrayList(OpenFile),
next_fd: i32 = 4,
io_streams: Streams,
stdin_stream: ?Streams.InputStreamHandle = null,
stdout_stream: ?Streams.OutputStreamHandle = null,
stderr_stream: ?Streams.OutputStreamHandle = null,
cli: CLI,
http: *WasiHttp,
nn: *WasiNn,
thread_pool: ?*@import("threads.zig").ThreadPool = null,
// WASI Preview 2: Sockets and Poll
socket_manager: Sockets.SocketManager,
poll_manager: Poll.PollManager,

const LOG_PREFIX = Color.dim ++ "[" ++ Color.bright_green ++ "wart" ++ Color.reset ++ Color.dim ++ "] ";

inline fn logInfo(comptime fmt_str: []const u8, args: anytype) void {
    std.log.info(LOG_PREFIX ++ fmt_str, args);
}

inline fn logDebug(self: *WASI, comptime fmt_str: []const u8, args: anytype) void {
    if (!self.debug) return;
    std.log.debug(LOG_PREFIX ++ fmt_str, args);
}

inline fn logDebugGlobal(comptime fmt_str: []const u8, args: anytype) void {
    std.log.debug(LOG_PREFIX ++ fmt_str, args);
}

inline fn logError(comptime fmt_str: []const u8, args: anytype) void {
    std.log.err(LOG_PREFIX ++ fmt_str, args);
}

inline fn logWarn(comptime fmt_str: []const u8, args: anytype) void {
    std.log.warn(LOG_PREFIX ++ fmt_str, args);
}

const Preopen = struct {
    fd: i32,
    path: []const u8,
};

const OpenFile = struct {
    fd: i32,
    file: std.Io.File,
    path: []const u8,
    position: u64 = 0, // Current file position for seeking
};

pub fn init(allocator: std.mem.Allocator, io: std.Io, args: [][:0]u8, env: [][:0]u8) !WASI {
    // Pre-allocate preopens with expected capacity (most modules only use cwd)
    var preopens = std.ArrayList(Preopen).empty;
    errdefer preopens.deinit(allocator);
    try preopens.ensureTotalCapacity(allocator, 4);
    try preopens.append(allocator, .{ .fd = 3, .path = "." });

    // Lazy-init stream manager - only create handles, don't allocate buffers
    var stream_manager = try Streams.init(allocator, io);
    errdefer stream_manager.deinit();

    const stdin_handle = try stream_manager.addInputFile(std.Io.File.stdin(), .{ .close_on_drop = false });
    const stdout_handle = try stream_manager.addOutputFile(std.Io.File.stdout(), .{ .close_on_drop = false });
    const stderr_handle = try stream_manager.addOutputFile(std.Io.File.stderr(), .{ .close_on_drop = false });
    const http = try WasiHttp.init(allocator);
    errdefer http.deinit();
    const nn = try WasiNn.init(allocator);
    errdefer nn.deinit();

    var wasi = WASI{
        .allocator = allocator,
        .io = io,
        .args = args,
        .env = env,
        // Lazy allocation - most WASM programs don't buffer much output
        .stdout_buffer = std.ArrayList(u8).empty,
        .debug = false,
        .preopens = preopens,
        .open_files = std.ArrayList(OpenFile).empty,
        .next_fd = 4,
        .io_streams = stream_manager,
        .stdin_stream = stdin_handle,
        .stdout_stream = stdout_handle,
        .stderr_stream = stderr_handle,
        .cli = undefined,
        .http = http,
        .nn = nn,
        .socket_manager = try Sockets.SocketManager.init(allocator),
        .poll_manager = try Poll.PollManager.init(allocator),
    };

    wasi.cli = try CLI.init(allocator, &wasi.io_streams);

    return wasi;
}

pub fn deinit(self: *WASI) void {
    self.stdout_buffer.deinit(self.allocator);
    self.preopens.deinit(self.allocator);
    // Close all open files
    for (self.open_files.items) |open_file| {
        open_file.file.close(self.io);
        self.allocator.free(open_file.path);
    }
    self.open_files.deinit(self.allocator);
    // Free copied environment strings
    for (self.env) |env_var| {
        self.allocator.free(env_var);
    }
    if (self.env.len > 0) {
        self.allocator.free(self.env);
    }
    self.http.deinit();
    self.nn.deinit();
    self.cli.deinit();
    self.io_streams.deinit();
    self.socket_manager.deinit();
    self.poll_manager.deinit();
}

/// Initialize the WASM module with WASI imports
pub fn setupModule(self: *WASI, _: *Runtime, module: *Module) !void {
    // Setup memory for args
    if (module.memory == null) {
        var has_wasi_import = false;
        for (module.imports.items) |import| {
            if (std.mem.startsWith(u8, import.module, "wasi_") or
                std.mem.eql(u8, import.module, "wasi_snapshot_preview1"))
            {
                has_wasi_import = true;
                break;
            }
        }
        if (!has_wasi_import) return;
        logError("No memory section in module", .{});
        return error.NoMemory;
    }

    // Avoid pre-populating argv in linear memory here to prevent clobbering
    // the guest's data segment. The guest will call args_sizes_get and
    // args_get; we implement those to write into guest-provided pointers.
    // Expose runtime thread pool if available
    // (runtime currently unused)

    logInfo("WASI ready (memory size: {d} bytes)", .{module.memory.?.len});
    _ = self; // silence unused warnings in some Zig versions
}

pub fn streams(self: *WASI) *Streams {
    return &self.io_streams;
}

pub fn stdinStream(self: *WASI) ?Streams.InputStreamHandle {
    return self.stdin_stream;
}

pub fn stdoutStream(self: *WASI) ?Streams.OutputStreamHandle {
    return self.stdout_stream;
}

pub fn stderrStream(self: *WASI) ?Streams.OutputStreamHandle {
    return self.stderr_stream;
}

pub fn cliManager(self: *WASI) *CLI {
    return &self.cli;
}

pub fn cliCreateCommand(self: *WASI, program: []const u8) !CLI.CommandHandle {
    return self.cli.createCommand(program);
}

pub fn cliDropCommand(self: *WASI, handle: CLI.CommandHandle) void {
    self.cli.dropCommand(handle);
}

pub fn cliCommandPushArg(self: *WASI, handle: CLI.CommandHandle, arg: []const u8) !void {
    try self.cli.commandPushArg(handle, arg);
}

pub fn cliCommandClearArgs(self: *WASI, handle: CLI.CommandHandle) !void {
    try self.cli.commandClearArgs(handle);
}

pub fn cliCommandSetCwd(self: *WASI, handle: CLI.CommandHandle, cwd: ?[]const u8) !void {
    try self.cli.commandSetCwd(handle, cwd);
}

pub fn cliCommandSetEnv(self: *WASI, handle: CLI.CommandHandle, key: []const u8, value: []const u8) !void {
    try self.cli.commandSetEnv(handle, key, value);
}

pub fn cliCommandRemoveEnv(self: *WASI, handle: CLI.CommandHandle, key: []const u8) !void {
    try self.cli.commandRemoveEnv(handle, key);
}

pub fn cliCommandSetInheritEnv(self: *WASI, handle: CLI.CommandHandle, inherit: bool) !void {
    try self.cli.commandSetInheritEnv(handle, inherit);
}

pub fn cliCommandSetStdin(self: *WASI, handle: CLI.CommandHandle, binding: CLI.StdinBinding) !void {
    try self.cli.commandSetStdin(handle, binding);
}

pub fn cliCommandSetStdout(self: *WASI, handle: CLI.CommandHandle, binding: CLI.StdoutBinding) !void {
    try self.cli.commandSetStdout(handle, binding);
}

pub fn cliCommandSetStderr(self: *WASI, handle: CLI.CommandHandle, binding: CLI.StdoutBinding) !void {
    try self.cli.commandSetStderr(handle, binding);
}

pub fn cliRun(self: *WASI, handle: CLI.CommandHandle) CLI.RunResult {
    return self.cli.run(handle);
}

inline fn checkedMutSlice(memory: []u8, ptr: i32, len: usize) ?[]u8 {
    if (ptr < 0) return null;
    const start: usize = @intCast(ptr);
    if (start > memory.len) return null;
    if (len > memory.len - start) return null;
    return memory[start .. start + len];
}

inline fn checkedConstSlice(memory: []u8, ptr: i32, len: usize) ?[]const u8 {
    return checkedMutSlice(memory, ptr, len);
}

inline fn writeU32(memory: []u8, ptr: i32, value: u32) bool {
    const dst = checkedMutSlice(memory, ptr, 4) orelse return false;
    const buf: *[4]u8 = @ptrCast(dst.ptr);
    std.mem.writeInt(u32, buf, value, .little);
    return true;
}

fn httpMethodFromCode(code: i32) ?@import("wasi/http.zig").Method {
    return switch (code) {
        0 => .GET,
        1 => .POST,
        2 => .PUT,
        3 => .DELETE,
        4 => .HEAD,
        5 => .OPTIONS,
        6 => .CONNECT,
        7 => .TRACE,
        8 => .PATCH,
        else => null,
    };
}

pub fn wasi_io_stream_read(self: *WASI, stream_handle: u32, buf_ptr: i32, buf_len: u32, nread_ptr: i32, module: *Module) !i32 {
    const memory = module.memory orelse return 21;
    const dst = checkedMutSlice(memory, buf_ptr, @intCast(buf_len)) orelse return 21;
    if (buf_len == 0) {
        if (!writeU32(memory, nread_ptr, 0)) return 21;
        return 0;
    }

    const result = self.io_streams.read(stream_handle, @intCast(buf_len));
    switch (result) {
        .ok => |outcome| {
            defer self.allocator.free(outcome.bytes);
            const copied = @min(dst.len, outcome.bytes.len);
            if (copied > 0) {
                @memcpy(dst[0..copied], outcome.bytes[0..copied]);
            }
            if (!writeU32(memory, nread_ptr, @intCast(copied))) return 21;
            return 0;
        },
        .err => |err| switch (err) {
            .closed => return 8,
            .lastOperationFailed => return 29,
        },
    }
}

pub fn wasi_io_stream_write(self: *WASI, stream_handle: u32, data_ptr: i32, data_len: u32, nwritten_ptr: i32, module: *Module) !i32 {
    const memory = module.memory orelse return 21;
    const src = checkedConstSlice(memory, data_ptr, @intCast(data_len)) orelse return 21;

    const result = self.io_streams.write(stream_handle, src);
    switch (result) {
        .ok => |written| {
            if (!writeU32(memory, nwritten_ptr, @intCast(@min(written, std.math.maxInt(u32))))) return 21;
            return 0;
        },
        .err => |err| switch (err) {
            .closed => return 8,
            .lastOperationFailed => return 29,
        },
    }
}

pub fn wasi_io_stream_flush(self: *WASI, stream_handle: u32) !i32 {
    switch (self.io_streams.flush(stream_handle)) {
        .ok => return 0,
        .err => |err| switch (err) {
            .closed => return 8,
            .lastOperationFailed => return 29,
        },
    }
}

pub fn wasi_io_stream_check_write(self: *WASI, stream_handle: u32, available_ptr: i32, module: *Module) !i32 {
    const memory = module.memory orelse return 21;
    const result = self.io_streams.checkWrite(stream_handle);
    switch (result) {
        .ok => |available| {
            const clipped = @as(u32, @intCast(@min(available, std.math.maxInt(u32))));
            if (!writeU32(memory, available_ptr, clipped)) return 21;
            return 0;
        },
        .err => |err| switch (err) {
            .closed => return 8,
            .lastOperationFailed => return 29,
        },
    }
}

pub fn wasi_http_outgoing_request(self: *WASI, method_code: i32, url_ptr: i32, url_len: i32, request_handle_ptr: i32, module: *Module) !i32 {
    if (url_len < 0) return 28;
    const method = httpMethodFromCode(method_code) orelse return 28;
    const memory = module.memory orelse return 21;
    const url = checkedConstSlice(memory, url_ptr, @intCast(url_len)) orelse return 21;
    const handle = self.http.outgoingRequest(method, url) catch return 28;
    if (!writeU32(memory, request_handle_ptr, handle)) return 21;
    return 0;
}

pub fn wasi_http_outgoing_request_write(self: *WASI, request_handle: i32, data_ptr: i32, data_len: i32, module: *Module) !i32 {
    if (request_handle < 0 or data_len < 0) return 28;
    const memory = module.memory orelse return 21;
    const data = checkedConstSlice(memory, data_ptr, @intCast(data_len)) orelse return 21;
    self.http.outgoingRequestWrite(@intCast(request_handle), data) catch return 28;
    return 0;
}

pub fn wasi_http_outgoing_request_send(self: *WASI, request_handle: i32, response_handle_ptr: i32, module: *Module) !i32 {
    if (request_handle < 0) return 28;
    const memory = module.memory orelse return 21;
    const response_handle = self.http.outgoingRequestSend(@intCast(request_handle)) catch return 28;
    if (!writeU32(memory, response_handle_ptr, response_handle)) return 21;
    return 0;
}

pub fn wasi_http_incoming_response_status(self: *WASI, response_handle: i32, status_ptr: i32, module: *Module) !i32 {
    if (response_handle < 0) return 28;
    const memory = module.memory orelse return 21;
    const status = self.http.incomingResponseStatus(@intCast(response_handle)) catch return 28;
    if (!writeU32(memory, status_ptr, status)) return 21;
    return 0;
}

pub fn wasi_http_incoming_response_read(self: *WASI, response_handle: i32, buf_ptr: i32, buf_len: i32, nread_ptr: i32, module: *Module) !i32 {
    if (response_handle < 0 or buf_len < 0) return 28;
    const memory = module.memory orelse return 21;
    const dst = checkedMutSlice(memory, buf_ptr, @intCast(buf_len)) orelse return 21;
    const copied = self.http.incomingResponseRead(@intCast(response_handle), dst) catch return 28;
    if (!writeU32(memory, nread_ptr, @intCast(copied))) return 21;
    return 0;
}

pub fn wasi_nn_load(self: *WASI, model_ptr: i32, model_len: i32, model_handle_ptr: i32, module: *Module) !i32 {
    if (model_len < 0) return 28;
    const memory = module.memory orelse return 21;
    const blob = checkedConstSlice(memory, model_ptr, @intCast(model_len)) orelse return 21;
    const handle = self.nn.loadModel(blob) catch return 28;
    if (!writeU32(memory, model_handle_ptr, handle)) return 21;
    return 0;
}

pub fn wasi_nn_init_execution_context(self: *WASI, model_handle: i32, context_ptr: i32, module: *Module) !i32 {
    if (model_handle < 0) return 28;
    const memory = module.memory orelse return 21;
    const handle = self.nn.initExecutionContext(@intCast(model_handle)) catch return 28;
    if (!writeU32(memory, context_ptr, handle)) return 21;
    return 0;
}

pub fn wasi_nn_set_input(self: *WASI, context_handle: i32, index: i32, data_ptr: i32, data_len: i32, module: *Module) !i32 {
    if (context_handle < 0 or index < 0 or data_len < 0) return 28;
    const memory = module.memory orelse return 21;
    const data = checkedConstSlice(memory, data_ptr, @intCast(data_len)) orelse return 21;
    self.nn.setInput(@intCast(context_handle), @intCast(index), data) catch return 28;
    return 0;
}

pub fn wasi_nn_compute(self: *WASI, context_handle: i32) !i32 {
    if (context_handle < 0) return 28;
    self.nn.compute(@intCast(context_handle)) catch return 28;
    return 0;
}

pub fn wasi_nn_get_output(self: *WASI, context_handle: i32, index: i32, out_ptr: i32, out_len: i32, bytes_written_ptr: i32, module: *Module) !i32 {
    if (context_handle < 0 or index < 0 or out_len < 0) return 28;
    const memory = module.memory orelse return 21;
    const dst = checkedMutSlice(memory, out_ptr, @intCast(out_len)) orelse return 21;
    const written = self.nn.getOutput(@intCast(context_handle), @intCast(index), dst) catch return 28;
    if (!writeU32(memory, bytes_written_ptr, @intCast(written))) return 21;
    return 0;
}

/// Write data to a file descriptor - supports stdout, stderr, and opened files
pub fn fd_write(self: *WASI, fd: i32, iovs_ptr: i32, iovs_len: u32, written_ptr: i32, module: *Module) !i32 {
    if (module.memory) |memory| {
        var total_written: u32 = 0;

        // Check if the iovs_ptr is valid
        if (iovs_ptr < 0 or @as(usize, @intCast(iovs_ptr)) + (@as(usize, @intCast(iovs_len)) * 8) > memory.len) {
            return 21; // EFAULT
        }

        // For stdout/stderr, use direct posix write for unbuffered output
        if (fd == 1 or fd == 2) {
            const posix_fd: std.posix.fd_t = if (fd == 1) std.posix.STDOUT_FILENO else std.posix.STDERR_FILENO;

            if (self.debug) {
                logDebug(self, "fd_write: iovs_len={d}", .{iovs_len});
            }
            for (0..@as(usize, @intCast(iovs_len))) |i| {
                const iov_base_offset: usize = @as(usize, @intCast(iovs_ptr)) + (i * 8);
                const buf_ptr = std.mem.readInt(u32, memory[iov_base_offset..][0..4], .little);
                const buf_len = std.mem.readInt(u32, memory[iov_base_offset + 4 ..][0..4], .little);

                if (self.debug) {
                    logDebug(self, "  iov[{d}] ptr={d} len={d}", .{ i, buf_ptr, buf_len });
                }

                if (buf_len == 0) continue;
                if (@as(usize, @intCast(buf_ptr)) + buf_len > memory.len) return 21;

                const original_len: usize = buf_len;
                var buffer = memory[buf_ptr .. buf_ptr + buf_len];

                // Drop trailing NULs from stdout/stderr output while still
                // reporting the full length back to the guest. This keeps C
                // stdio happy (no partial writes) without emitting spurious
                // \0 characters.
                while (buffer.len > 0 and buffer[buffer.len - 1] == 0) {
                    buffer = buffer[0 .. buffer.len - 1];
                }
                if (self.debug) {
                    const last_byte: u8 = if (buffer.len > 0) buffer[buffer.len - 1] else 0;
                    logDebug(self, "  iov[{d}] slice_len={d} last={d}", .{ i, buffer.len, last_byte });
                }

                // Use direct posix write for immediate output
                var written: usize = 0;
                while (written < buffer.len) {
                    const result = std.c.write(posix_fd, buffer[written..].ptr, buffer.len - written);
                    if (result < 0) return 29;
                    written += @intCast(result);
                }

                if (self.debug) {
                    try self.stdout_buffer.appendSlice(self.allocator, buffer);
                }
                total_written += @intCast(original_len);
            }
        } else {
            // For opened files, use positional writes with tracked position
            var open_file_ptr: ?*OpenFile = null;
            for (self.open_files.items) |*open_file| {
                if (open_file.fd == fd) {
                    open_file_ptr = open_file;
                    break;
                }
            }

            const open_file = open_file_ptr orelse return 8; // EBADF

            for (0..@as(usize, @intCast(iovs_len))) |i| {
                const iov_base_offset: usize = @as(usize, @intCast(iovs_ptr)) + (i * 8);
                const buf_ptr = std.mem.readInt(u32, memory[iov_base_offset..][0..4], .little);
                const buf_len = std.mem.readInt(u32, memory[iov_base_offset + 4 ..][0..4], .little);

                if (buf_len == 0) continue;
                if (@as(usize, @intCast(buf_ptr)) + buf_len > memory.len) return 21;

                const buffer = memory[buf_ptr .. buf_ptr + buf_len];

                // Write at current position using positional write
                open_file.file.writePositionalAll(self.io, buffer, open_file.position) catch return 29;

                // Update tracked position
                open_file.position += buf_len;
                total_written += buf_len;
            }
        }

        // Write the number of bytes written to written_ptr
        if (written_ptr >= 0 and @as(usize, @intCast(written_ptr)) + 4 <= memory.len) {
            std.mem.writeInt(u32, memory[@intCast(written_ptr)..][0..4], total_written, .little);
            if (self.debug) {
                logDebug(self, "  Wrote total_written={d} to written_ptr={d}", .{ total_written, written_ptr });
            }
        }

        if (self.debug) {
            logDebug(self, "\nWASI fd_write result: {d}", .{0});
        }

        return 0; // Success
    } else {
        return 21; // EFAULT - No memory available
    }
}

/// Seek within a file descriptor - supports opened files
pub fn fd_seek(self: *WASI, fd: i32, offset: i64, whence: i32, new_offset_ptr: i32, module: *Module) !i32 {
    if (self.debug) {
        logDebug(self, "\nWASI fd_seek: fd={d}, offset={d}, whence={d}, new_offset_ptr={d}", .{ fd, offset, whence, new_offset_ptr });
    }

    if (module.memory) |memory| {
        // stdin/stdout/stderr - return success with position 0 (no-op seek for compatibility)
        if (fd >= 0 and fd <= 2) {
            if (new_offset_ptr >= 0 and @as(usize, @intCast(new_offset_ptr)) + 8 <= memory.len) {
                std.mem.writeInt(u64, memory[@intCast(new_offset_ptr)..][0..8], 0, .little);
            }
            return 0; // Success (no-op)
        }

        // Find the file in open_files
        var open_file_ptr: ?*OpenFile = null;
        for (self.open_files.items) |*open_file| {
            if (open_file.fd == fd) {
                open_file_ptr = open_file;
                break;
            }
        }

        const open_file = open_file_ptr orelse return 8; // EBADF

        // Perform the seek based on whence
        // WASI whence: 0 = SET, 1 = CUR, 2 = END
        const new_pos: u64 = switch (whence) {
            0 => blk: { // SEEK_SET
                if (offset < 0) return 22; // EINVAL
                break :blk @intCast(offset);
            },
            1 => blk: { // SEEK_CUR
                const current: i64 = @intCast(open_file.position);
                const new: i64 = current + offset;
                if (new < 0) return 22; // EINVAL
                break :blk @intCast(new);
            },
            2 => blk: { // SEEK_END
                const stat = open_file.file.stat(self.io) catch return 29;
                const new: i64 = @as(i64, @intCast(stat.size)) + offset;
                if (new < 0) return 22; // EINVAL
                break :blk @intCast(new);
            },
            else => return 22, // EINVAL
        };

        // Update the tracked position
        open_file.position = new_pos;

        // Write the new offset to memory
        if (new_offset_ptr >= 0 and @as(usize, @intCast(new_offset_ptr)) + 8 <= memory.len) {
            std.mem.writeInt(u64, memory[@intCast(new_offset_ptr)..][0..8], new_pos, .little);
        }

        if (self.debug) {
            logDebug(self, "  Seek result: {d}", .{new_pos});
        }

        return 0; // Success
    } else {
        return -1; // No memory available
    }
}

/// Helper function to safely resolve paths and prevent path traversal
fn resolveSafePath(self: *WASI, dirfd: i32, path: []const u8, out_buf: []u8) ![:0]const u8 {
    // Find base directory path for dirfd
    var base_path: []const u8 = ".";
    if (dirfd >= 3) {
        var found = false;
        for (self.preopens.items) |preopen| {
            if (preopen.fd == dirfd) {
                base_path = preopen.path;
                found = true;
                break;
            }
        }
        if (!found) {
            // Check open_files if it's a directory
            for (self.open_files.items) |open_file| {
                if (open_file.fd == dirfd) {
                    base_path = open_file.path;
                    break;
                }
            }
        }
    }

    // Security: Check for absolute paths
    if (std.fs.path.isAbsolute(path)) {
        return error.AccessDenied;
    }

    // Security: Path normalization and traversal prevention
    // We check that the path does not escape the base_path by tracking directory depth.
    var depth: usize = 0;
    var it = std.mem.tokenizeAny(u8, path, "/\\");
    while (it.next()) |component| {
        if (std.mem.eql(u8, component, "..")) {
            if (depth == 0) return error.AccessDenied;
            depth -= 1;
        } else if (std.mem.eql(u8, component, ".")) {
            continue;
        } else {
            depth += 1;
        }
    }

    return std.fmt.bufPrintZ(out_buf, "{s}/{s}", .{ base_path, path }) catch error.NameTooLong;
}

/// Setup arguments in WASM memory
pub fn setupArgs(self: *WASI, module: *Module) !struct { argc: i32, argv_ptr: i32 } {
    if (module.memory == null) {
        return error.NoMemory;
    }
    logInfo("Setting up args: args.len={d}", .{self.args.len});
    for (self.args, 0..) |arg, i| {
        logInfo("  arg[{d}] = \"{s}\"", .{ i, arg });
    }

    logInfo("Memory size: {d} bytes", .{module.memory.?.len});

    // Calculate total size needed for strings
    var total_size: usize = 0;
    for (self.args) |arg| {
        total_size += arg.len + 1; // +1 for null terminator
    }

    // Calculate size needed for argv array
    const argv_array_size = self.args.len * 4; // 4 bytes per pointer

    // Find a suitable location in memory for argv array and strings
    // Start at offset 1024 to avoid interfering with any low memory usage
    const argv_ptr: usize = 1024;
    const strings_ptr: usize = argv_ptr + argv_array_size;

    logInfo("  argv_ptr = {d}, strings_ptr = {d}, total_strings_size = {d}", .{ argv_ptr, strings_ptr, total_size });

    // Check if we have enough memory
    if (strings_ptr + total_size > module.memory.?.len) {
        logInfo("Error: Not enough memory for args: need {d} bytes", .{strings_ptr + total_size});
        return error.OutOfMemory;
    }

    var current_string_ptr: usize = strings_ptr;

    // Write argument strings and their pointers
    for (self.args, 0..) |arg, i| {
        // Write pointer to string in argv array
        const argv_entry_ptr = argv_ptr + (i * 4);
        std.mem.writeInt(u32, module.memory.?[argv_entry_ptr..][0..4], @intCast(current_string_ptr), .little);

        logInfo("  Writing arg[{d}]=\"{s}\" at memory[{d}], pointer at memory[{d}]={d}", .{ i, arg, current_string_ptr, argv_entry_ptr, current_string_ptr });

        // Write string data
        @memcpy(module.memory.?[current_string_ptr..][0..arg.len], arg);
        module.memory.?[current_string_ptr + arg.len] = 0; // Null terminator

        current_string_ptr += arg.len + 1;
    }

    logInfo("Arguments setup completed: argc={d}, argv_ptr={d}", .{ self.args.len, argv_ptr });

    return .{
        .argc = @intCast(self.args.len),
        .argv_ptr = @intCast(argv_ptr),
    };
}

/// Get environment variables count
pub fn environ_sizes_get(self: *WASI, environ_count_ptr: i32, environ_buf_size_ptr: i32, module: *Module) !i32 {
    if (module.memory) |memory| {
        // Write environ count
        if (environ_count_ptr >= 0 and @as(usize, @intCast(environ_count_ptr)) + 4 <= memory.len) {
            if (self.env.len > std.math.maxInt(u32)) return -1;
            std.mem.writeInt(u32, memory[@intCast(environ_count_ptr)..][0..4], @as(u32, @intCast(self.env.len)), .little);
        }

        // Calculate total size needed for all environment variables (including null terminators)
        var total_size: usize = 0;
        for (self.env) |env_var| {
            const add = env_var.len + 1;
            if (total_size > std.math.maxInt(u32) - add) return -1;
            total_size += add; // +1 for null terminator
        }

        // Write environ_buf_size
        if (environ_buf_size_ptr >= 0 and @as(usize, @intCast(environ_buf_size_ptr)) + 4 <= memory.len) {
            std.mem.writeInt(u32, memory[@intCast(environ_buf_size_ptr)..][0..4], @as(u32, @intCast(total_size)), .little);
        }

        return 0; // Success
    } else {
        return -1; // No memory available
    }
}

/// Get environment variables
pub fn environ_get(self: *WASI, environ_ptr: i32, environ_buf_ptr: i32, module: *Module) !i32 {
    if (module.memory) |memory| {
        var current_buf_ptr: u32 = @intCast(environ_buf_ptr);

        // Check if we have enough memory for the environ array
        const environ_array_size = self.env.len * 4; // 4 bytes per pointer
        if (@as(usize, @intCast(environ_ptr)) + environ_array_size > memory.len) {
            return -1;
        }

        // Calculate total size needed for strings
        var total_size: usize = 0;
        for (self.env) |env_var| {
            total_size += env_var.len + 1; // +1 for null terminator
        }

        // Check if we have enough memory for the strings
        if (@as(usize, @intCast(environ_buf_ptr)) + total_size > memory.len) {
            return -1;
        }

        // For each environment variable
        for (self.env, 0..) |env_var, i| {
            // Write pointer to environment variable string in environ array
            const env_ptr_offset = @as(usize, @intCast(environ_ptr)) + (i * 4);
            std.mem.writeInt(u32, memory[env_ptr_offset..][0..4], current_buf_ptr, .little);

            // Write environment variable string to buffer
            @memcpy(memory[current_buf_ptr..][0..env_var.len], env_var);
            memory[current_buf_ptr + env_var.len] = 0; // Null terminator

            // Update buffer pointer
            current_buf_ptr += @as(u32, @intCast(env_var.len + 1));
        }

        return 0; // Success
    } else {
        return -1; // No memory available
    }
}

/// Get command-line arguments count
pub fn args_sizes_get(self: *WASI, argc_ptr: i32, argv_buf_size_ptr: i32, module: *Module) !i32 {
    // CRITICAL: Check if args is even initialized
    if (self.args.len == 0) {
        std.debug.print("ERROR: args_sizes_get called but self.args is EMPTY! WASI not set up correctly!\n", .{});
        // Return success with 0 args to prevent crash - but this indicates a bug
        if (module.memory) |memory| {
            const argc_addr = @as(usize, @intCast(argc_ptr));
            const buf_size_addr = @as(usize, @intCast(argv_buf_size_ptr));
            if (argc_addr + 4 <= memory.len and buf_size_addr + 4 <= memory.len) {
                std.mem.writeInt(u32, memory[argc_addr..][0..4], 0, .little);
                std.mem.writeInt(u32, memory[buf_size_addr..][0..4], 0, .little);
            }
        }
        return 0;
    }

    if (module.memory) |memory| {
        const argc_value = @as(u32, @intCast(self.args.len));
        var argv_buf_size: u32 = 0;
        for (self.args) |arg| argv_buf_size += @as(u32, @intCast(arg.len + 1));

        // Verify memory bounds and write
        const argc_addr = @as(usize, @intCast(argc_ptr));
        const buf_size_addr = @as(usize, @intCast(argv_buf_size_ptr));

        if (argc_addr + 4 > memory.len or buf_size_addr + 4 > memory.len) {
            logError("args_sizes_get: out of bounds - argc_ptr={d}, buf_ptr={d}, mem_len={d}", .{ argc_ptr, argv_buf_size_ptr, memory.len });
            return 21; // EINVAL
        }

        std.mem.writeInt(u32, memory[argc_addr..][0..4], argc_value, .little);
        std.mem.writeInt(u32, memory[buf_size_addr..][0..4], argv_buf_size, .little);

        if (self.debug) {
            logDebug(self, "args_sizes_get: argc={d}, buf_size={d}", .{ argc_value, argv_buf_size });
            // Log all args for debugging
            for (self.args, 0..) |arg, i| {
                logDebug(self, "  args[{d}] = '{s}' (len={d})", .{ i, arg, arg.len });
            }
        }
        return 0;
    }
    return 21; // EINVAL
}

/// Get command-line arguments
pub fn args_get(self: *WASI, argv_ptr: i32, argv_buf_ptr: i32, module: *Module) !i32 {
    if (module.memory) |memory| {
        var current_buf_ptr: u32 = @intCast(argv_buf_ptr);

        if (self.debug) {
            logDebug(self, "args_get: argv_ptr={d}, argv_buf_ptr={d}", .{ argv_ptr, argv_buf_ptr });
        }

        for (self.args, 0..) |arg, i| {
            const arg_ptr_offset = @as(usize, @intCast(argv_ptr)) + (i * 4);
            if (arg_ptr_offset + 4 > memory.len) {
                logError("args_get: arg pointer {d} out of bounds (memory size {d})", .{ arg_ptr_offset, memory.len });
                return -1;
            }

            std.mem.writeInt(u32, memory[arg_ptr_offset..][0..4], current_buf_ptr, .little);

            if (current_buf_ptr + arg.len + 1 > memory.len) {
                logError("args_get: arg buffer {d} + {d} out of bounds (memory size {d})", .{ current_buf_ptr, arg.len + 1, memory.len });
                return -1;
            }
            @memcpy(memory[current_buf_ptr..][0..arg.len], arg);
            memory[current_buf_ptr + arg.len] = 0;

            if (self.debug) {
                logDebug(self, "  wrote arg[{d}] at buf_ptr={d}: '{s}'", .{ i, current_buf_ptr, arg });
            }

            current_buf_ptr += @as(u32, @intCast(arg.len + 1));
        }

        if (self.debug) {
            logDebug(self, "args_get: wrote {d} args", .{self.args.len});
        }
        return 0;
    }
    return -1;
}

/// Exit the program
pub fn proc_exit(_: *WASI, exit_code: i32) !i32 {
    // proc_exit must terminate - the WASM spec says it never returns
    std.process.exit(@intCast(exit_code));
}

/// Send a signal to the process (proc_raise)
pub fn proc_raise(_: *WASI, sig: i32) !i32 {
    // Signal handling - for now just exit on common signals
    switch (sig) {
        2 => std.process.exit(130), // SIGINT
        3 => std.process.exit(131), // SIGQUIT
        9 => std.process.exit(137), // SIGKILL
        15 => std.process.exit(143), // SIGTERM
        else => return 0, // Ignore other signals
    }
}

// ============================================================================
// WASIX Extensions - Advanced Features Beyond WASI Preview 1
// ============================================================================

/// Fork the current process (WASIX extension)
pub fn proc_fork(self: *WASI, pid_ptr: i32, module: *Module) !i32 {
    _ = self;
    if (module.memory) |memory| {
        if (pid_ptr < 0 or @as(usize, @intCast(pid_ptr)) + 4 > memory.len) return 28;
        // Fork semantics don't map cleanly to WASM - would require full instance duplication
        std.mem.writeInt(i32, memory[@intCast(pid_ptr)..][0..4], -1, .little);
        return 52; // ENOSYS - Not implemented
    }
    return 28; // EINVAL
}

/// Execute a new program (WASIX extension)
pub fn proc_exec(self: *WASI, path_ptr: i32, path_len: i32, module: *Module) !i32 {
    _ = self;
    _ = path_ptr;
    _ = path_len;
    _ = module;
    // exec() requires loading/executing different WASM module
    return 52; // ENOSYS
}

/// Create a pipe (WASIX extension)
pub fn fd_pipe(self: *WASI, ro_fd_ptr: i32, ri_fd_ptr: i32, module: *Module) !i32 {
    _ = self;
    if (module.memory) |memory| {
        if (ro_fd_ptr < 0 or ri_fd_ptr < 0) return 28;
        if (@as(usize, @intCast(ro_fd_ptr)) + 4 > memory.len or
            @as(usize, @intCast(ri_fd_ptr)) + 4 > memory.len) return 28;

        const pipe_fds = std.posix.pipe() catch return 29;
        std.mem.writeInt(i32, memory[@intCast(ro_fd_ptr)..][0..4], @intCast(pipe_fds[0]), .little);
        std.mem.writeInt(i32, memory[@intCast(ri_fd_ptr)..][0..4], @intCast(pipe_fds[1]), .little);
        return 0;
    }
    return 28;
}

/// Get the resolution of a clock (clock_res_get)
pub fn clock_res_get(_: *WASI, clock_id: i32, resolution_ptr: i32, module: *Module) !i32 {
    if (module.memory) |memory| {
        // Return nanosecond resolution (1ns = 1)
        const resolution: u64 = 1;

        if (resolution_ptr >= 0 and @as(usize, @intCast(resolution_ptr)) + 8 <= memory.len) {
            std.mem.writeInt(u64, memory[@intCast(resolution_ptr)..][0..8], resolution, .little);
        }

        _ = clock_id; // Ignore clock_id for now
        return 0; // Success
    } else {
        return -1; // No memory available
    }
}

/// Get the time value of a clock (clock_time_get)
pub fn clock_time_get(_: *WASI, clock_id: i32, precision: i64, time_ptr: i32, module: *Module) !i32 {
    if (module.memory) |memory| {
        // Get current time in nanoseconds
        const timestamp: isize = @intCast(@import("../util/time.zig").nanoTimestamp());

        if (time_ptr >= 0 and @as(usize, @intCast(time_ptr)) + 8 <= memory.len) {
            std.mem.writeInt(u64, memory[@intCast(time_ptr)..][0..8], @intCast(timestamp), .little);
        }

        _ = clock_id; // Ignore clock_id for now
        _ = precision; // Ignore precision for now
        return 0; // Success
    } else {
        return -1; // No memory available
    }
}

/// Close a file descriptor - properly closes opened files
pub fn fd_close(self: *WASI, fd: i32) !i32 {
    // stdin/stdout/stderr shouldn't be closed
    if (fd >= 0 and fd <= 2) {
        return 0; // Return success but don't actually close
    }

    // Find and close the file in open_files
    for (self.open_files.items, 0..) |open_file, idx| {
        if (open_file.fd == fd) {
            // Close the file
            open_file.file.close(self.io);
            // Free the path
            self.allocator.free(open_file.path);
            // Remove from list
            _ = self.open_files.swapRemove(idx);
            return 0; // Success
        }
    }

    // fd not found - still return success for compatibility
    return 0;
}

/// Read from a file descriptor - supports stdin and opened files
pub fn fd_read(self: *WASI, fd: i32, iovs_ptr: i32, iovs_len: i32, nread_ptr: i32, module: *Module) !i32 {
    if (self.debug) {
        logDebug(self, "\nWASI fd_read: fd={d}, iovs_ptr={d}, iovs_len={d}, nread_ptr={d}", .{ fd, iovs_ptr, iovs_len, nread_ptr });
    }

    if (module.memory) |memory| {
        var total_read: u32 = 0;

        // Check if the iovs_ptr is valid
        if (iovs_ptr < 0 or @as(usize, @intCast(iovs_ptr)) + (@as(usize, @intCast(iovs_len)) * 8) > memory.len) {
            return 21; // EFAULT
        }

        // Get the file and position to read from
        var file_opt: ?std.Io.File = null;
        var position: u64 = 0;
        var open_file_ptr: ?*OpenFile = null;

        // Handle stdin specially - use streaming read, not positional
        if (fd == 0) {
            const stdin_file = std.Io.File.stdin();

            // Read IOVs (I/O vectors)
            for (0..@as(usize, @intCast(iovs_len))) |i| {
                const iov_base_offset: usize = @as(usize, @intCast(iovs_ptr)) + (i * 8);
                const buf_ptr = std.mem.readInt(u32, memory[iov_base_offset..][0..4], .little);
                const buf_len = std.mem.readInt(u32, memory[iov_base_offset + 4 ..][0..4], .little);

                if (buf_len == 0) continue;

                // Check buffer validity
                if (@as(usize, @intCast(buf_ptr)) + buf_len > memory.len) {
                    return 21; // EFAULT
                }

                // Get the buffer to read into
                const buffer = memory[buf_ptr .. buf_ptr + buf_len];

                // Use streaming read for stdin (sequential, not positional)
                const bytes_read = stdin_file.readStreaming(self.io, &.{buffer}) catch return 29; // EIO
                total_read += @intCast(bytes_read);

                // If we got less than requested, stop reading (EOF or partial read)
                if (bytes_read < buf_len) break;
            }
        } else {
            // Find in open_files
            for (self.open_files.items) |*open_file| {
                if (open_file.fd == fd) {
                    file_opt = open_file.file;
                    position = open_file.position;
                    open_file_ptr = open_file;
                    break;
                }
            }

            const file = file_opt orelse return 8; // EBADF

            // Read IOVs (I/O vectors) for regular files
            for (0..@as(usize, @intCast(iovs_len))) |i| {
                const iov_base_offset: usize = @as(usize, @intCast(iovs_ptr)) + (i * 8);
                const buf_ptr = std.mem.readInt(u32, memory[iov_base_offset..][0..4], .little);
                const buf_len = std.mem.readInt(u32, memory[iov_base_offset + 4 ..][0..4], .little);

                if (buf_len == 0) continue;

                // Check buffer validity
                if (@as(usize, @intCast(buf_ptr)) + buf_len > memory.len) {
                    return 21; // EFAULT
                }

                // Get the buffer to read into
                const buffer = memory[buf_ptr .. buf_ptr + buf_len];

                // Read from file using positional read (since we track position manually)
                const bytes_read = file.readPositionalAll(self.io, buffer, position) catch return 29; // EIO
                total_read += @intCast(bytes_read);
                position += bytes_read;

                // If we got less than requested, stop reading (EOF or partial read)
                if (bytes_read < buf_len) break;
            }

            // Update tracked position
            if (open_file_ptr) |ofp| {
                ofp.position = position;
            }
        }

        // Write the number of bytes read to nread_ptr
        if (nread_ptr >= 0 and @as(usize, @intCast(nread_ptr)) + 4 <= memory.len) {
            std.mem.writeInt(u32, memory[@intCast(nread_ptr)..][0..4], total_read, .little);
        }

        if (self.debug) {
            logDebug(self, "  fd_read result: {d} bytes", .{total_read});
        }

        return 0; // Success
    } else {
        return 21; // EFAULT - No memory available
    }
}

/// Get information about a preopened directory (fd_prestat_get)
pub fn fd_prestat_get(self: *WASI, fd: i32, prestat_ptr: i32, module: *Module) !i32 {
    if (self.debug) {
        logDebug(self, "\nWASI fd_prestat_get: fd={d}, prestat_ptr={d}", .{ fd, prestat_ptr });
    }

    if (module.memory) |memory| {
        // Check if this is a preopened directory
        for (self.preopens.items) |preopen| {
            if (preopen.fd == fd) {
                // Write prestat structure:
                // u8: tag (0 for dir)
                // u32: path length
                if (prestat_ptr >= 0 and @as(usize, @intCast(prestat_ptr)) + 8 <= memory.len) {
                    memory[@intCast(prestat_ptr)] = 0; // tag = 0 (dir)
                    std.mem.writeInt(u32, memory[@as(usize, @intCast(prestat_ptr)) + 4 ..][0..4], @as(u32, @intCast(preopen.path.len)), .little);

                    if (self.debug) {
                        logDebug(self, "  Found preopen fd={d}, path_len={d}", .{ fd, preopen.path.len });
                    }
                }
                return 0; // Success
            }
        }

        // Not a preopened directory
        return 8; // EBADF
    } else {
        return -1; // No memory available
    }
}

/// Get the path of a preopened directory (fd_prestat_dir_name)
pub fn fd_prestat_dir_name(self: *WASI, fd: i32, path_ptr: i32, path_len: i32, module: *Module) !i32 {
    if (self.debug) {
        logDebug(self, "\nWASI fd_prestat_dir_name: fd={d}, path_ptr={d}, path_len={d}", .{ fd, path_ptr, path_len });
    }

    if (module.memory) |memory| {
        // Find the preopened directory
        for (self.preopens.items) |preopen| {
            if (preopen.fd == fd) {
                const copy_len = @min(@as(usize, @intCast(path_len)), preopen.path.len);

                if (path_ptr >= 0 and @as(usize, @intCast(path_ptr)) + copy_len <= memory.len) {
                    @memcpy(memory[@intCast(path_ptr)..][0..copy_len], preopen.path[0..copy_len]);

                    if (self.debug) {
                        logDebug(self, "  Copied path: {s}", .{preopen.path});
                    }
                }
                return 0; // Success
            }
        }

        // Not a preopened directory
        return 8; // EBADF
    } else {
        return -1; // No memory available
    }
}

/// Get file descriptor attributes (fd_fdstat_get)
pub fn fd_fdstat_get(self: *WASI, fd: i32, stat_ptr: i32, module: *Module) !i32 {
    if (self.debug) {
        logDebug(self, "fd_fdstat_get: fd={d}, stat_ptr={d}", .{ fd, stat_ptr });
    }

    if (module.memory) |memory| {
        // Write fdstat structure (24 bytes):
        // u8: fs_filetype
        // u16: fs_flags
        // u64: fs_rights_base
        // u64: fs_rights_inheriting

        if (stat_ptr >= 0 and @as(usize, @intCast(stat_ptr)) + 24 <= memory.len) {
            const base: usize = @intCast(stat_ptr);

            // WASI rights bits
            const RIGHT_FD_READ: u64 = 1 << 1;
            const RIGHT_FD_WRITE: u64 = 1 << 6;
            const RIGHT_FD_SYNC: u64 = 1 << 4;
            const RIGHT_FD_FDSTAT_SET_FLAGS: u64 = 1 << 8;

            // Set file type and rights based on fd
            if (fd >= 0 and fd <= 2) {
                // stdin/stdout/stderr - character device (no seek rights)
                memory[base] = 2; // CHARACTER_DEVICE

                // Rights for character devices: read (stdin) or write (stdout/stderr), no seek
                const rights: u64 = if (fd == 0)
                    RIGHT_FD_READ | RIGHT_FD_FDSTAT_SET_FLAGS
                else
                    RIGHT_FD_WRITE | RIGHT_FD_SYNC | RIGHT_FD_FDSTAT_SET_FLAGS;

                std.mem.writeInt(u64, memory[base + 8 ..][0..8], rights, .little);
                std.mem.writeInt(u64, memory[base + 16 ..][0..8], 0, .little);

                if (self.debug) {
                    logDebug(self, "  fd={d} is stdio, filetype=2 (CHARACTER_DEVICE), rights=0x{x}", .{ fd, rights });
                }
            } else {
                // Other fds - regular file or directory with all rights
                memory[base] = 4; // REGULAR_FILE
                std.mem.writeInt(u64, memory[base + 8 ..][0..8], 0xFFFFFFFF, .little);
                std.mem.writeInt(u64, memory[base + 16 ..][0..8], 0xFFFFFFFF, .little);
            }

            // fs_flags (u16 at offset 2)
            std.mem.writeInt(u16, memory[base + 2 ..][0..2], 0, .little);
        }

        return 0; // Success
    } else {
        logError("fd_fdstat_get: no memory available", .{});
        return 21; // EINVAL
    }
}

/// Set file descriptor flags (fd_fdstat_set_flags)
pub fn fd_fdstat_set_flags(_: *WASI, _: i32, _: i32) !i32 {
    // Not implemented yet, return success
    return 0;
}

/// Open a file or directory (path_open)
pub fn path_open(self: *WASI, dirfd: i32, dirflags: i32, path_ptr: i32, path_len: i32, oflags: i32, fs_rights_base: i64, fs_rights_inheriting: i64, fdflags: i32, fd_ptr: i32, module: *Module) !i32 {
    _ = dirflags;
    _ = fs_rights_inheriting;
    _ = fdflags;

    const io = self.io;
    logInfo("dirfd={d}, path_ptr={d}, path_len={d}, oflags=0x{x}, fd_ptr={d}", .{ dirfd, path_ptr, path_len, oflags, fd_ptr });

    if (module.memory) |memory| {
        // Validate path pointer
        if (path_ptr < 0 or @as(usize, @intCast(path_ptr)) + @as(usize, @intCast(path_len)) > memory.len) {
            logWarn("INVALID path pointer", .{});
            return 28; // EINVAL
        }

        const path = memory[@intCast(path_ptr) .. @as(usize, @intCast(path_ptr)) + @as(usize, @intCast(path_len))];
        logInfo("path={s}", .{path});

        // Build full path
        var full_path_buf: [std.posix.PATH_MAX]u8 = undefined;
        const full_path = self.resolveSafePath(dirfd, path, &full_path_buf) catch |err| {
            return switch (err) {
                error.AccessDenied => 2, // EACCES
                error.NameTooLong => 63, // ENAMETOOLONG
                else => 28, // EINVAL
            };
        };

        // Parse oflags - WASI oflags
        // 0x01 = CREAT, 0x02 = DIRECTORY, 0x04 = EXCL, 0x08 = TRUNC
        const should_create = (oflags & 0x01) != 0;
        const should_truncate = (oflags & 0x08) != 0;

        // Determine the correct open mode based on fdflags
        // fdflags: 0x01 = APPEND, 0x02 = DSYNC, 0x04 = NONBLOCK, 0x08 = RSYNC, 0x10 = SYNC
        const want_write = (fs_rights_base & 0x40) != 0; // FD_WRITE right
        const want_read = (fs_rights_base & 0x02) != 0 or !want_write; // FD_READ right or default to read

        // Try to open or create the file
        const file = if (should_create) blk: {
            // Create file if it doesn't exist, or open if it does
            break :blk std.Io.Dir.cwd().createFile(io, full_path, .{
                .truncate = should_truncate,
                .read = want_read,
                .exclusive = (oflags & 0x04) != 0, // EXCL flag
            }) catch |err| {
                logError("createFile failed: {}", .{err});
                return switch (err) {
                    error.FileNotFound => 44, // ENOENT
                    error.AccessDenied => 2, // EACCES
                    error.IsDir => 21, // EISDIR
                    error.NotDir => 54, // ENOTDIR
                    error.PathAlreadyExists => 17, // EEXIST
                    else => 28, // EINVAL
                };
            };
        } else blk: {
            // Just open existing file
            const mode: std.Io.File.OpenMode = if (want_write) .read_write else .read_only;
            break :blk std.Io.Dir.cwd().openFile(io, full_path, .{
                .mode = mode,
            }) catch |err| {
                logError("openFile failed: {}", .{err});
                return switch (err) {
                    error.FileNotFound => 44, // ENOENT
                    error.AccessDenied => 2, // EACCES
                    error.IsDir => 21, // EISDIR
                    error.NotDir => 54, // ENOTDIR
                    else => 28, // EINVAL
                };
            };
        };

        // Allocate new fd and store the file
        const new_fd = self.next_fd;
        self.next_fd += 1;

        const path_copy = try self.allocator.dupe(u8, full_path);
        try self.open_files.append(self.allocator, .{
            .fd = new_fd,
            .file = file,
            .path = path_copy,
        });

        // Write the new fd to memory
        if (fd_ptr >= 0 and @as(usize, @intCast(fd_ptr)) + 4 <= memory.len) {
            std.mem.writeInt(u32, memory[@as(usize, @intCast(fd_ptr))..][0..4], @as(u32, @intCast(new_fd)), .little);
        }

        return 0; // Success
    } else {
        return -1; // No memory available
    }
}

/// Get file or directory metadata (path_filestat_get)
pub fn path_filestat_get(self: *WASI, dirfd: i32, flags: i32, path_ptr: i32, path_len: i32, buf_ptr: i32, module: *Module) !i32 {
    _ = flags; // Flags for following symlinks
    const io = self.io;

    if (module.memory) |memory| {
        // Validate path pointer
        if (path_ptr < 0 or @as(usize, @intCast(path_ptr)) + @as(usize, @intCast(path_len)) > memory.len) {
            return 28; // EINVAL
        }

        const path = memory[@intCast(path_ptr) .. @as(usize, @intCast(path_ptr)) + @as(usize, @intCast(path_len))];

        // Build full path
        var full_path_buf: [std.posix.PATH_MAX]u8 = undefined;
        const full_path = self.resolveSafePath(dirfd, path, &full_path_buf) catch |err| {
            return switch (err) {
                error.AccessDenied => 2, // EACCES
                error.NameTooLong => 63, // ENAMETOOLONG
                else => 28, // EINVAL
            };
        };

        // Get file stats
        const file = std.Io.Dir.cwd().openFile(io, full_path, .{}) catch |err| {
            return switch (err) {
                error.FileNotFound => 44, // ENOENT
                error.AccessDenied => 2, // EACCES
                error.IsDir => {
                    // For directories, try to open as dir
                    var dir = std.Io.Dir.cwd().openDir(io, full_path, .{}) catch return 54; // ENOTDIR
                    defer dir.close(self.io);

                    // Write filestat structure for directory
                    if (buf_ptr >= 0 and @as(usize, @intCast(buf_ptr)) + 64 <= memory.len) {
                        const base_addr: usize = @intCast(buf_ptr);
                        std.mem.writeInt(u64, memory[base_addr..][0..8], 0, .little); // dev
                        std.mem.writeInt(u64, memory[base_addr + 8 ..][0..8], 0, .little); // ino
                        memory[base_addr + 16] = 3; // DIRECTORY
                        std.mem.writeInt(u64, memory[base_addr + 24 ..][0..8], 1, .little); // nlink
                        std.mem.writeInt(u64, memory[base_addr + 32 ..][0..8], 0, .little); // size
                        std.mem.writeInt(u64, memory[base_addr + 40 ..][0..8], 0, .little); // atim
                        std.mem.writeInt(u64, memory[base_addr + 48 ..][0..8], 0, .little); // mtim
                        std.mem.writeInt(u64, memory[base_addr + 56 ..][0..8], 0, .little); // ctim
                    }
                    return 0;
                },
                else => 28, // ENOSYS
            };
        };
        defer file.close(self.io);

        const stat = file.stat(self.io) catch return 28;

        // Write filestat structure (64 bytes)
        if (buf_ptr >= 0 and @as(usize, @intCast(buf_ptr)) + 64 <= memory.len) {
            const base_addr: usize = @intCast(buf_ptr);
            std.mem.writeInt(u64, memory[base_addr..][0..8], 0, .little); // dev
            std.mem.writeInt(u64, memory[base_addr + 8 ..][0..8], stat.inode, .little); // ino
            memory[base_addr + 16] = switch (stat.kind) {
                .file => 4, // REGULAR_FILE
                .directory => 3, // DIRECTORY
                .sym_link => 7, // SYMBOLIC_LINK
                else => 0, // UNKNOWN
            };
            std.mem.writeInt(u64, memory[base_addr + 24 ..][0..8], 1, .little); // nlink
            std.mem.writeInt(u64, memory[base_addr + 32 ..][0..8], stat.size, .little); // size
            std.mem.writeInt(u64, memory[base_addr + 40 ..][0..8], @intCast(stat.atime.?.toNanoseconds()), .little); // atim
            std.mem.writeInt(u64, memory[base_addr + 48 ..][0..8], @intCast(stat.mtime.toNanoseconds()), .little); // mtim
            std.mem.writeInt(u64, memory[base_addr + 56 ..][0..8], @intCast(stat.ctime.toNanoseconds()), .little); // ctim
        }

        return 0; // Success
    } else {
        return -1; // No memory available
    }
}

/// Set file timestamps (path_filestat_set_times)
pub fn path_filestat_set_times(self: *WASI, dirfd: i32, flags: i32, path_ptr: i32, path_len: i32, atim: i64, mtim: i64, fst_flags: i32, module: *Module) !i32 {
    _ = flags; // Flags for following symlinks
    const io = self.io;

    if (fst_flags & 0x03 == 0x03 or fst_flags & 0x0C == 0x0C) {
        return 28; // EINVAL - can't set both NOW and value
    }

    // Get the path from memory
    const path_bytes = blk: {
        if (path_len < 0 or path_ptr < 0) return 28; // EINVAL
        const module_mem = module.memory orelse return 28;
        if (@as(usize, @intCast(path_ptr)) + @as(usize, @intCast(path_len)) > module_mem.len) return 28;
        break :blk module_mem[@intCast(path_ptr) .. @as(usize, @intCast(path_ptr)) + @as(usize, @intCast(path_len))];
    };

    // Build full path
    var full_path_buf: [std.posix.PATH_MAX]u8 = undefined;
    const full_path = self.resolveSafePath(dirfd, path_bytes, &full_path_buf) catch |err| {
        return switch (err) {
            error.AccessDenied => 2, // EACCES
            error.NameTooLong => 63, // ENAMETOOLONG
            else => 28, // EINVAL
        };
    };

    // On platforms that support it, use utimensat
    // For now, we'll use a simpler approach with updateTimes if available
    const file = std.Io.Dir.cwd().openFile(io, full_path, .{ .mode = .read_write }) catch return 44; // ENOENT
    defer file.close(self.io);

    const n = @import("../util/time.zig").nanoTimestamp();
    // Convert nanoseconds to seconds for updateTimes
    const atime_sec: i128 = if (fst_flags & 0x01 != 0) @divFloor(@as(i128, n), 1_000_000_000) else @divFloor(atim, 1_000_000_000);
    const mtime_sec: i128 = if (fst_flags & 0x04 != 0) @divFloor(@as(i128, n), 1_000_000_000) else @divFloor(mtim, 1_000_000_000);

    file.updateTimes(atime_sec, mtime_sec) catch return 29; // EIO
    return 0;
}

/// Remove a directory (path_remove_directory)
pub fn path_remove_directory(self: *WASI, dirfd: i32, path_ptr: i32, path_len: i32, module: *Module) !i32 {
    const io = self.io;
    if (module.memory) |memory| {
        // Validate path pointer
        if (path_ptr < 0 or @as(usize, @intCast(path_ptr)) + @as(usize, @intCast(path_len)) > memory.len) {
            return 28; // EINVAL
        }

        const path = memory[@intCast(path_ptr) .. @as(usize, @intCast(path_ptr)) + @as(usize, @intCast(path_len))];

        // Build full path
        var full_path_buf: [std.posix.PATH_MAX]u8 = undefined;
        const full_path = self.resolveSafePath(dirfd, path, &full_path_buf) catch |err| {
            return switch (err) {
                error.AccessDenied => 2, // EACCES
                error.NameTooLong => 63, // ENAMETOOLONG
                else => 28, // EINVAL
            };
        };

        // Remove the directory
        std.Io.Dir.cwd().deleteDir(io, full_path) catch |err| {
            return switch (err) {
                error.FileNotFound => 44, // ENOENT
                error.AccessDenied => 2, // EACCES
                error.DirNotEmpty => 66, // ENOTEMPTY
                else => 28, // ENOSYS
            };
        };

        return 0; // Success
    } else {
        return -1; // No memory available
    }
}

/// Unlink a file (path_unlink_file)
pub fn path_unlink_file(self: *WASI, dirfd: i32, path_ptr: i32, path_len: i32, module: *Module) !i32 {
    const io = self.io;
    if (module.memory) |memory| {
        // Validate path pointer
        if (path_ptr < 0 or @as(usize, @intCast(path_ptr)) + @as(usize, @intCast(path_len)) > memory.len) {
            return 28; // EINVAL
        }

        const path = memory[@intCast(path_ptr) .. @as(usize, @intCast(path_ptr)) + @as(usize, @intCast(path_len))];

        // Build full path
        var full_path_buf: [std.posix.PATH_MAX]u8 = undefined;
        const full_path = self.resolveSafePath(dirfd, path, &full_path_buf) catch |err| {
            return switch (err) {
                error.AccessDenied => 2, // EACCES
                error.NameTooLong => 63, // ENAMETOOLONG
                else => 28, // EINVAL
            };
        };

        // Delete the file
        std.Io.Dir.cwd().deleteFile(io, full_path) catch |err| {
            return switch (err) {
                error.FileNotFound => 44, // ENOENT
                error.AccessDenied => 2, // EACCES
                error.IsDir => 21, // EISDIR
                else => 28, // ENOSYS
            };
        };

        return 0; // Success
    } else {
        return -1; // No memory available
    }
}

/// Get random bytes (random_get)
pub fn random_get(_: *WASI, buf_ptr: i32, buf_len: i32, module: *Module) !i32 {
    if (module.memory) |memory| {
        if (buf_ptr >= 0 and @as(usize, @intCast(buf_ptr)) + @as(usize, @intCast(buf_len)) <= memory.len) {
            const buffer = memory[@intCast(buf_ptr)..][0..@intCast(buf_len)];

            // Fill with random bytes
            var prng = std.Random.DefaultPrng.init(@intCast(@import("../util/time.zig").nanoTimestamp()));
            prng.random().bytes(buffer);
        }

        return 0; // Success
    } else {
        return -1; // No memory available
    }
}

/// Poll for events (poll_oneoff)
pub fn poll_oneoff(_: *WASI, in_ptr: i32, out_ptr: i32, nsubscriptions: i32, nevents_ptr: i32, module: *Module) !i32 {
    _ = in_ptr;
    _ = out_ptr;
    _ = nsubscriptions;

    if (module.memory) |memory| {
        // For now, immediately return with 0 events
        if (nevents_ptr >= 0 and @as(usize, @intCast(nevents_ptr)) + 4 <= memory.len) {
            std.mem.writeInt(u32, memory[@intCast(nevents_ptr)..][0..4], 0, .little);
        }

        return 0; // Success
    } else {
        return -1; // No memory available
    }
}

/// WASI-threads: thread-spawn (proposed)
pub fn thread_spawn(self: *WASI, start_arg: i32, stack_top_ptr: i32, module: *Module) !i32 {
    _ = module;
    _ = stack_top_ptr;
    if (self.thread_pool == null) return -1;
    const func_idx: u32 = @bitCast(start_arg);
    const tid = try self.thread_pool.?.spawnThread(func_idx, &[_]Value{});
    return @as(i32, @bitCast(tid));
}

/// WASI-threads: thread-join (proposed)
pub fn thread_join(self: *WASI, tid: i32) !i32 {
    if (self.thread_pool == null) return -1;
    try self.thread_pool.?.joinThread(@bitCast(@as(u32, @bitCast(tid))));
    return 0;
}

/// WASI-threads: thread-exit (proposed)
pub fn thread_exit(self: *WASI, exit_code: i32) !i32 {
    _ = self;
    _ = exit_code;
    // In a real implementation, this would terminate the current thread
    // For single-threaded mode, we just return success
    return 0;
}

/// WASI-threads: thread-self (proposed) - returns current thread ID
pub fn thread_self(self: *WASI) !i32 {
    if (self.thread_pool == null) return 0; // Main thread
    // Return main thread ID (0)
    return 0;
}

/// WASI-threads: thread-yield (proposed) - yield to other threads
pub fn thread_yield(self: *WASI) !i32 {
    _ = self;
    std.Thread.yield() catch {};
    return 0;
}

/// WASI-threads: thread-mutex-init (proposed)
pub fn thread_mutex_init(self: *WASI) !i32 {
    _ = self;
    // Return a valid mutex handle (simplified)
    return 1;
}

/// WASI-threads: thread-mutex-lock (proposed)
pub fn thread_mutex_lock(self: *WASI, mutex: i32) !i32 {
    _ = self;
    _ = mutex;
    return 0;
}

/// WASI-threads: thread-mutex-unlock (proposed)
pub fn thread_mutex_unlock(self: *WASI, mutex: i32) !i32 {
    _ = self;
    _ = mutex;
    return 0;
}

/// WASI-threads: thread-cond-init (proposed)
pub fn thread_cond_init(self: *WASI) !i32 {
    _ = self;
    return 1;
}

/// WASI-threads: thread-cond-signal (proposed)
pub fn thread_cond_signal(self: *WASI, cond: i32) !i32 {
    _ = self;
    _ = cond;
    return 0;
}

/// WASI-threads: thread-cond-wait (proposed)
pub fn thread_cond_wait(self: *WASI, cond: i32, mutex: i32) !i32 {
    _ = self;
    _ = cond;
    _ = mutex;
    std.Thread.yield() catch {};
    return 0;
}

/// Yield the processor (sched_yield)
pub fn sched_yield(_: *WASI) !i32 {
    // Give up CPU time slice
    std.Thread.yield() catch {};
    return 0; // Success
}

/// WASI Preview 2: Open a TCP socket
pub fn sock_open_tcp(
    self: *WASI,
    address_family: u8, // 0 = IPv4, 1 = IPv6
    ret_fd: i32,
    module: *Module,
) !i32 {
    const family: Sockets.AddressFamily = if (address_family == 0) .ipv4 else .ipv6;

    const socket = Sockets.TcpSocket.init(self.allocator, family) catch return 28; // EINVAL

    const handle = self.socket_manager.addTcpSocket(socket) catch return 12; // ENOMEM

    // Write handle to memory
    const memory = module.memory orelse return 21; // EISDIR (no memory)
    if (ret_fd < 0 or @as(usize, @intCast(ret_fd)) + 4 > memory.len) return 21;

    std.mem.writeInt(u32, memory[@intCast(ret_fd)..][0..4], @intCast(handle), .little);
    return 0; // SUCCESS
}

/// WASI Preview 2: Connect TCP socket
pub fn sock_connect(
    self: *WASI,
    sock_handle: u32,
    addr_ptr: i32,
    module: *Module,
) !i32 {
    const socket = self.socket_manager.getTcpSocket(sock_handle) orelse return 8; // EBADF

    const memory = module.memory orelse return 21;
    if (addr_ptr < 0 or @as(usize, @intCast(addr_ptr)) + 18 > memory.len) return 14; // EFAULT

    // Parse address: [family:u8][port:u16][addr:16 bytes max]
    const addr_bytes = memory[@intCast(addr_ptr)..];
    const family_byte = addr_bytes[0];
    const port = std.mem.readInt(u16, addr_bytes[1..3], .little);

    const address = if (family_byte == 0) blk: {
        var octets: [4]u8 = undefined;
        @memcpy(&octets, addr_bytes[3..7]);
        break :blk Sockets.IpSocketAddress{
            .address = .{ .ipv4 = octets },
            .port = port,
        };
    } else blk: {
        var octets: [16]u8 = undefined;
        @memcpy(&octets, addr_bytes[3..19]);
        break :blk Sockets.IpSocketAddress{
            .address = .{ .ipv6 = octets },
            .port = port,
        };
    };

    socket.connect(address) catch |err| {
        return switch (err) {
            error.ConnectionRefused => 61, // ECONNREFUSED
            error.NetworkUnreachable => 51, // ENETUNREACH
            error.Timeout => 60, // ETIMEDOUT
            error.AddressInUse => 48, // EADDRINUSE
            else => 5, // EIO
        };
    };

    return 0;
}

/// WASI Preview 2: Bind and listen on TCP socket
pub fn sock_listen(
    self: *WASI,
    sock_handle: u32,
    addr_ptr: i32,
    backlog: u32,
    module: *Module,
) !i32 {
    const socket = self.socket_manager.getTcpSocket(sock_handle) orelse return 8;

    const memory = module.memory orelse return 21;
    if (addr_ptr < 0 or @as(usize, @intCast(addr_ptr)) + 18 > memory.len) return 14;

    const addr_bytes = memory[@intCast(addr_ptr)..];
    const family_byte = addr_bytes[0];
    const port = std.mem.readInt(u16, addr_bytes[1..3], .little);

    const address = if (family_byte == 0) blk: {
        var octets: [4]u8 = undefined;
        @memcpy(&octets, addr_bytes[3..7]);
        break :blk Sockets.IpSocketAddress{
            .address = .{ .ipv4 = octets },
            .port = port,
        };
    } else blk: {
        var octets: [16]u8 = undefined;
        @memcpy(&octets, addr_bytes[3..19]);
        break :blk Sockets.IpSocketAddress{
            .address = .{ .ipv6 = octets },
            .port = port,
        };
    };

    socket.bind(address) catch return 48; // EADDRINUSE
    socket.listen(@intCast(backlog)) catch return 5;

    return 0;
}

/// WASI Preview 2: Accept connection
pub fn sock_accept(
    self: *WASI,
    sock_handle: u32,
    ret_fd: i32,
    module: *Module,
) !i32 {
    const socket = self.socket_manager.getTcpSocket(sock_handle) orelse return 8;

    const new_socket = socket.accept() catch return 5;

    const new_handle = self.socket_manager.addTcpSocket(new_socket) catch return 12;

    const memory = module.memory orelse return 21;
    if (ret_fd < 0 or @as(usize, @intCast(ret_fd)) + 4 > memory.len) return 21;

    std.mem.writeInt(u32, memory[@intCast(ret_fd)..][0..4], @intCast(new_handle), .little);
    return 0;
}

/// WASI Preview 2: Send data on socket
pub fn sock_send(
    self: *WASI,
    sock_handle: u32,
    buf_ptr: i32,
    buf_len: u32,
    ret_sent: i32,
    module: *Module,
) !i32 {
    const socket = self.socket_manager.getTcpSocket(sock_handle) orelse return 8;

    const memory = module.memory orelse return 21;
    if (buf_ptr < 0 or @as(usize, @intCast(buf_ptr)) + buf_len > memory.len) return 14;

    const data = memory[@intCast(buf_ptr)..][0..buf_len];

    const sent = socket.send(data) catch return 5;

    if (ret_sent >= 0 and @as(usize, @intCast(ret_sent)) + 4 <= memory.len) {
        std.mem.writeInt(u32, memory[@intCast(ret_sent)..][0..4], @intCast(sent), .little);
    }

    return 0;
}

/// WASI Preview 2: Receive data from socket
pub fn sock_recv(
    self: *WASI,
    sock_handle: u32,
    buf_ptr: i32,
    buf_len: u32,
    ret_received: i32,
    module: *Module,
) !i32 {
    const socket = self.socket_manager.getTcpSocket(sock_handle) orelse return 8;

    const memory = module.memory orelse return 21;
    if (buf_ptr < 0 or @as(usize, @intCast(buf_ptr)) + buf_len > memory.len) return 14;

    const buffer = memory[@intCast(buf_ptr)..][0..buf_len];

    const received = socket.receive(buffer) catch return 5;

    if (ret_received >= 0 and @as(usize, @intCast(ret_received)) + 4 <= memory.len) {
        std.mem.writeInt(u32, memory[@intCast(ret_received)..][0..4], @intCast(received), .little);
    }

    return 0;
}

/// WASI Preview 2: Shutdown socket
pub fn sock_shutdown(self: *WASI, sock_handle: u32, how: u8) !i32 {
    const socket = self.socket_manager.getTcpSocket(sock_handle) orelse return 8;

    const shutdown_how: Sockets.ShutdownHow = switch (how) {
        0 => .recv,
        1 => .send,
        2 => .both,
        else => return 28, // EINVAL
    };

    socket.shutdown(shutdown_how) catch return 5;
    return 0;
}

/// Advise the system about how a file will be used (fd_advise)
pub fn fd_advise(_: *WASI, _: i32, _: i64, _: i64, _: i32) !i32 {
    // Not implemented, return success
    return 0;
}

/// Force file data and metadata to disk (fd_sync)
pub fn fd_sync(self: *WASI, fd: i32) !i32 {
    if (fd < 0 or fd >= self.open_files.items.len) return 8; // ERRNO_BADF
    const file_info = &self.open_files.items[@intCast(fd)];
    file_info.file.sync(self.io) catch return 29; // ERRNO_IO
    return 0;
}

/// Force file data to disk, metadata optional (fd_datasync)
pub fn fd_datasync(self: *WASI, fd: i32) !i32 {
    if (fd < 0 or fd >= self.open_files.items.len) return 8; // ERRNO_BADF
    const file_info = &self.open_files.items[@intCast(fd)];
    // Zig's std.Io.File doesn't have datasync, use sync
    file_info.file.sync(self.io) catch return 29; // ERRNO_IO
    return 0;
}

/// Set file descriptor rights (fd_fdstat_set_rights)
pub fn fd_fdstat_set_rights(_: *WASI, _: i32, _: i64, _: i64) !i32 {

    // Rights management is capability-based, currently a no-op
    // Return success as we don't enforce fine-grained rights
    return 0;
}

/// Get file attributes (fd_filestat_get)
pub fn fd_filestat_get(_: *WASI, fd: i32, buf_ptr: i32, module: *Module) !i32 {
    if (module.memory) |memory| {
        // Write filestat structure (64 bytes):
        // u64: dev, u64: ino, u8: filetype, u64: nlink
        // u64: size, u64: atim, u64: mtim, u64: ctim

        if (buf_ptr >= 0 and @as(usize, @intCast(buf_ptr)) + 64 <= memory.len) {
            const base: usize = @intCast(buf_ptr);

            // dev (u64 at offset 0)
            std.mem.writeInt(u64, memory[base..][0..8], 0, .little);

            // ino (u64 at offset 8)
            std.mem.writeInt(u64, memory[base + 8 ..][0..8], 0, .little);

            // filetype (u8 at offset 16)
            if (fd >= 0 and fd <= 2) {
                memory[base + 16] = 2; // CHARACTER_DEVICE
            } else {
                memory[base + 16] = 3; // DIRECTORY
            }

            // nlink (u64 at offset 24)
            std.mem.writeInt(u64, memory[base + 24 ..][0..8], 1, .little);

            // size (u64 at offset 32)
            std.mem.writeInt(u64, memory[base + 32 ..][0..8], 0, .little);

            // atim (u64 at offset 40)
            std.mem.writeInt(u64, memory[base + 40 ..][0..8], 0, .little);

            // mtim (u64 at offset 48)
            std.mem.writeInt(u64, memory[base + 48 ..][0..8], 0, .little);

            // ctim (u64 at offset 56)
            std.mem.writeInt(u64, memory[base + 56 ..][0..8], 0, .little);
        }

        return 0; // Success
    } else {
        return -1; // No memory available
    }
}

/// Set file size (fd_filestat_set_size)
pub fn fd_filestat_set_size(self: *WASI, fd: i32, size: i64) !i32 {
    // Find the file descriptor
    const io = self.io;
    for (self.open_files.items) |open_file| {
        if (open_file.fd == fd) {
            // Set the file size (truncate or extend)
            open_file.file.setLength(io, @intCast(size)) catch |err| {
                return switch (err) {
                    error.AccessDenied => 2, // EACCES
                    error.InputOutput => 5, // EIO
                    error.FileBusy => 26, // ETXTBSY
                    else => 28, // ENOSYS
                };
            };
            return 0; // Success
        }
    }

    return 8; // EBADF - bad file descriptor
}

/// Set file timestamps (fd_filestat_set_times)
pub fn fd_filestat_set_times(self: *WASI, fd: i32, atim: i64, mtim: i64, fst_flags: i32) !i32 {
    _ = atim;
    _ = mtim;
    _ = fst_flags;

    // Find the file descriptor
    for (self.open_files.items) |open_file| {
        if (open_file.fd == fd) {
            // Note: Zig's std.Io.File doesn't directly support setting timestamps
            // This would require platform-specific syscalls
            // For now, we'll return success without actually setting times
            return 0; // Success (no-op)
        }
    }

    return 8; // EBADF - bad file descriptor
}

/// Read from a file descriptor with offset (fd_pread)
pub fn fd_pread(self: *WASI, fd: i32, iovs_ptr: i32, iovs_len: i32, offset: i64, nread_ptr: i32, module: *Module) !i32 {
    const io = self.io;
    if (module.memory) |memory| {
        // Find the file descriptor
        var file: ?std.Io.File = null;
        for (self.open_files.items) |open_file| {
            if (open_file.fd == fd) {
                file = open_file.file;
                break;
            }
        }

        if (file == null) {
            return 8; // EBADF - bad file descriptor
        }

        var total_read: u32 = 0;

        // Check if the iovs_ptr is valid
        if (iovs_ptr < 0 or @as(usize, @intCast(iovs_ptr)) + (@as(usize, @intCast(iovs_len)) * 8) > memory.len) {
            return 28; // EINVAL
        }

        // Read IOVs (I/O vectors)
        for (0..@as(usize, @intCast(iovs_len))) |i| {
            const iov_base_offset: usize = @as(usize, @intCast(iovs_ptr)) + (i * 8);

            const buf_ptr = std.mem.readInt(u32, memory[iov_base_offset..][0..4], .little);
            const buf_len = std.mem.readInt(u32, memory[iov_base_offset + 4 ..][0..4], .little);

            if (buf_len == 0) continue;

            // Check buffer validity
            if (@as(usize, @intCast(buf_ptr)) + buf_len > memory.len) {
                return 28; // EINVAL
            }

            const buffer = memory[buf_ptr .. buf_ptr + buf_len];

            // Read from file at offset
            const bytes_read = file.?.readPositionalAll(io, buffer, @intCast(offset + total_read)) catch |err| {
                return switch (err) {
                    error.AccessDenied => 2, // EACCES
                    error.InputOutput => 5, // EIO
                    else => 28, // ENOSYS
                };
            };
            total_read += @intCast(bytes_read);

            if (bytes_read < buf_len) break; // EOF or short read
        }

        // Write the number of bytes read to nread_ptr
        if (nread_ptr >= 0 and @as(usize, @intCast(nread_ptr)) + 4 <= memory.len) {
            std.mem.writeInt(u32, memory[@intCast(nread_ptr)..][0..4], total_read, .little);
        }

        return 0; // Success
    } else {
        return -1; // No memory available
    }
}

/// Write to a file descriptor with offset (fd_pwrite)
pub fn fd_pwrite(self: *WASI, fd: i32, iovs_ptr: i32, iovs_len: i32, offset: i64, nwritten_ptr: i32, module: *Module) !i32 {
    const io = self.io;
    if (module.memory) |memory| {
        // Find the file descriptor
        var file: ?std.Io.File = null;
        for (self.open_files.items) |open_file| {
            if (open_file.fd == fd) {
                file = open_file.file;
                break;
            }
        }

        if (file == null) {
            return 8; // EBADF - bad file descriptor
        }

        var total_written: u32 = 0;

        // Check if the iovs_ptr is valid
        if (iovs_ptr < 0 or @as(usize, @intCast(iovs_ptr)) + (@as(usize, @intCast(iovs_len)) * 8) > memory.len) {
            return 28; // EINVAL
        }

        // Write IOVs (I/O vectors)
        for (0..@as(usize, @intCast(iovs_len))) |i| {
            const iov_base_offset: usize = @as(usize, @intCast(iovs_ptr)) + (i * 8);

            const buf_ptr = std.mem.readInt(u32, memory[iov_base_offset..][0..4], .little);
            const buf_len = std.mem.readInt(u32, memory[iov_base_offset + 4 ..][0..4], .little);

            if (buf_len == 0) continue;

            // Check buffer validity
            if (@as(usize, @intCast(buf_ptr)) + buf_len > memory.len) {
                return 28; // EINVAL
            }

            const buffer = memory[buf_ptr .. buf_ptr + buf_len];

            // Write to file at offset
            _ = file.?.writePositionalAll(io, buffer, @intCast(offset + total_written)) catch |err| {
                return switch (err) {
                    error.AccessDenied => 2, // EACCES
                    error.InputOutput => 5, // EIO
                    error.NoSpaceLeft => 55, // ENOSPC
                    else => 28, // ENOSYS
                };
            };

            total_written += buf_len;
        }

        // Write the number of bytes written to nwritten_ptr
        if (nwritten_ptr >= 0 and @as(usize, @intCast(nwritten_ptr)) + 4 <= memory.len) {
            std.mem.writeInt(u32, memory[@intCast(nwritten_ptr)..][0..4], total_written, .little);
        }

        return 0; // Success
    } else {
        return -1; // No memory available
    }
}

/// Read directory entries (fd_readdir)
pub fn fd_readdir(self: *WASI, fd: i32, buf_ptr: i32, buf_len: i32, cookie: i64, bufused_ptr: i32, module: *Module) !i32 {
    const io = self.io;
    if (module.memory) |memory| {
        // Find the file descriptor (should be a directory)
        var dir_path: ?[]const u8 = null;

        // Check if it's a preopened directory
        for (self.preopens.items) |preopen| {
            if (preopen.fd == fd) {
                dir_path = preopen.path;
                break;
            }
        }

        if (dir_path == null) {
            return 8; // EBADF - not a directory or not found
        }

        // Open the directory
        var dir = std.Io.Dir.cwd().openDir(io, dir_path.?, .{ .iterate = true }) catch {
            return 8; // EBADF
        };
        defer dir.close(io);

        var buffer = memory[@intCast(buf_ptr) .. @as(usize, @intCast(buf_ptr)) + @as(usize, @intCast(buf_len))];
        var buf_pos: usize = 0;
        var next_cookie: u64 = @intCast(cookie);

        // Skip entries based on cookie
        var iter = dir.iterate();
        var entry_count: u64 = 0;
        while (try iter.next(io)) |entry| {
            entry_count += 1;
            if (entry_count <= cookie) continue;

            // Calculate entry size: 24 bytes header + name_len + 1 (for alignment?)
            const name_len = entry.name.len;
            const entry_size = 24 + name_len;
            if (buf_pos + entry_size > buffer.len) break; // Buffer full

            // Write dirent structure
            // d_next
            std.mem.writeInt(u64, buffer[buf_pos..][0..8], next_cookie + 1, .little);
            buf_pos += 8;
            // d_ino (use 0 for now)
            std.mem.writeInt(u64, buffer[buf_pos..][0..8], 0, .little);
            buf_pos += 8;
            // d_namlen
            std.mem.writeInt(u32, buffer[buf_pos..][0..4], @intCast(name_len), .little);
            buf_pos += 4;
            // d_type
            const d_type: u8 = switch (entry.kind) {
                .file => 4, // REGULAR_FILE
                .directory => 3, // DIRECTORY
                .sym_link => 7, // SYMBOLIC_LINK
                else => 0, // UNKNOWN
            };
            buffer[buf_pos] = d_type;
            buf_pos += 1;
            // Padding to align to 8 bytes? WASI dirent is packed
            buf_pos += 3; // padding to 24 bytes

            // Write name
            @memcpy(buffer[buf_pos..][0..name_len], entry.name);
            buf_pos += name_len;

            next_cookie += 1;
        }

        // Write bytes used
        if (bufused_ptr >= 0 and @as(usize, @intCast(bufused_ptr)) + 4 <= memory.len) {
            std.mem.writeInt(u32, memory[@intCast(bufused_ptr)..][0..4], @intCast(buf_pos), .little);
        }

        return 0; // Success
    } else {
        return -1; // No memory available
    }
}

/// Atomically replace a file descriptor (fd_renumber)
pub fn fd_renumber(self: *WASI, from_fd: i32, to_fd: i32) !i32 {
    const io = self.io;
    // Find and remove the 'to_fd' if it exists
    var to_index: ?usize = null;
    for (self.open_files.items, 0..) |open_file, i| {
        if (open_file.fd == to_fd) {
            to_index = i;
            break;
        }
    }

    if (to_index) |idx| {
        var old_file = self.open_files.orderedRemove(idx);
        old_file.file.close(io);
        self.allocator.free(old_file.path);
    }

    // Find and renumber the 'from_fd'
    for (self.open_files.items) |*open_file| {
        if (open_file.fd == from_fd) {
            open_file.fd = to_fd;
            return 0; // Success
        }
    }

    return 8; // EBADF - from_fd not found
}

/// Return current offset of a file descriptor (fd_tell)
pub fn fd_tell(_: *WASI, fd: i32, offset_ptr: i32, module: *Module) !i32 {
    if (module.memory) |memory| {
        // Always return 0 for current offset
        if (offset_ptr >= 0 and @as(usize, @intCast(offset_ptr)) + 8 <= memory.len) {
            std.mem.writeInt(u64, memory[@intCast(offset_ptr)..][0..8], 0, .little);
        }
        _ = fd;
        return 0; // Success
    } else {
        return -1; // No memory available
    }
}

/// Allocate space in a file (fd_allocate)
pub fn fd_allocate(self: *WASI, fd: i32, offset: i64, len: i64) !i32 {
    const io = self.io;
    // Find the file descriptor
    for (self.open_files.items) |open_file| {
        if (open_file.fd == fd) {
            // Calculate the new required size
            const required_size: u64 = @intCast(offset + len);

            // Get current file size
            const stat = open_file.file.stat(io) catch {
                return 5; // EIO
            };

            // Only extend if needed
            if (required_size > stat.size) {
                open_file.file.setLength(io, required_size) catch |err| {
                    return switch (err) {
                        error.AccessDenied => 2, // EACCES
                        error.InputOutput => 5, // EIO
                        error.FileTooBig => 27, // EFBIG
                        else => 28, // ENOSYS
                    };
                };
            }

            return 0; // Success
        }
    }

    return 8; // EBADF - bad file descriptor
}

/// Create a directory (path_create_directory)
pub fn path_create_directory(self: *WASI, dirfd: i32, path_ptr: i32, path_len: i32, module: *Module) !i32 {
    if (module.memory) |memory| {
        // Validate path pointer
        if (path_ptr < 0 or @as(usize, @intCast(path_ptr)) + @as(usize, @intCast(path_len)) > memory.len) {
            return 28; // EINVAL
        }

        const path = memory[@intCast(path_ptr) .. @as(usize, @intCast(path_ptr)) + @as(usize, @intCast(path_len))];

        // Build full path
        var full_path_buf: [std.posix.PATH_MAX]u8 = undefined;
        const full_path = self.resolveSafePath(dirfd, path, &full_path_buf) catch |err| {
            return switch (err) {
                error.AccessDenied => 2, // EACCES
                error.NameTooLong => 63, // ENAMETOOLONG
                else => 28, // EINVAL
            };
        };

        // Create the directory
        std.Io.Dir.cwd().createDirPath(self.io, full_path) catch |err| {
            return switch (err) {
                error.PathAlreadyExists => 17, // EEXIST
                error.AccessDenied => 2, // EACCES
                error.NotDir => 54, // ENOTDIR
                else => 28, // ENOSYS
            };
        };

        return 0; // Success
    } else {
        return -1; // No memory available
    }
}

/// Create a hard link (path_link)
pub fn path_link(self: *WASI, old_fd: i32, old_flags: i32, old_path_ptr: i32, old_path_len: i32, new_fd: i32, new_path_ptr: i32, new_path_len: i32, module: *Module) !i32 {
    _ = old_flags;

    if (module.memory) |memory| {
        // Validate path pointers
        if (old_path_ptr < 0 or @as(usize, @intCast(old_path_ptr)) + @as(usize, @intCast(old_path_len)) > memory.len) {
            return 28; // EINVAL
        }
        if (new_path_ptr < 0 or @as(usize, @intCast(new_path_ptr)) + @as(usize, @intCast(new_path_len)) > memory.len) {
            return 28; // EINVAL
        }

        const old_path = memory[@intCast(old_path_ptr) .. @as(usize, @intCast(old_path_ptr)) + @as(usize, @intCast(old_path_len))];
        const new_path = memory[@intCast(new_path_ptr) .. @as(usize, @intCast(new_path_ptr)) + @as(usize, @intCast(new_path_len))];

        // Build full paths
        var old_full_path_buf: [std.posix.PATH_MAX]u8 = undefined;
        var new_full_path_buf: [std.posix.PATH_MAX]u8 = undefined;
        const old_full_path: [*:0]const u8 = self.resolveSafePath(old_fd, old_path, &old_full_path_buf) catch return 63;
        const new_full_path: [*:0]const u8 = self.resolveSafePath(new_fd, new_path, &new_full_path_buf) catch return 63;

        // Create hard link
        _ = std.posix.system.link(old_full_path, new_full_path);

        return 0; // Success
    } else {
        return -1; // No memory available
    }
}

/// Read the contents of a symbolic link (path_readlink)
pub fn path_readlink(self: *WASI, dirfd: i32, path_ptr: i32, path_len: i32, buf_ptr: i32, buf_len: i32, bufused_ptr: i32, module: *Module) !i32 {
    if (module.memory) |memory| {
        // Validate path pointer
        if (path_ptr < 0 or @as(usize, @intCast(path_ptr)) + @as(usize, @intCast(path_len)) > memory.len) {
            return 28; // EINVAL
        }
        if (buf_ptr < 0 or @as(usize, @intCast(buf_ptr)) + @as(usize, @intCast(buf_len)) > memory.len) {
            return 28; // EINVAL
        }

        const path = memory[@intCast(path_ptr) .. @as(usize, @intCast(path_ptr)) + @as(usize, @intCast(path_len))];

        // Build full path
        var full_path_buf: [std.posix.PATH_MAX]u8 = undefined;
        const full_path = self.resolveSafePath(dirfd, path, &full_path_buf) catch |err| {
            return switch (err) {
                error.AccessDenied => 2, // EACCES
                error.NameTooLong => 63, // ENAMETOOLONG
                else => 28, // EINVAL
            };
        };

        // Read symlink
        const buffer = memory[@intCast(buf_ptr) .. @as(usize, @intCast(buf_ptr)) + @as(usize, @intCast(buf_len))];
        const target = std.Io.Dir.cwd().readLink(self.io, full_path, buffer) catch |err| {
            return switch (err) {
                error.FileNotFound => 44, // ENOENT
                error.AccessDenied => 2, // EACCES
                error.NotLink => 22, // EINVAL
                else => 28, // ENOSYS
            };
        };

        // Write bytes used
        if (bufused_ptr >= 0 and @as(usize, @intCast(bufused_ptr)) + 4 <= memory.len) {
            std.mem.writeInt(u32, memory[@intCast(bufused_ptr)..][0..4], @intCast(target), .little);
        }

        return 0; // Success
    } else {
        return -1; // No memory available
    }
}

/// Rename a file or directory (path_rename)
pub fn path_rename(self: *WASI, old_fd: i32, old_path_ptr: i32, old_path_len: i32, new_fd: i32, new_path_ptr: i32, new_path_len: i32, module: *Module) !i32 {
    if (module.memory) |memory| {
        // Validate path pointers
        if (old_path_ptr < 0 or @as(usize, @intCast(old_path_ptr)) + @as(usize, @intCast(old_path_len)) > memory.len) {
            return 28; // EINVAL
        }
        if (new_path_ptr < 0 or @as(usize, @intCast(new_path_ptr)) + @as(usize, @intCast(new_path_len)) > memory.len) {
            return 28; // EINVAL
        }

        const old_path = memory[@intCast(old_path_ptr) .. @as(usize, @intCast(old_path_ptr)) + @as(usize, @intCast(old_path_len))];
        const new_path = memory[@intCast(new_path_ptr) .. @as(usize, @intCast(new_path_ptr)) + @as(usize, @intCast(new_path_len))];

        // Build full paths
        var old_full_path_buf: [std.posix.PATH_MAX]u8 = undefined;
        var new_full_path_buf: [std.posix.PATH_MAX]u8 = undefined;
        const old_full_path = self.resolveSafePath(old_fd, old_path, &old_full_path_buf) catch return 63;
        const new_full_path = self.resolveSafePath(new_fd, new_path, &new_full_path_buf) catch return 63;
        const old_dir = std.Io.Dir.openDirAbsolute(self.io, old_full_path, .{}) catch {
            return 44; // ENOENT
        };
        defer old_dir.close(self.io);
        const new_dir = std.Io.Dir.openDirAbsolute(self.io, new_full_path, .{}) catch {
            return 44; // ENOENT
        };
        defer new_dir.close(self.io);

        // Rename file/directory
        std.Io.Dir.rename(old_dir, old_full_path, new_dir, new_full_path, self.io) catch |err| {
            return switch (err) {
                error.FileNotFound => 44, // ENOENT
                error.AccessDenied => 2, // EACCES
                error.NotDir => 54, // ENOTDIR
                else => 28, // ENOSYS
            };
        };

        return 0; // Success
    } else {
        return -1; // No memory available
    }
}

/// Create a symbolic link (path_symlink)
pub fn path_symlink(self: *WASI, old_path_ptr: i32, old_path_len: i32, dirfd: i32, new_path_ptr: i32, new_path_len: i32, module: *Module) !i32 {
    if (module.memory) |memory| {
        // Validate path pointers
        if (old_path_ptr < 0 or @as(usize, @intCast(old_path_ptr)) + @as(usize, @intCast(old_path_len)) > memory.len) {
            return 28; // EINVAL
        }
        if (new_path_ptr < 0 or @as(usize, @intCast(new_path_ptr)) + @as(usize, @intCast(new_path_len)) > memory.len) {
            return 28; // EINVAL
        }

        const old_path = memory[@intCast(old_path_ptr) .. @as(usize, @intCast(old_path_ptr)) + @as(usize, @intCast(old_path_len))];
        const new_path = memory[@intCast(new_path_ptr) .. @as(usize, @intCast(new_path_ptr)) + @as(usize, @intCast(new_path_len))];

        // Build new full path
        var new_full_path_buf: [std.posix.PATH_MAX]u8 = undefined;
        const new_full_path = self.resolveSafePath(dirfd, new_path, &new_full_path_buf) catch |err| {
            return switch (err) {
                error.AccessDenied => 2, // EACCES
                error.NameTooLong => 63, // ENAMETOOLONG
                else => 28, // EINVAL
            };
        };
        // Create symbolic link
        std.Io.Dir.cwd().symLink(self.io, old_path, new_full_path, .{}) catch |err| {
            return switch (err) {
                error.FileNotFound => 44, // ENOENT
                error.AccessDenied => 2, // EACCES
                error.PathAlreadyExists => 17, // EEXIST
                else => 28, // ENOSYS
            };
        };

        return 0; // Success
    } else {
        return -1; // No memory available
    }
}
