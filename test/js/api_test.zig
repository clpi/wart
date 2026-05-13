const std = @import("std");
const js = @import("../../src/js/api.zig");

const add42_module = [_]u8{
    0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00, 0x01, 0x06, 0x01, 0x60,
    0x01, 0x7f, 0x01, 0x7f, 0x03, 0x02, 0x01, 0x00, 0x07, 0x09, 0x01, 0x05,
    0x61, 0x64, 0x64, 0x34, 0x32, 0x00, 0x00, 0x0a, 0x09, 0x01, 0x07, 0x00,
    0x20, 0x00, 0x41, 0x2a, 0x6a, 0x0b,
};

test "JS API can instantiate module and invoke export" {
    var allocator = std.testing.allocator;

    var module = try js.JsModule.fromBytes(allocator, &add42_module);
    defer module.deinit();

    var io_provider = std.Io.Threaded.init(allocator, .{});
    defer io_provider.deinit();

    var runtime = try js.JsRuntime.init(allocator, io_provider.io());
    defer runtime.deinit();
    runtime.setConfig(false, true);

    var instance = try runtime.instantiate(&module);
    defer instance.deinit();

    const exports = instance.exports();
    try std.testing.expectEqual(@as(usize, 1), exports.len);
    try std.testing.expect(std.mem.eql(u8, exports[0].name, "add42"));

    const args = [_]js.JsValue{js.JsValue{ .i32 = 58 }};
    const value = try instance.invoke("add42", &args);

    switch (value) {
        .i32 => |result| try std.testing.expectEqual(@as(i32, 100), result),
        else => return error.UnexpectedReturnType,
    }
}
