const std = @import("std");
const testing = std.testing;
const bulk = @import("../../src/wasm/bulk_memory.zig");
const Value = @import("../../src/wasm/value.zig").Value;

const MemoryOps = bulk.MemoryOps;
const TableOps = bulk.TableOps;
const DataSegmentManager = bulk.DataSegmentManager;
const ElemSegmentManager = bulk.ElemSegmentManager;
const BulkOperations = bulk.BulkOperations;

// Memory Operations Tests

test "memory.copy - non-overlapping forward" {
    var memory = [_]u8{0} **100;
    @memcpy(memory[10..15], &[_]u8{ 1, 2, 3, 4, 5 });

    try MemoryOps.copy(&memory, 20, 10, 5);

    try testing.expectEqualSlices(u8, &[_]u8{ 1, 2, 3, 4, 5 }, memory[20..25]);
}

test "memory.copy - non-overlapping backward" {
    var memory = [_]u8{0} **100;
    @memcpy(memory[20..25], &[_]u8{ 1, 2, 3, 4, 5 });

    try MemoryOps.copy(&memory, 10, 20, 5);

    try testing.expectEqualSlices(u8, &[_]u8{ 1, 2, 3, 4, 5 }, memory[10..15]);
}

test "memory.copy - overlapping forward" {
    var memory = [_]u8{0} **100;
    @memcpy(memory[10..15], &[_]u8{ 1, 2, 3, 4, 5 });

    try MemoryOps.copy(&memory, 12, 10, 5);

    try testing.expectEqualSlices(u8, &[_]u8{ 1, 2, 3, 4, 5 }, memory[12..17]);
}

test "memory.copy - overlapping backward" {
    var memory = [_]u8{0} **100;
    @memcpy(memory[12..17], &[_]u8{ 1, 2, 3, 4, 5 });

    try MemoryOps.copy(&memory, 10, 12, 5);

    try testing.expectEqualSlices(u8, &[_]u8{ 1, 2, 3, 4, 5 }, memory[10..15]);
}

test "memory.copy - same position" {
    var memory = [_]u8{0} **100;
    @memcpy(memory[10..15], &[_]u8{ 1, 2, 3, 4, 5 });

    try MemoryOps.copy(&memory, 10, 10, 5);

    try testing.expectEqualSlices(u8, &[_]u8{ 1, 2, 3, 4, 5 }, memory[10..15]);
}

test "memory.copy - bounds checking" {
    var memory = [_]u8{0} **100;

    const result1 = MemoryOps.copy(&memory, 150, 10, 5);
    try testing.expectError(error.OutOfBoundsMemoryAccess, result1);

    const result2 = MemoryOps.copy(&memory, 10, 150, 5);
    try testing.expectError(error.OutOfBoundsMemoryAccess, result2);

    const result3 = MemoryOps.copy(&memory, 98, 10, 5);
    try testing.expectError(error.OutOfBoundsMemoryAccess, result3);
}

test "memory.fill - basic" {
    var memory = [_]u8{0} **100;

    try MemoryOps.fill(&memory, 10, 0x42, 10);

    for (memory[10..20]) |byte| {
        try testing.expectEqual(@as(u8, 0x42), byte);
    }
}

test "memory.fill - full region" {
    var memory = [_]u8{0} **100;

    try MemoryOps.fill(&memory, 0, 0xFF, 100);

    for (memory) |byte| {
        try testing.expectEqual(@as(u8, 0xFF), byte);
    }
}

test "memory.fill - bounds checking" {
    var memory = [_]u8{0} **100;

    const result1 = MemoryOps.fill(&memory, 150, 0x42, 5);
    try testing.expectError(error.OutOfBoundsMemoryAccess, result1);

    const result2 = MemoryOps.fill(&memory, 98, 0x42, 5);
    try testing.expectError(error.OutOfBoundsMemoryAccess, result2);
}

test "memory.init - basic" {
    var memory = [_]u8{0} **100;
    const data = [_]u8{ 10, 20, 30, 40, 50 };

    try MemoryOps.init(&memory, &data, 10, 0, 5);

    try testing.expectEqualSlices(u8, &data, memory[10..15]);
}

