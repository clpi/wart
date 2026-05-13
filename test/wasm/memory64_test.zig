const std = @import("std");
const Runtime = @import("../../src/wasm/runtime.zig");
const Value = Runtime.Value;

const MEMORY64_MODULE = [_]u8{
    0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00, 0x01, 0x14, 0x04, 0x60,
    0x00, 0x01, 0x7e, 0x60, 0x01, 0x7e, 0x01, 0x7e, 0x60, 0x02, 0x7e, 0x7f,
    0x00, 0x60, 0x01, 0x7e, 0x01, 0x7f, 0x03, 0x05, 0x04, 0x00, 0x01, 0x02,
    0x03, 0x05, 0x04, 0x01, 0x05, 0x01, 0x04, 0x07, 0x1e, 0x04, 0x04, 0x73,
    0x69, 0x7a, 0x65, 0x00, 0x00, 0x04, 0x67, 0x72, 0x6f, 0x77, 0x00, 0x01,
    0x05, 0x73, 0x74, 0x6f, 0x72, 0x65, 0x00, 0x02, 0x04, 0x6c, 0x6f, 0x61,
    0x64, 0x00, 0x03, 0x0a, 0x1f, 0x04, 0x04, 0x00, 0x3f, 0x00, 0x0b, 0x06,
    0x00, 0x20, 0x00, 0x40, 0x00, 0x0b, 0x09, 0x00, 0x20, 0x00, 0x20, 0x01,
    0x36, 0x02, 0x00, 0x0b, 0x07, 0x00, 0x20, 0x00, 0x28, 0x02, 0x00, 0x0b,
};

test "memory64 executes loads, stores, and growth" {
    var io_provider = std.Io.Threaded.init(std.testing.allocator, .{});
    defer io_provider.deinit();

    var runtime = try Runtime.init(std.testing.allocator, io_provider.io());
    defer runtime.deinit();

    runtime.validate = true;
    runtime.debug = false;

    const module = try runtime.loadModule(&MEMORY64_MODULE);

    const size_idx = runtime.findExportedFunction("size") orelse return error.MissingExport;
    const grow_idx = runtime.findExportedFunction("grow") orelse return error.MissingExport;
    const store_idx = runtime.findExportedFunction("store") orelse return error.MissingExport;
    const load_idx = runtime.findExportedFunction("load") orelse return error.MissingExport;

    // Initial size should be one page.
    var result = try runtime.executeFunction(size_idx, &[_]Value{});
    try std.testing.expect(@as(Value.Type, std.meta.activeTag(result)) == .i64);
    try std.testing.expectEqual(@as(i64, 1), result.i64);

    // Grow by one page and ensure previous size returned.
    result = try runtime.executeFunction(grow_idx, &[_]Value{.{ .i64 = 1 }});
    try std.testing.expectEqual(@as(i64, 1), result.i64);

    // New size should now be two pages.
    result = try runtime.executeFunction(size_idx, &[_]Value{});
    try std.testing.expectEqual(@as(i64, 2), result.i64);

    // Store and load using 64-bit addresses.
    const value_to_store: i32 = 1234;
    _ = try runtime.executeFunction(store_idx, &[_]Value{ .{ .i64 = 0 }, .{ .i32 = value_to_store } });

    result = try runtime.executeFunction(load_idx, &[_]Value{.{ .i64 = 0 }});
    try std.testing.expect(@as(Value.Type, std.meta.activeTag(result)) == .i32);
    try std.testing.expectEqual(value_to_store, result.i32);

    // Clean up module to avoid leaks.
    _ = module; // module freed by runtime.deinit()
}
