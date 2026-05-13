const std = @import("std");
const CLI = @import("../../src/wasm/wasi/cli.zig").CLI;
const Streams = @import("../../src/wasm/wasi/io.zig").Streams;

test "cli run command success" {
    const allocator = std.testing.allocator;
    var io_provider = std.Io.Threaded.init(allocator, .{});
    defer io_provider.deinit();
    var streams = try Streams.init(allocator, io_provider.io());
    defer streams.deinit();

    var cli = try CLI.init(allocator, &streams);
    defer cli.deinit();

    const handle = try cli.createCommand("echo");
    try cli.commandPushArg(handle, "hello");

    const status = cli.run(handle);
    try std.testing.expect(status == .ok);
}

test "cli run command non-zero exit" {
    const allocator = std.testing.allocator;
    var io_provider = std.Io.Threaded.init(allocator, .{});
    defer io_provider.deinit();
    var streams = try Streams.init(allocator, io_provider.io());
    defer streams.deinit();

    var cli = try CLI.init(allocator, &streams);
    defer cli.deinit();

    const handle = try cli.createCommand("exit");
    try cli.commandPushArg(handle, "42");

    const result = cli.run(handle);
    try std.testing.expect(result == .ok);
    try std.testing.expect(result.ok == .terminated);
    try std.testing.expectEqual(@as(u8, 42), result.ok.terminated);
}
