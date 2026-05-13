const std = @import("std");
const Runtime = @import("../../src/wasm/runtime.zig");
const Value = Runtime.Value;

// Module generated from:
// (module
//   (type (func (result i32)))
//   (func $callee (type 0) (result i32)
//     i32.const 42)
//   (func (export "call_ref") (result i32)
//     ref.func $callee
//     call_ref 0))
const call_ref_module = [_]u8{
    0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00,
    0x01, 0x05, 0x01, 0x60, 0x00, 0x01, 0x7f, 0x03,
    0x03, 0x02, 0x00, 0x00, 0x07, 0x0c, 0x01, 0x08,
    0x63, 0x61, 0x6c, 0x6c, 0x5f, 0x72, 0x65, 0x66,
    0x00, 0x01, 0x0a, 0x0d, 0x02, 0x04, 0x00, 0x41,
    0x2a, 0x0b, 0x06, 0x00, 0xd2, 0x00, 0x14, 0x00,
    0x0b, 0x00, 0x10, 0x04, 0x6e, 0x61, 0x6d, 0x65,
    0x01, 0x09, 0x01, 0x00, 0x06, 0x63, 0x61, 0x6c,
    0x6c, 0x65, 0x65,
};

test "typed function references: call_ref executes typed callee" {
    var io_provider = std.Io.Threaded.init(std.testing.allocator, .{});
    defer io_provider.deinit();

    var runtime = try Runtime.init(std.testing.allocator, io_provider.io());
    defer runtime.deinit();

    _ = try runtime.loadModule(&call_ref_module);

    const func_idx = runtime.findExportedFunction("call_ref") orelse {
        return error.FunctionNotFound;
    };

    const result = try runtime.executeFunction(func_idx, &[_]Value{});
    try std.testing.expectEqual(@as(i32, 42), result.i32);
}