test "memory.init - partial segment" {
    var memory = [_]u8{0} **100;
    const data = [_]u8{ 10, 20, 30, 40, 50, 60, 70 };

    try MemoryOps.init(&memory, &data, 10, 2, 3);

    try testing.expectEqualSlices(u8, &[_]u8{ 30, 40, 50 }, memory[10..13]);
}

test "memory.init - bounds checking" {
    var memory = [_]u8{0} **100;
    const data = [_]u8{ 10, 20, 30, 40, 50 };

    const result1 = MemoryOps.init(&memory, &data, 150, 0, 5);
    try testing.expectError(error.OutOfBoundsMemoryAccess, result1);

    const result2 = MemoryOps.init(&memory, &data, 10, 3, 5);
    try testing.expectError(error.OutOfBoundsMemoryAccess, result2);
}

test "memory.zero - basic" {
    var memory = [_]u8{0xFF} **100;

    try MemoryOps.zero(&memory, 10, 20);

    for (memory[10..30]) |byte| {
        try testing.expectEqual(@as(u8, 0), byte);
    }
}

// Table Operations Tests

test "table.copy - non-overlapping" {
    var table = [_]Value{Value{ .i32 = 0 }} **100;
    for (10..15) |i| {
        table[i] = Value{ .i32 = @intCast(i) };
    }

    try TableOps.copy(&table, &table, 20, 10, 5);

    for (20..25, 10..15) |dst_i, src_i| {
        try testing.expectEqual(table[src_i].i32, table[dst_i].i32);
    }
}

test "table.copy - overlapping forward" {
    var table = [_]Value{Value{ .i32 = 0 }} **100;
    for (10..15) |i| {
        table[i] = Value{ .i32 = @intCast(i) };
    }

    try TableOps.copy(&table, &table, 12, 10, 5);

    try testing.expectEqual(@as(i32, 10), table[12].i32);
    try testing.expectEqual(@as(i32, 14), table[16].i32);
}

test "table.copy - different tables" {
    var dst_table = [_]Value{Value{ .i32 = 0 }} **50;
    var src_table = [_]Value{Value{ .i32 = 0 }} **50;
    
    for (10..15) |i| {
        src_table[i] = Value{ .i32 = @intCast(i) };
    }

    try TableOps.copy(&dst_table, &src_table, 20, 10, 5);

    for (20..25, 10..15) |dst_i, src_i| {
        try testing.expectEqual(src_table[src_i].i32, dst_table[dst_i].i32);
    }
}

test "table.fill - basic" {
    var table = [_]Value{Value{ .i32 = 0 }} **100;
    const fill_value = Value{ .i32 = 42 };

    try TableOps.fill(&table, 10, fill_value, 10);

    for (table[10..20]) |val| {
        try testing.expectEqual(@as(i32, 42), val.i32);
    }
}

test "table.init - basic" {
    var table = [_]Value{Value{ .i32 = 0 }} **100;
    const elems = [_]Value{
        Value{ .i32 = 10 },
        Value{ .i32 = 20 },
        Value{ .i32 = 30 },
    };

    try TableOps.init(&table, &elems, 10, 0, 3);

    try testing.expectEqual(@as(i32, 10), table[10].i32);
    try testing.expectEqual(@as(i32, 20), table[11].i32);
    try testing.expectEqual(@as(i32, 30), table[12].i32);
}

test "table.size - basic" {
    const table = [_]Value{Value{ .i32 = 0 }} **50;
    const size = TableOps.size(&table);
    try testing.expectEqual(@as(u32, 50), size);
}

test "table.grow - basic" {
    const allocator = testing.allocator;
    var table = std.ArrayList(Value).init(allocator);
    defer table.deinit();

    // Add initial elements
    try table.append(Value{ .i32 = 1 });
    try table.append(Value{ .i32 = 2 });

    const old_size = try TableOps.grow(allocator, &table, 3, Value{ .i32 = 0 });
    
    try testing.expectEqual(@as(i32, 2), old_size);
    try testing.expectEqual(@as(usize, 5), table.items.len);
}

