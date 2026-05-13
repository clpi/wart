const std = @import("std");
const wasi_io = @import("../../src/wasm/wasi/io.zig");

const Streams = wasi_io.Streams;
const StreamStatus = wasi_io.StreamStatus;

test "streams read from file" {
    const allocator = std.testing.allocator;
    var io_provider = std.Io.Threaded.init(allocator, .{});
    defer io_provider.deinit();
    const io = io_provider.io();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(io, .{ .sub_path = "input.txt", .data = "hello wasm" });
    var file = try tmp.dir.openFile(io, "input.txt", .{ .mode = .read_only });
    defer file.close(io);

    var streams = try Streams.init(allocator, io);
    defer streams.deinit();

    const handle = try streams.addInputFile(file, .{ .close_on_drop = false });
    const result = streams.read(handle, 5);
    switch (result) {
        .ok => |payload| {
            defer streams.freeReadBuffer(payload.bytes);
            try std.testing.expectEqualSlices(u8, "hello", payload.bytes);
            try std.testing.expectEqual(StreamStatus.open, payload.status);
        },
        .err => |err| switch (err) {
            .closed => return std.testing.expect(false),
            .lastOperationFailed => return std.testing.expect(false),
        },
    }
}

test "streams write to file and flush" {
    const allocator = std.testing.allocator;
    var io_provider = std.Io.Threaded.init(allocator, .{});
    defer io_provider.deinit();
    const io = io_provider.io();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var file = try tmp.dir.createFile(io, "output.txt", .{ .read = true, .truncate = true });
    defer file.close(io);

    var streams = try Streams.init(allocator, io);
    defer streams.deinit();

    const handle = try streams.addOutputFile(file, .{ .close_on_drop = false });
    {
        const written = streams.write(handle, "preview3");
        switch (written) {
            .ok => |count| try std.testing.expectEqual(@as(u64, 8), count),
            .err => return std.testing.expect(false),
        }
    }
    switch (streams.flush(handle)) {
        .ok => {},
        .err => return std.testing.expect(false),
    }

    const written = try tmp.dir.readFileAlloc(io, "output.txt", allocator, .limited(64));
    defer allocator.free(written);

    try std.testing.expectEqual(@as(usize, 8), written.len);
    try std.testing.expectEqualSlices(u8, "preview3", written);
}
