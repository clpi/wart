const std = @import("std");
const Io = std.Io;

pub const StreamStatus = enum {
    open,
    closed,
};

pub const StreamError = union(enum) {
    closed,
    lastOperationFailed: anyerror,
};

pub fn Result(comptime T: type) type {
    return union(enum) {
        ok: T,
        err: StreamError,
    };
}

pub const ResultVoid = union(enum) {
    ok,
    err: StreamError,
};

pub const Pollable = struct {
    ready: bool,
};

pub const Streams = struct {
    const Self = @This();

    pub const InputStreamHandle = u32;
    pub const OutputStreamHandle = u32;

    allocator: std.mem.Allocator,
    io: std.Io,
    input_streams: std.AutoHashMap(InputStreamHandle, InputStream),
    output_streams: std.AutoHashMap(OutputStreamHandle, OutputStream),
    next_input: InputStreamHandle,
    next_output: OutputStreamHandle,

    pub const RegisterOptions = struct { close_on_drop: bool = false };

    pub const ReadOutcome = struct {
        bytes: []u8,
        status: StreamStatus,
    };

    pub const SkipOutcome = struct {
        skipped: u64,
        status: StreamStatus,
    };

    pub const ForwardOutcome = struct {
        transferred: u64,
        status: StreamStatus,
    };

    pub const InputStream = struct {
        source: Source,
        closed: bool,

        const Source = union(enum) {
            file: File,
        };

        const File = struct {
            file: std.Io.File,
            io: std.Io,
            close_on_drop: bool,

            fn read(self: *File, dest: []u8) !usize {
                return self.file.readStreaming(self.io, &[_][]u8{dest});
            }

            fn skip(self: *File, scratch: []u8, amount: usize) !usize {
                var remaining = amount;
                var skipped: usize = 0;
                while (remaining > 0) {
                    const chunk = @min(remaining, scratch.len);
                    const n = try self.file.readStreaming(self.io, &[_][]u8{scratch[0..chunk]});
                    if (n == 0) break;
                    skipped += n;
                    remaining -= n;
                    if (n < chunk) break;
                }
                return skipped;
            }

            fn readAll(self: *File, allocator: std.mem.Allocator) ![]u8 {
                var list = std.ArrayList(u8).init(allocator);
                errdefer list.deinit();

                var buf: [4096]u8 = undefined;
                while (true) {
                    const n = try self.file.readStreaming(self.io, &[_][]u8{buf[0..]});
                    if (n == 0) break;
                    try list.appendSlice(buf[0..n]);
                }

                return list.toOwnedSlice();
            }

            fn deinit(self: *File) void {
                if (self.close_on_drop) {
                    self.file.close(self.io);
                }
            }
        };

        fn deinit(self: *InputStream) void {
            switch (self.source) {
                .file => |*f| f.deinit(),
            }
        }
    };

    pub const OutputStream = struct {
        sink: Sink,
        closed: bool,

        const Sink = union(enum) {
            file: File,
        };

        const File = struct {
            file: std.Io.File,
            io: std.Io,
            close_on_drop: bool,

            fn write(self: *File, src: []const u8) !usize {
                try self.file.writeStreamingAll(self.io, src);
                return src.len;
            }

            fn flush(self: *File) !void {
                try self.file.sync(self.io);
            }

            fn deinit(self: *File) void {
                if (self.close_on_drop) {
                    self.file.close(self.io);
                }
            }
        };

        fn deinit(self: *OutputStream) void {
            switch (self.sink) {
                .file => |*f| f.deinit(),
            }
        }
    };

    pub fn init(allocator: std.mem.Allocator, io: std.Io) !Self {
        return Self{
            .allocator = allocator,
            .io = io,
            .input_streams = std.AutoHashMap(InputStreamHandle, InputStream).init(allocator),
            .output_streams = std.AutoHashMap(OutputStreamHandle, OutputStream).init(allocator),
            .next_input = 0,
            .next_output = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        {
            var it = self.input_streams.iterator();
            while (it.next()) |entry| {
                entry.value_ptr.deinit();
            }
        }
        {
            var it = self.output_streams.iterator();
            while (it.next()) |entry| {
                entry.value_ptr.deinit();
            }
        }
        self.input_streams.deinit();
        self.output_streams.deinit();
    }

    pub fn addInputFile(self: *Self, file: std.Io.File, options: RegisterOptions) !InputStreamHandle {
        const handle = self.next_input;
        self.next_input += 1;

        const stream = InputStream{
            .source = .{ .file = .{ .file = file, .io = self.io, .close_on_drop = options.close_on_drop } },
            .closed = false,
        };
        try self.input_streams.putNoClobber(handle, stream);
        return handle;
    }

    pub fn addOutputFile(self: *Self, file: std.Io.File, options: RegisterOptions) !OutputStreamHandle {
        const handle = self.next_output;
        self.next_output += 1;

        const stream = OutputStream{
            .sink = .{ .file = .{ .file = file, .io = self.io, .close_on_drop = options.close_on_drop } },
            .closed = false,
        };
        try self.output_streams.putNoClobber(handle, stream);
        return handle;
    }

    pub fn dropInputStream(self: *Self, handle: InputStreamHandle) ResultVoid {
        if (self.input_streams.fetchRemove(handle)) |kv| {
            var value = kv.value;
            value.deinit();
            return .ok;
        }
        return .{ .err = .closed };
    }

    pub fn dropOutputStream(self: *Self, handle: OutputStreamHandle) ResultVoid {
        if (self.output_streams.fetchRemove(handle)) |kv| {
            var value = kv.value;
            value.deinit();
            return .ok;
        }
        return .{ .err = .closed };
    }

    pub fn read(self: *Self, handle: InputStreamHandle, len: usize) Result(ReadOutcome) {
        const stream = self.input_streams.getPtr(handle) orelse return .{ .err = .closed };
        if (stream.closed) return .{ .err = .closed };

        if (len == 0) {
            return .{ .ok = .{ .bytes = &[_]u8{}, .status = .open } };
        }

        const capped_len = @min(len, std.math.maxInt(usize));
        var buffer = self.allocator.alloc(u8, capped_len) catch |err| {
            return .{ .err = .{ .lastOperationFailed = err } };
        };
        errdefer self.allocator.free(buffer);

        const read_bytes = streamRead(stream, buffer) catch |err| {
            stream.closed = true;
            return .{ .err = .{ .lastOperationFailed = err } };
        };

        if (read_bytes == 0) {
            stream.closed = true;
            return .{ .ok = .{ .bytes = buffer[0..0], .status = .closed } };
        }

        return .{ .ok = .{ .bytes = buffer[0..read_bytes], .status = .open } };
    }

    pub fn blockingRead(self: *Self, handle: InputStreamHandle, len: usize) Result(ReadOutcome) {
        return self.read(handle, len);
    }

    pub fn readToEnd(self: *Self, handle: InputStreamHandle) Result(ReadOutcome) {
        const stream = self.input_streams.getPtr(handle) orelse return .{ .err = .closed };
        if (stream.closed) return .{ .err = .closed };

        const data = streamReadAll(stream, self.allocator) catch |err| {
            stream.closed = true;
            return .{ .err = .{ .lastOperationFailed = err } };
        };

        return self.readToEndDone(data, .open);
    }

    fn readToEndDone(self: *Self, data: []u8, status: StreamStatus) Result(ReadOutcome) {
        _ = self;
        return .{ .ok = .{ .bytes = data, .status = status } };
    }

    pub fn skip(self: *Self, handle: InputStreamHandle, amount: usize) Result(SkipOutcome) {
        const stream = self.input_streams.getPtr(handle) orelse return .{ .err = .closed };
        if (stream.closed) return .{ .err = .closed };

        var scratch: [4096]u8 = undefined;
        const skipped = streamSkip(stream, &scratch, amount) catch |err| {
            stream.closed = true;
            return .{ .err = .{ .lastOperationFailed = err } };
        };

        if (skipped < amount) stream.closed = true;
        return .{ .ok = .{ .skipped = skipped, .status = if (skipped < amount) .closed else .open } };
    }

    pub fn blockingSkip(self: *Self, handle: InputStreamHandle, amount: usize) Result(SkipOutcome) {
        return self.skip(handle, amount);
    }

    pub fn write(self: *Self, handle: OutputStreamHandle, data: []const u8) Result(u64) {
        const stream = self.output_streams.getPtr(handle) orelse return .{ .err = .closed };
        if (stream.closed) return .{ .err = .closed };

        if (data.len == 0) return .{ .ok = 0 };

        const written = streamWrite(stream, data) catch |err| {
            stream.closed = true;
            return .{ .err = .{ .lastOperationFailed = err } };
        };

        return .{ .ok = @intCast(written) };
    }

    pub fn blockingWrite(self: *Self, handle: OutputStreamHandle, data: []const u8) Result(u64) {
        return self.write(handle, data);
    }

    pub fn flush(self: *Self, handle: OutputStreamHandle) ResultVoid {
        const stream = self.output_streams.getPtr(handle) orelse return .{ .err = .closed };
        if (stream.closed) return .{ .err = .closed };

        streamFlush(stream) catch |err| {
            stream.closed = true;
            return .{ .err = .{ .lastOperationFailed = err } };
        };

        return ResultVoid.ok;
    }

    pub fn checkWrite(_: *Self, _: OutputStreamHandle) Result(u64) {
        // No buffering guarantees yet; report a conservative chunk size
        return .{ .ok = 64 * 1024 };
    }

    pub fn writeZeroes(self: *Self, handle: OutputStreamHandle, amount: usize) Result(u64) {
        const stream = self.output_streams.getPtr(handle) orelse return .{ .err = .closed };
        if (stream.closed) return .{ .err = .closed };

        if (amount == 0) return .{ .ok = 0 };

        var zeros: [4096]u8 = [_]u8{0} **4096;
        var remaining = amount;
        var total: usize = 0;

        while (remaining > 0) {
            const chunk = @min(remaining, zeros.len);
            const written = streamWrite(stream, zeros[0..chunk]) catch |err| {
                stream.closed = true;
                return .{ .err = .{ .lastOperationFailed = err } };
            };
            total += written;
            remaining -= written;
            if (written < chunk) break;
        }

        return .{ .ok = @intCast(total) };
    }

    pub fn blockingWriteZeroes(self: *Self, handle: OutputStreamHandle, amount: usize) Result(u64) {
        return self.writeZeroes(handle, amount);
    }

    pub fn splice(self: *Self, dst_handle: OutputStreamHandle, src_handle: InputStreamHandle, amount: usize) Result(u64) {
        const dst = self.output_streams.getPtr(dst_handle) orelse return .{ .err = .closed };
        const src = self.input_streams.getPtr(src_handle) orelse return .{ .err = .closed };
        if (dst.closed or src.closed) return .{ .err = .closed };

        var scratch: [4096]u8 = undefined;
        var remaining = amount;
        var total: usize = 0;

        while (remaining > 0) {
            const chunk = @min(remaining, scratch.len);
            const read_bytes = streamRead(src, scratch[0..chunk]) catch |err| {
                src.closed = true;
                return .{ .err = .{ .lastOperationFailed = err } };
            };

            if (read_bytes == 0) {
                src.closed = true;
                break;
            }

            const written = streamWrite(dst, scratch[0..read_bytes]) catch |err| {
                dst.closed = true;
                return .{ .err = .{ .lastOperationFailed = err } };
            };

            total += written;
            remaining -= written;
            if (written < read_bytes) break;
        }

        return .{ .ok = @intCast(total) };
    }

    pub fn blockingSplice(self: *Self, dst_handle: OutputStreamHandle, src_handle: InputStreamHandle, amount: usize) Result(u64) {
        return self.splice(dst_handle, src_handle, amount);
    }

    pub fn forward(self: *Self, dst_handle: OutputStreamHandle, src_handle: InputStreamHandle) Result(ForwardOutcome) {
        const dst = self.output_streams.getPtr(dst_handle) orelse return .{ .err = .closed };
        const src = self.input_streams.getPtr(src_handle) orelse return .{ .err = .closed };
        if (dst.closed or src.closed) return .{ .err = .closed };

        var scratch: [4096]u8 = undefined;
        var total: usize = 0;

        while (true) {
            const read_bytes = streamRead(src, &scratch) catch |err| {
                src.closed = true;
                return .{ .err = .{ .lastOperationFailed = err } };
            };
            if (read_bytes == 0) {
                src.closed = true;
                break;
            }
            const written = streamWrite(dst, scratch[0..read_bytes]) catch |err| {
                dst.closed = true;
                return .{ .err = .{ .lastOperationFailed = err } };
            };
            total += written;
            if (written < read_bytes) break;
        }

        return .{ .ok = .{ .transferred = @intCast(total), .status = if (src.closed) .closed else .open } };
    }

    pub fn subscribeInput(self: *Self, handle: InputStreamHandle) Result(Pollable) {
        const stream = self.input_streams.getPtr(handle) orelse return .{ .err = .closed };
        return .{ .ok = .{ .ready = !stream.closed } };
    }

    pub fn subscribeOutput(self: *Self, handle: OutputStreamHandle) Result(Pollable) {
        const stream = self.output_streams.getPtr(handle) orelse return .{ .err = .closed };
        return .{ .ok = .{ .ready = !stream.closed } };
    }

    pub fn freeReadBuffer(self: *Self, buffer: []u8) void {
        self.allocator.free(buffer);
    }

    fn streamRead(stream: *InputStream, dest: []u8) !usize {
        return switch (stream.source) {
            .file => |*f| f.read(dest),
        };
    }

    fn streamReadAll(stream: *InputStream, allocator: std.mem.Allocator) ![]u8 {
        return switch (stream.source) {
            .file => |*f| f.readAll(allocator),
        };
    }

    fn streamSkip(stream: *InputStream, scratch: []u8, amount: usize) !usize {
        return switch (stream.source) {
            .file => |*f| f.skip(scratch, amount),
        };
    }

    fn streamWrite(stream: *OutputStream, data: []const u8) !usize {
        return switch (stream.sink) {
            .file => |*f| f.write(data),
        };
    }

    fn streamFlush(stream: *OutputStream) anyerror!void {
        return switch (stream.sink) {
            .file => |*f| f.flush(),
        };
    }
};
