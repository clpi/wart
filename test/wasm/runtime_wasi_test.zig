const std = @import("std");
const Runtime = @import("../../src/wasm/runtime.zig");
const Value = Runtime.Value;

test "WASI functionality" {
    const allocator = std.testing.allocator;

    var io_provider = std.Io.Threaded.init(allocator, .{});
    defer io_provider.deinit();
    const io = io_provider.io();

    const wasm_data = try std.Io.Dir.cwd().readFileAlloc(io, "zig-out/bin/opcodes_cli.wasm", allocator, .limited(1024 * 1024));
    defer allocator.free(wasm_data);

    var runtime = try Runtime.init(allocator, io);
    defer runtime.deinit();

    const args = try allocator.alloc([:0]u8, 0);
    defer allocator.free(args);

    try runtime.setupWASI(args);

    _ = try runtime.loadModule(wasm_data);

    const start_func_idx = runtime.findExportedFunction("_start") orelse {
        return error.NoStartFunction;
    };

    _ = try runtime.executeFunction(start_func_idx, &[_]Value{});
}

test "setupWASI tolerates module without memory section" {
    const allocator = std.testing.allocator;

    var io_provider = std.Io.Threaded.init(allocator, .{});
    defer io_provider.deinit();
    const io = io_provider.io();

    var runtime = try Runtime.init(allocator, io);
    defer runtime.deinit();

    // (module (func (export "_start") (nop)))
    const memoryless_wasm = [_]u8{
        0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00,
        0x01, 0x04, 0x01, 0x60, 0x00, 0x00, 0x03, 0x02,
        0x01, 0x00, 0x07, 0x0a, 0x01, 0x06, 0x5f, 0x73,
        0x74, 0x61, 0x72, 0x74, 0x00, 0x00, 0x0a, 0x05,
        0x01, 0x03, 0x00, 0x01, 0x0b,
    };

    _ = try runtime.loadModule(&memoryless_wasm);

    const args = try allocator.alloc([:0]u8, 0);
    defer allocator.free(args);

    try runtime.setupWASI(args);

    const start_func_idx = runtime.findExportedFunction("_start") orelse {
        return error.NoStartFunction;
    };
    _ = try runtime.executeFunction(start_func_idx, &[_]Value{});
}
