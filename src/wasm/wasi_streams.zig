/// WASI Streams Implementation (WASI Preview 2)
///
/// Implements the wasi-io interface for streaming I/O operations.
/// This provides asynchronous, pollable streams for reading and writing data.
///
/// Interfaces:
/// - wasi:io/streams@0.2.0
/// - wasi:io/poll@0.2.0
///
/// References:
/// - https://github.com/WebAssembly/wasi-io
const std = @import("std");
const std_io = @import("std/io.zig");
const Allocator = std.mem.Allocator;
const Log = @import("../util/fmt.zig").Log;

pub const Error = error{
    Closed,
    LastOperationFailed,
    InvalidHandle,
    OutOfMemory,
    WouldBlock,
};

/// Stream error codes (from WASI spec)
pub const StreamError = enum(u8) {
    closed,
    last_operation_failed,
};

/// Pollable handle (resource)
pub const Pollable = struct {
    handle: u32,
    ready: bool = false,
};

/// Input stream (readable)
pub const InputStream = struct {
    handle: u32,
    buffer: std.ArrayList(u8),
    closed: bool = false,
    nonblocking: bool = true,

    pub fn init(allocator: Allocator, handle: u32) InputStream {
        return InputStream{
            .handle = handle,
            .buffer = std.ArrayList(u8).init(allocator),
            .closed = false,
        };
    }

    pub fn deinit(self: *InputStream) void {
        self.buffer.deinit();
    }
};

/// Output stream (writable)
pub const OutputStream = struct {
    handle: u32,
    buffer: std.ArrayList(u8),
    closed: bool = false,
    nonblocking: bool = true,

    pub fn init(allocator: Allocator, handle: u32) OutputStream {
        return OutputStream{
            .handle = handle,
            .buffer = std.ArrayList(u8).init(allocator),
            .closed = false,
        };
    }

    pub fn deinit(self: *OutputStream) void {
        self.buffer.deinit();
    }
};

