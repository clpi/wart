const std = @import("std");
const testing = std.testing;
const Module = @import("../../src/wasm/module.zig");
const Expression = @import("../../src/wasm/module.zig").Expression;
const value = @import("../../src/wasm/value.zig");
const Value = value.Value;
const io = std.Options.debug_threaded_io();

test "constant expression - i32.const" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create a simple module with memory for testing
    var module = try Module.init(allocator, io);
    defer module.deinit();

    // Initialize memory
    module.memory = try allocator.alloc(u8, 1024);
    @memset(module.memory.?, 0);

    // Test i32.const expression: i32.const 42, end
    var expr = Expression.init(allocator);
    defer expr.deinit();

    // Manually add operations (normally this would be parsed)
    try expr.operations.append(.{ .i32_const = 42 });

    const result = try module.evaluateConstantExpression(&expr);
    try testing.expectEqual(@as(i32, 42), result.i32);
}

test "constant expression - i64.const" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var module = try Module.init(allocator, io);
    defer module.deinit();

    var expr = Expression.init(allocator);
    defer expr.deinit();

    try expr.operations.append(.{ .i64_const = 123456789 });

    const result = try module.evaluateConstantExpression(&expr);
    try testing.expectEqual(@as(i64, 123456789), result.i64);
}

test "constant expression - f32.const" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var module = try Module.init(allocator, io);
    defer module.deinit();

    var expr = Expression.init(allocator);
    defer expr.deinit();

    try expr.operations.append(.{ .f32_const = 3.14 });

    const result = try module.evaluateConstantExpression(&expr);
    try testing.expectEqual(@as(f32, 3.14), result.f32);
}

test "constant expression - f64.const" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var module = try Module.init(allocator, io);
    defer module.deinit();

    var expr = Expression.init(allocator);
    defer expr.deinit();

    try expr.operations.append(.{ .f64_const = 2.71828 });

    const result = try module.evaluateConstantExpression(&expr);
    try testing.expectEqual(@as(f64, 2.71828), result.f64);
}

test "constant expression - v128.const" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var module = try Module.init(allocator, io);
    defer module.deinit();

    var expr = Expression.init(allocator);
    defer expr.deinit();

    const expected = [_]u8{0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF};
    try expr.operations.append(.{ .v128_const = expected });

    const result = try module.evaluateConstantExpression(&expr);
    try testing.expectEqualSlices(u8, &expected, &result.v128);
}

test "constant expression - i32.add" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var module = try Module.init(allocator, io);
    defer module.deinit();

    var expr = Expression.init(allocator);
    defer expr.deinit();

    // i32.const 10, i32.const 20, i32.add
    try expr.operations.append(.{ .i32_const = 10 });
    try expr.operations.append(.{ .i32_const = 20 });
    try expr.operations.append(.i32_add);

    const result = try module.evaluateConstantExpression(&expr);
    try testing.expectEqual(@as(i32, 30), result.i32);
}

test "constant expression - i32.load" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var module = try Module.init(allocator, io);
    defer module.deinit();

    // Initialize memory with test data
    module.memory = try allocator.alloc(u8, 1024);
    @memset(module.memory.?, 0);
    // Write 0x12345678 at offset 100 (little endian)
    std.mem.writeInt(u32, module.memory.?[100..104], 0x12345678, .little);

    var expr = Expression.init(allocator);
    defer expr.deinit();

    // i32.const 100, i32.load
    try expr.operations.append(.{ .i32_const = 100 });
    try expr.operations.append(.{ .i32_load = .{ .offset = 0, .alignment = 4 } });

    const result = try module.evaluateConstantExpression(&expr);
    try testing.expectEqual(@as(i32, 0x12345678), result.i32);
}

test "constant expression - i32.load8_u" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var module = try Module.init(allocator, io);
    defer module.deinit();

    // Initialize memory with test data
    module.memory = try allocator.alloc(u8, 1024);
    @memset(module.memory.?, 0);
    module.memory.?[50] = 0xAB;

    var expr = Expression.init(allocator);
    defer expr.deinit();

    // i32.const 50, i32.load8_u
    try expr.operations.append(.{ .i32_const = 50 });
    try expr.operations.append(.{ .i32_load8_u = .{ .offset = 0, .alignment = 1 } });

    const result = try module.evaluateConstantExpression(&expr);
    try testing.expectEqual(@as(i32, 0xAB), result.i32);
}

test "constant expression - global.get" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var module = try Module.init(allocator, io);
    defer module.deinit();

    // Add a global with value 42
    try module.globals.append(allocator, .{
        .value = .{ .i32 = 42 },
        .mutable = false,
        .val_type = .i32,
    });

    var expr = Expression.init(allocator);
    defer expr.deinit();

    // global.get 0
    try expr.operations.append(.{ .global_get = 0 });

    const result = try module.evaluateConstantExpression(&expr);
    try testing.expectEqual(@as(i32, 42), result.i32);
}

test "constant expression - ref.null" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var module = try Module.init(allocator, io);
    defer module.deinit();

    var expr = Expression.init(allocator);
    defer expr.deinit();

    // ref.null funcref
    try expr.operations.append(.{ .ref_null = .funcref });

    const result = try module.evaluateConstantExpression(&expr);
    try testing.expect(result == .ref_null);
}

test "constant expression - ref.func" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var module = try Module.init(allocator, io);
    defer module.deinit();

    // Add a dummy function
    const func = try allocator.create(Module.Function);
    func.* = .{
        .type_index = 0,
        .code = &[_]u8{},
        .locals = &[_]value.ValueType{},
        .imported = false,
    };
    try module.functions.append(allocator, func);

    var expr = Expression.init(allocator);
    defer expr.deinit();

    // ref.func 0
    try expr.operations.append(.{ .ref_func = 0 });

    const result = try module.evaluateConstantExpression(&expr);
    try testing.expectEqual(@as(u32, 0), result.ref_func);
}
