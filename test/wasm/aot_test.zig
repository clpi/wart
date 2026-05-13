const std = @import("std");
const Module = @import("../../src/wasm/module.zig");
const ValueType = @import("../../src/wasm/value.zig").Type;
const io = std.Options.debug_threaded_io();
const AOT = @import("../../src/wasm/aot.zig").AOT;

test "AOT initialization" {
    const allocator = std.testing.allocator;
    var io_provider = std.Io.Threaded.init(allocator, .{});
    defer io_provider.deinit();

    const module = try Module.init(allocator, io);
    defer module.deinit();

    var aot = try AOT.init(allocator, io_provider.io(), module);
    defer aot.deinit();

    try std.testing.expect(aot.optimize == .Aggressive);
}

test "Pattern detection - arithmetic loop" {
    const allocator = std.testing.allocator;
    var io_provider = std.Io.Threaded.init(allocator, .{});
    defer io_provider.deinit();

    const module = try Module.init(allocator, io);
    defer module.deinit();

    var aot = try AOT.init(allocator, io_provider.io(), module);
    defer aot.deinit();

    const code = [_]u8{ 0x03, 0x6A, 0x6B, 0x6C, 0x6A, 0x6B, 0x6C };
    const func = Module.Function{
        .type_index = 0,
        .locals = &[_]ValueType{},
        .code = &code,
    };

    const pattern = try aot.analyzeFunction(func);
    try std.testing.expect(pattern.has_loop);
    try std.testing.expect(pattern.arithmetic_density >= 5);
}

test "Pattern detection - fibonacci" {
    const allocator = std.testing.allocator;
    var io_provider = std.Io.Threaded.init(allocator, .{});
    defer io_provider.deinit();

    const module = try Module.init(allocator, io);
    defer module.deinit();

    var aot = try AOT.init(allocator, io_provider.io(), module);
    defer aot.deinit();

    const code = [_]u8{ 0x10, 0x6A, 0x10 };
    const func = Module.Function{
        .type_index = 0,
        .locals = &[_]ValueType{},
        .code = &code,
    };

    const pattern = try aot.analyzeFunction(func);
    try std.testing.expect(pattern.call_count >= 2);
}