/// Streams manager
pub const StreamsManager = struct {
    const Self = @This();

    allocator: Allocator,
    io: std.Io,
    input_streams: std.AutoHashMap(u32, InputStream),
    output_streams: std.AutoHashMap(u32, OutputStream),
    pollables: std.AutoHashMap(u32, Pollable),

    next_handle: u32 = 100, // Start at 100 to avoid conflicts

    // Standard streams
    stdin_handle: u32 = 0,
    stdout_handle: u32 = 1,
    stderr_handle: u32 = 2,

    pub fn init(allocator: Allocator, io: std.Io) !*Self {
        const manager = try allocator.create(Self);
        manager.* = Self{
            .allocator = allocator,
            .io = io,
            .input_streams = std.AutoHashMap(u32, InputStream).init(allocator),
            .output_streams = std.AutoHashMap(u32, OutputStream).init(allocator),
            .pollables = std.AutoHashMap(u32, Pollable).init(allocator),
        };

        // Create standard streams
        try manager.input_streams.put(0, InputStream.init(allocator, 0));
        try manager.output_streams.put(1, OutputStream.init(allocator, 1));
        try manager.output_streams.put(2, OutputStream.init(allocator, 2));

        return manager;
    }

    pub fn deinit(self: *Self) void {
        var it = self.input_streams.valueIterator();
        while (it.next()) |stream| {
            stream.deinit();
        }
        self.input_streams.deinit();

        var out_it = self.output_streams.valueIterator();
        while (out_it.next()) |stream| {
            stream.deinit();
        }
        self.output_streams.deinit();

        self.pollables.deinit();
        self.allocator.destroy(self);
    }

    /// Create a new input stream
    pub fn createInputStream(self: *Self) !u32 {
        const handle = self.next_handle;
        self.next_handle += 1;

        try self.input_streams.put(handle, InputStream.init(self.allocator, handle));

        var o = Log.op("Streams", "createInputStream");
        o.log("Created input stream: handle={d}", .{handle});

        return handle;
    }

    /// Create a new output stream
    pub fn createOutputStream(self: *Self) !u32 {
        const handle = self.next_handle;
        self.next_handle += 1;

        try self.output_streams.put(handle, OutputStream.init(self.allocator, handle));

        var o = Log.op("Streams", "createOutputStream");
        o.log("Created output stream: handle={d}", .{handle});

        return handle;
    }

    /// Create a pollable for a stream
    pub fn createPollable(self: *Self, stream_handle: u32) !u32 {
        const handle = self.next_handle;
        self.next_handle += 1;

        try self.pollables.put(handle, Pollable{
            .handle = stream_handle,
            .ready = true, // Always ready for now
        });

        var o = Log.op("Streams", "createPollable");
        o.log("Created pollable: handle={d} for stream={d}", .{ handle, stream_handle });

        return handle;
    }

    /// Read from input stream
    pub fn read(self: *Self, stream_handle: u32, len: u32) ![]const u8 {
        const stream = self.input_streams.getPtr(stream_handle) orelse return Error.InvalidHandle;

        if (stream.closed) {
            return Error.Closed;
        }

        var o = Log.op("Streams", "read");
        o.log("Reading from stream {d}, len={d}", .{ stream_handle, len });

        // For stdin (handle 0), read from actual stdin
        if (stream_handle == 0) {
            var buffer = try self.allocator.alloc(u8, len);
            const stdin_file = self.io.stdin();
            const bytes_read = try stdin_file.read(buffer);
            return buffer[0..bytes_read];
        }

        // For other streams, read from buffer
        const available = @min(len, stream.buffer.items.len);
        if (available == 0) {
            return &[_]u8{};
        }

        const data = try self.allocator.alloc(u8, available);
        @memcpy(data, stream.buffer.items[0..available]);

        // Remove read data from buffer
        std.mem.copyForwards(u8, stream.buffer.items, stream.buffer.items[available..]);
        stream.buffer.shrinkRetainingCapacity(stream.buffer.items.len - available);

        return data;
    }

    /// Write to output stream
    pub fn write(self: *Self, stream_handle: u32, data: []const u8) !u32 {
        const stream = self.output_streams.getPtr(stream_handle) orelse return Error.InvalidHandle;

        if (stream.closed) {
            return Error.Closed;
        }

        var o = Log.op("Streams", "write");
        o.log("Writing to stream {d}, len={d}", .{ stream_handle, data.len });

        // For stdout/stderr, write to actual output
        if (stream_handle == 1) {
            _ = try std_io.getStdOut().write(data);
            return @intCast(data.len);
        } else if (stream_handle == 2) {
            _ = try std_io.getStdErr().write(data);
            return @intCast(data.len);
        }

        // For other streams, buffer the data
        try stream.buffer.appendSlice(data);
        return @intCast(data.len);
    }

    /// Check available bytes in input stream
    pub fn checkRead(self: *Self, stream_handle: u32) !u64 {
        const stream = self.input_streams.get(stream_handle) orelse return Error.InvalidHandle;

        if (stream.closed) {
            return Error.Closed;
        }

        // For stdin, always return available
        if (stream_handle == 0) {
            return std.math.maxInt(u64);
        }

        return stream.buffer.items.len;
    }

    /// Check write capacity
    pub fn checkWrite(self: *Self, stream_handle: u32) !u64 {
        const stream = self.output_streams.get(stream_handle) orelse return Error.InvalidHandle;

        if (stream.closed) {
            return Error.Closed;
        }

        // Always report large capacity
        return std.math.maxInt(u64);
    }

    /// Close input stream
    pub fn closeInput(self: *Self, stream_handle: u32) !void {
        const stream = self.input_streams.getPtr(stream_handle) orelse return Error.InvalidHandle;
        stream.closed = true;

        var o = Log.op("Streams", "closeInput");
        o.log("Closed input stream: handle={d}", .{stream_handle});
    }

    /// Close output stream
    pub fn closeOutput(self: *Self, stream_handle: u32) !void {
        const stream = self.output_streams.getPtr(stream_handle) orelse return Error.InvalidHandle;
        stream.closed = true;

        var o = Log.op("Streams", "closeOutput");
        o.log("Closed output stream: handle={d}", .{stream_handle});
    }

    /// Flush output stream
    pub fn flush(self: *Self, stream_handle: u32) !void {
        const stream = self.output_streams.get(stream_handle) orelse return Error.InvalidHandle;

        if (stream.closed) {
            return Error.Closed;
        }

        var o = Log.op("Streams", "flush");
        o.log("Flushed output stream: handle={d}", .{stream_handle});

        // For stdout/stderr, flush the underlying stream
        if (stream_handle == 1) {
            try std_io.getStdOut().writeAll("");
        } else if (stream_handle == 2) {
            try std_io.getStdErr().writeAll("");
        }
    }

    /// Poll multiple pollables
    pub fn poll(self: *Self, pollables: []const u32) ![]const u32 {
        var o = Log.op("Streams", "poll");
        o.log("Polling {d} pollables", .{pollables.len});

        // For now, return all as ready
        const ready = try self.allocator.alloc(u32, pollables.len);
        for (pollables, 0..) |p, i| {
            ready[i] = p;
        }

        return ready;
    }

    /// Block on a single pollable
    pub fn blockOnPollable(self: *Self, pollable_handle: u32) !void {
        _ = self;

        var o = Log.op("Streams", "blockOnPollable");
        o.log("Blocking on pollable: handle={d}", .{pollable_handle});

        // For now, immediately return (non-blocking)
    }
};

