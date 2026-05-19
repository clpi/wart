const std = @import("std");
const Value = @import("value.zig").Value;

/// WASI Preview 2 implementation
/// Based on the WASI 0.2 specification
pub const WasiPreview2 = struct {
    io: std.Io,
    allocator: std.mem.Allocator,

    // Resource handles
    streams: std.ArrayListUnmanaged(Stream),
    errors: std.ArrayListUnmanaged(Error),

    // Standard I/O stream handles
    stdin_handle: u32,
    stdout_handle: u32,
    stderr_handle: u32,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, io: std.Io) !Self {
        var wasi = Self{
            .io = io,
            .allocator = allocator,
            .streams = .empty,
            .errors = .empty,
            .stdin_handle = 0,
            .stdout_handle = 0,
            .stderr_handle = 0,
        };

        // Create standard streams
        // Stdin (handle 0)
        try wasi.streams.append(allocator, Stream{
            .kind = .input,
            .fd = std.io.getStdIn().handle,
        });
        wasi.stdin_handle = 0;

        // Stdout (handle 1)
        try wasi.streams.append(allocator, Stream{
            .kind = .output,
            .fd = std.io.getStdOut().handle,
        });
        wasi.stdout_handle = 1;

        // Stderr (handle 2)
        try wasi.streams.append(allocator, Stream{
            .kind = .output,
            .fd = std.io.getStdErr().handle,
        });
        wasi.stderr_handle = 2;

        return wasi;
    }

    pub fn deinit(self: *Self) void {
        self.streams.deinit(self.allocator);
        self.errors.deinit(self.allocator);
    }

    // wasi:io/streams@0.2.0

    /// Check how many bytes can be written
    pub fn outputStreamCheckWrite(self: *Self, stream_handle: u32) !u64 {
        _ = self;
        _ = stream_handle;
        // For now, always report 64KB available
        return 65536;
    }

    /// Write bytes to output stream
    pub fn outputStreamWrite(self: *Self, stream_handle: u32, contents: []const u8) !void {
        if (stream_handle >= self.streams.items.len) {
            return error.InvalidStreamHandle;
        }

        const stream = &self.streams.items[stream_handle];
        if (stream.kind != .output) {
            return error.NotAnOutputStream;
        }

        // Write to the underlying file descriptor
        const file = std.Io.File{ .handle = stream.fd, .flags = .{ .nonblocking = false } };
        try file.writeStreamingAll(self.io, contents);
    }

    /// Blocking write and flush
    pub fn outputStreamBlockingWriteAndFlush(self: *Self, stream_handle: u32, contents: []const u8) !void {
        try self.outputStreamWrite(stream_handle, contents);

        if (stream_handle >= self.streams.items.len) {
            return error.InvalidStreamHandle;
        }

        const stream = &self.streams.items[stream_handle];
        const file = std.Io.File{ .handle = stream.fd, .flags = .{ .nonblocking = false } };

        // Flush the stream
        if (@hasDecl(std.Io.File, "sync")) {
            try file.sync(self.io);
        }
    }

    /// Blocking flush
    pub fn outputStreamBlockingFlush(self: *Self, stream_handle: u32) !void {
        if (stream_handle >= self.streams.items.len) {
            return error.InvalidStreamHandle;
        }

        const stream = &self.streams.items[stream_handle];
        const file = std.Io.File{ .handle = stream.fd, .flags = .{ .nonblocking = false } };

        if (@hasDecl(std.Io.File, "sync")) {
            try file.sync(self.io);
        }
    }

    /// Read from input stream
    pub fn inputStreamRead(self: *Self, stream_handle: u32, len: u64) ![]const u8 {
        if (stream_handle >= self.streams.items.len) {
            return error.InvalidStreamHandle;
        }

        const stream = &self.streams.items[stream_handle];
        if (stream.kind != .input) {
            return error.NotAnInputStream;
        }

        const buffer = try self.allocator.alloc(u8, len);
        const file = std.Io.File{ .handle = stream.fd, .flags = .{ .nonblocking = false } };
        const bytes_read = try file.readStreaming(self.io, &[_][]u8{buffer});

        return buffer[0..bytes_read];
    }

    /// Blocking read
    pub fn inputStreamBlockingRead(self: *Self, stream_handle: u32, len: u64) ![]const u8 {
        return try self.inputStreamRead(stream_handle, len);
    }

    // wasi:cli/stdin@0.2.0

    pub fn getStdin(self: *Self) !u32 {
        return self.stdin_handle;
    }

    // wasi:cli/stdout@0.2.0

    pub fn getStdout(self: *Self) !u32 {
        return self.stdout_handle;
    }

    // wasi:cli/stderr@0.2.0

    pub fn getStderr(self: *Self) !u32 {
        return self.stderr_handle;
    }

    // wasi:cli/environment@0.2.0

    pub fn getEnvironment(self: *Self) ![]const [2][]const u8 {
        _ = self;
        // Return empty environment for now
        return &[_][2][]const u8{};
    }

    pub fn getArguments(self: *Self) ![]const []const u8 {
        _ = self;
        // Return empty arguments for now
        return &[_][]const u8{};
    }

    // wasi:cli/exit@0.2.0

    pub fn exit(self: *Self, status: u32) !void {
        _ = self;
        std.process.exit(@intCast(status));
    }

    // wasi:clocks/wall-clock@0.2.0

    pub fn now(self: *Self) !Datetime {
        _ = self;
        const timestamp = @import("../util/time.zig").nanoTimestamp();

        return Datetime{
            .seconds = @intCast(@divFloor(timestamp, std.time.ns_per_s)),
            .nanoseconds = @intCast(@mod(timestamp, std.time.ns_per_s)),
        };
    }

    pub fn resolution(self: *Self) !Datetime {
        _ = self;
        // Report nanosecond resolution
        return Datetime{
            .seconds = 0,
            .nanoseconds = 1,
        };
    }

    // Types

    const Stream = struct {
        kind: Kind,
        fd: std.fs.File.Handle,

        const Kind = enum {
            input,
            output,
        };
    };

    const Error = struct {
        message: []const u8,
    };

    pub const Datetime = struct {
        seconds: u64,
        nanoseconds: u32,
    };
};