// Data Segment Manager Tests

test "data segment manager - add and get" {
    const allocator = testing.allocator;
    var mgr = DataSegmentManager.init(allocator);
    defer mgr.deinit();

    const data = [_]u8{ 1, 2, 3, 4, 5 };
    const idx = try mgr.addSegment(&data);

    const segment = try mgr.get(idx);
    try testing.expectEqualSlices(u8, &data, segment);
}

test "data segment manager - drop" {
    const allocator = testing.allocator;
    var mgr = DataSegmentManager.init(allocator);
    defer mgr.deinit();

    const data = [_]u8{ 1, 2, 3, 4, 5 };
    const idx = try mgr.addSegment(&data);

    try mgr.drop(idx);

    const result = mgr.get(idx);
    try testing.expectError(error.DataSegmentDropped, result);
}

test "data segment manager - invalid index" {
    const allocator = testing.allocator;
    var mgr = DataSegmentManager.init(allocator);
    defer mgr.deinit();

    const result = mgr.get(99);
    try testing.expectError(error.InvalidDataSegment, result);
}

// Element Segment Manager Tests

test "elem segment manager - add and get" {
    const allocator = testing.allocator;
    var mgr = ElemSegmentManager.init(allocator);
    defer mgr.deinit();

    const elems = [_]Value{
        Value{ .i32 = 1 },
        Value{ .i32 = 2 },
        Value{ .i32 = 3 },
    };
    const idx = try mgr.addSegment(&elems);

    const segment = try mgr.get(idx);
    try testing.expectEqual(@as(usize, 3), segment.len);
    try testing.expectEqual(@as(i32, 1), segment[0].i32);
}

test "elem segment manager - drop" {
    const allocator = testing.allocator;
    var mgr = ElemSegmentManager.init(allocator);
    defer mgr.deinit();

    const elems = [_]Value{Value{ .i32 = 1 }};
    const idx = try mgr.addSegment(&elems);

    try mgr.drop(idx);

    const result = mgr.get(idx);
    try testing.expectError(error.ElemSegmentDropped, result);
}

// Bulk Operations Tests

test "bulk operations - memory.init" {
    const allocator = testing.allocator;
    var bulk_ops = BulkOperations.init(allocator);
    defer bulk_ops.deinit();

    const data = [_]u8{ 10, 20, 30, 40, 50 };
    const data_idx = try bulk_ops.data_mgr.addSegment(&data);

    var memory = [_]u8{0} **100;
    try bulk_ops.memoryInit(&memory, data_idx, 10, 0, 5);

    try testing.expectEqualSlices(u8, &data, memory[10..15]);
}

test "bulk operations - table.init" {
    const allocator = testing.allocator;
    var bulk_ops = BulkOperations.init(allocator);
    defer bulk_ops.deinit();

    const elems = [_]Value{
        Value{ .i32 = 100 },
        Value{ .i32 = 200 },
    };
    const elem_idx = try bulk_ops.elem_mgr.addSegment(&elems);

    var table = [_]Value{Value{ .i32 = 0 }} **50;
    try bulk_ops.tableInit(&table, elem_idx, 10, 0, 2);

    try testing.expectEqual(@as(i32, 100), table[10].i32);
    try testing.expectEqual(@as(i32, 200), table[11].i32);
}

// Performance Tests

test "memory operations - large copy" {
    var memory = try testing.allocator.alloc(u8, 1024 * 1024);
    defer testing.allocator.free(memory);

    // Fill source region
    @memset(memory[0..512 * 1024], 0x42);

    // Copy large region
    try MemoryOps.copy(memory, 512 * 1024, 0, 512 * 1024);

    // Verify
    for (memory[512 * 1024 ..]) |byte| {
        try testing.expectEqual(@as(u8, 0x42), byte);
    }
}

test "memory operations - large fill" {
    var memory = try testing.allocator.alloc(u8, 1024 * 1024);
    defer testing.allocator.free(memory);

    try MemoryOps.fill(memory, 0, 0xFF, @intCast(memory.len));

    for (memory) |byte| {
        try testing.expectEqual(@as(u8, 0xFF), byte);
    }
}