/// WASI Streams API (exported functions)
pub const API = struct {
    /// read(stream: input-stream, len: u64) -> result<list<u8>, stream-error>
    pub fn inputStreamRead(manager: *StreamsManager, stream: u32, len: u32, buf_ptr: u32, memory: []u8) !u32 {
        const data = try manager.read(stream, len);
        defer manager.allocator.free(data);

        // Write data to WASM memory
        if (buf_ptr + data.len > memory.len) {
            return Error.OutOfMemory;
        }

        @memcpy(memory[buf_ptr..][0..data.len], data);
        return @intCast(data.len);
    }

    /// blocking-read(stream: input-stream, len: u64) -> result<list<u8>, stream-error>
    pub fn inputStreamBlockingRead(manager: *StreamsManager, stream: u32, len: u32, buf_ptr: u32, memory: []u8) !u32 {
        // For now, same as non-blocking read
        return inputStreamRead(manager, stream, len, buf_ptr, memory);
    }

    /// skip(stream: input-stream, len: u64) -> result<u64, stream-error>
    pub fn inputStreamSkip(manager: *StreamsManager, stream: u32, len: u32) !u32 {
        const data = try manager.read(stream, len);
        defer manager.allocator.free(data);
        return @intCast(data.len);
    }

    /// write(stream: output-stream, buf: list<u8>) -> result<u64, stream-error>
    pub fn outputStreamWrite(manager: *StreamsManager, stream: u32, buf_ptr: u32, buf_len: u32, memory: []const u8) !u32 {
        if (buf_ptr + buf_len > memory.len) {
            return Error.OutOfMemory;
        }

        const data = memory[buf_ptr..][0..buf_len];
        return try manager.write(stream, data);
    }

    /// blocking-write(stream: output-stream, buf: list<u8>) -> result<u64, stream-error>
    pub fn outputStreamBlockingWrite(manager: *StreamsManager, stream: u32, buf_ptr: u32, buf_len: u32, memory: []const u8) !u32 {
        // For now, same as non-blocking write
        return outputStreamWrite(manager, stream, buf_ptr, buf_len, memory);
    }

    /// flush(stream: output-stream) -> result<_, stream-error>
    pub fn outputStreamFlush(manager: *StreamsManager, stream: u32) !void {
        try manager.flush(stream);
    }

    /// blocking-flush(stream: output-stream) -> result<_, stream-error>
    pub fn outputStreamBlockingFlush(manager: *StreamsManager, stream: u32) !void {
        try manager.flush(stream);
    }

    /// check-write(stream: output-stream) -> result<u64, stream-error>
    pub fn outputStreamCheckWrite(manager: *StreamsManager, stream: u32) !u64 {
        return try manager.checkWrite(stream);
    }

    /// subscribe(stream: input-stream) -> pollable
    pub fn inputStreamSubscribe(manager: *StreamsManager, stream: u32) !u32 {
        return try manager.createPollable(stream);
    }

    /// subscribe(stream: output-stream) -> pollable
    pub fn outputStreamSubscribe(manager: *StreamsManager, stream: u32) !u32 {
        return try manager.createPollable(stream);
    }

    /// poll(pollables: list<pollable>) -> list<u32>
    pub fn pollList(manager: *StreamsManager, pollables_ptr: u32, pollables_len: u32, memory: []const u8) !u32 {
        if (pollables_ptr + pollables_len * 4 > memory.len) {
            return Error.OutOfMemory;
        }

        var pollables = try manager.allocator.alloc(u32, pollables_len);
        defer manager.allocator.free(pollables);

        for (0..pollables_len) |i| {
            const offset = pollables_ptr + @as(u32, @intCast(i * 4));
            pollables[i] = std.mem.readInt(u32, memory[offset..][0..4], .little);
        }

        const ready = try manager.poll(pollables);
        defer manager.allocator.free(ready);

        return @intCast(ready.len);
    }

    /// block(pollable: pollable)
    pub fn pollableBlock(manager: *StreamsManager, pollable: u32) !void {
        try manager.blockOnPollable(pollable);
    }
};
