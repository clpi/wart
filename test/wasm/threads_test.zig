const std = @import("std");
const testing = std.testing;
const threads = @import("../../src/wasm/threads.zig");
const Value = @import("../../src/wasm/value.zig").Value;

// Test SharedMemory
test "shared memory - creation and initialization" {
    const allocator = testing.allocator;

    var mem = try threads.SharedMemory.init(allocator, 1, 10, true);
    defer mem.deinit();

    try testing.expect(mem.is_shared);
    try testing.expectEqual(@as(usize, 65536), mem.memory.len);
    try testing.expectEqual(@as(u32, 10), mem.max_pages);
}

test "shared memory - grow within limits" {
    const allocator = testing.allocator;

    var mem = try threads.SharedMemory.init(allocator, 1, 10, true);
    defer mem.deinit();

    const old_pages = try mem.grow(2);
    try testing.expectEqual(@as(u32, 1), old_pages);
    try testing.expectEqual(@as(usize, 3 * 65536), mem.memory.len);
}

test "shared memory - grow beyond limits fails" {
    const allocator = testing.allocator;

    var mem = try threads.SharedMemory.init(allocator, 1, 10, true);
    defer mem.deinit();

    const result = mem.grow(10); // Would exceed max_pages
    try testing.expectError(error.MemoryGrowFailed, result);
}

test "shared memory - atomic load u32" {
    const allocator = testing.allocator;

    var mem = try threads.SharedMemory.init(allocator, 1, 10, true);
    defer mem.deinit();

    // Write a value directly
    std.mem.writeInt(u32, mem.memory[0..4], 42, .little);

    const value = try mem.atomicLoad(0, u32);
    try testing.expectEqual(@as(u32, 42), value);
}

test "shared memory - atomic store u32" {
    const allocator = testing.allocator;

    var mem = try threads.SharedMemory.init(allocator, 1, 10, true);
    defer mem.deinit();

    try mem.atomicStore(0, u32, 42);

    const value = std.mem.readInt(u32, mem.memory[0..4], .little);
    try testing.expectEqual(@as(u32, 42), value);
}

test "shared memory - atomic RMW add" {
    const allocator = testing.allocator;

    var mem = try threads.SharedMemory.init(allocator, 1, 10, true);
    defer mem.deinit();

    // Initialize with 10
    std.mem.writeInt(u32, mem.memory[0..4], 10, .little);

    const old = try mem.atomicRMW(0, u32, 5, .add);
    try testing.expectEqual(@as(u32, 10), old);

    const new = std.mem.readInt(u32, mem.memory[0..4], .little);
    try testing.expectEqual(@as(u32, 15), new);
}

test "shared memory - atomic RMW sub" {
    const allocator = testing.allocator;

    var mem = try threads.SharedMemory.init(allocator, 1, 10, true);
    defer mem.deinit();

    std.mem.writeInt(u32, mem.memory[0..4], 20, .little);

    const old = try mem.atomicRMW(0, u32, 7, .sub);
    try testing.expectEqual(@as(u32, 20), old);

    const new = std.mem.readInt(u32, mem.memory[0..4], .little);
    try testing.expectEqual(@as(u32, 13), new);
}

test "shared memory - atomic RMW and" {
    const allocator = testing.allocator;

    var mem = try threads.SharedMemory.init(allocator, 1, 10, true);
    defer mem.deinit();

    std.mem.writeInt(u32, mem.memory[0..4], 0xFF00, .little);

    const old = try mem.atomicRMW(0, u32, 0x00FF, .and_);
    try testing.expectEqual(@as(u32, 0xFF00), old);

    const new = std.mem.readInt(u32, mem.memory[0..4], .little);
    try testing.expectEqual(@as(u32, 0), new);
}

test "shared memory - atomic RMW or" {
    const allocator = testing.allocator;

    var mem = try threads.SharedMemory.init(allocator, 1, 10, true);
    defer mem.deinit();

    std.mem.writeInt(u32, mem.memory[0..4], 0xFF00, .little);

    const old = try mem.atomicRMW(0, u32, 0x00FF, .or_);
    try testing.expectEqual(@as(u32, 0xFF00), old);

    const new = std.mem.readInt(u32, mem.memory[0..4], .little);
    try testing.expectEqual(@as(u32, 0xFFFF), new);
}

test "shared memory - atomic RMW xor" {
    const allocator = testing.allocator;

    var mem = try threads.SharedMemory.init(allocator, 1, 10, true);
    defer mem.deinit();

    std.mem.writeInt(u32, mem.memory[0..4], 0xFFFF, .little);

    const old = try mem.atomicRMW(0, u32, 0xFF00, .xor);
    try testing.expectEqual(@as(u32, 0xFFFF), old);

    const new = std.mem.readInt(u32, mem.memory[0..4], .little);
    try testing.expectEqual(@as(u32, 0x00FF), new);
}

test "shared memory - atomic RMW exchange" {
    const allocator = testing.allocator;

    var mem = try threads.SharedMemory.init(allocator, 1, 10, true);
    defer mem.deinit();

    std.mem.writeInt(u32, mem.memory[0..4], 42, .little);

    const old = try mem.atomicRMW(0, u32, 100, .xchg);
    try testing.expectEqual(@as(u32, 42), old);

    const new = std.mem.readInt(u32, mem.memory[0..4], .little);
    try testing.expectEqual(@as(u32, 100), new);
}

test "shared memory - atomic compare exchange success" {
    const allocator = testing.allocator;

    var mem = try threads.SharedMemory.init(allocator, 1, 10, true);
    defer mem.deinit();

    std.mem.writeInt(u32, mem.memory[0..4], 42, .little);

    const result = try mem.atomicCompareExchange(0, u32, 42, 100);
    try testing.expectEqual(@as(u32, 42), result);

    const new = std.mem.readInt(u32, mem.memory[0..4], .little);
    try testing.expectEqual(@as(u32, 100), new);
}

test "shared memory - atomic compare exchange failure" {
    const allocator = testing.allocator;

    var mem = try threads.SharedMemory.init(allocator, 1, 10, true);
    defer mem.deinit();

    std.mem.writeInt(u32, mem.memory[0..4], 42, .little);

    const result = try mem.atomicCompareExchange(0, u32, 99, 100);
    try testing.expectEqual(@as(u32, 42), result);

    const value = std.mem.readInt(u32, mem.memory[0..4], .little);
    try testing.expectEqual(@as(u32, 42), value); // Unchanged
}

// Test ThreadPool
test "thread pool - initialization" {
    const allocator = testing.allocator;

    var pool = threads.ThreadPool.init(allocator, 4);
    defer pool.deinit();

    try testing.expectEqual(@as(u32, 4), pool.max_threads);
    try testing.expectEqual(@as(usize, 0), pool.threads.items.len);
}

test "thread pool - spawn thread" {
    const allocator = testing.allocator;

    var pool = threads.ThreadPool.init(allocator, 4);
    defer pool.deinit();

    const args = [_]Value{Value{ .i32 = 42 }};
    const thread_id = try pool.spawnThread(1, &args);

    try testing.expectEqual(@as(u32, 0), thread_id);
    try testing.expectEqual(@as(usize, 1), pool.threads.items.len);
}

test "thread pool - spawn multiple threads" {
    const allocator = testing.allocator;

    var pool = threads.ThreadPool.init(allocator, 4);
    defer pool.deinit();

    const args = [_]Value{};
    _ = try pool.spawnThread(1, &args);
    _ = try pool.spawnThread(2, &args);
    _ = try pool.spawnThread(3, &args);

    try testing.expectEqual(@as(usize, 3), pool.threads.items.len);
}

test "thread pool - exceed max threads" {
    const allocator = testing.allocator;

    var pool = threads.ThreadPool.init(allocator, 2);
    defer pool.deinit();

    const args = [_]Value{};
    _ = try pool.spawnThread(1, &args);
    _ = try pool.spawnThread(2, &args);

    const result = pool.spawnThread(3, &args);
    try testing.expectError(error.TooManyThreads, result);
}

test "thread pool - get thread count" {
    const allocator = testing.allocator;

    var pool = threads.ThreadPool.init(allocator, 4);
    defer pool.deinit();

    try testing.expectEqual(@as(u32, 0), pool.getThreadCount());

    const args = [_]Value{};
    _ = try pool.spawnThread(1, &args);

    try testing.expectEqual(@as(u32, 1), pool.getThreadCount());
}

// Test WaitQueue
test "wait queue - initialization" {
    const allocator = testing.allocator;

    var queue = threads.WaitQueue.init(allocator);
    defer queue.deinit();

    try testing.expectEqual(@as(usize, 0), queue.waiters.items.len);
}

test "wait queue - wait adds entry" {
    const allocator = testing.allocator;

    var queue = threads.WaitQueue.init(allocator);
    defer queue.deinit();

    const result = try queue.wait(0x1000, 0, 1000000);
    try testing.expectEqual(@as(i32, 0), result);
    try testing.expectEqual(@as(usize, 1), queue.waiters.items.len);
}

test "wait queue - notify removes waiters" {
    const allocator = testing.allocator;

    var queue = threads.WaitQueue.init(allocator);
    defer queue.deinit();

    _ = try queue.wait(0x1000, 0, 1000000);
    _ = try queue.wait(0x1000, 1, 1000000);
    _ = try queue.wait(0x2000, 2, 1000000);

    const notified = try queue.notify(0x1000, 1);
    try testing.expectEqual(@as(u32, 1), notified);
    try testing.expectEqual(@as(usize, 2), queue.waiters.items.len);
}

test "wait queue - notify all" {
    const allocator = testing.allocator;

    var queue = threads.WaitQueue.init(allocator);
    defer queue.deinit();

    _ = try queue.wait(0x1000, 0, 1000000);
    _ = try queue.wait(0x1000, 1, 1000000);
    _ = try queue.wait(0x1000, 2, 1000000);

    const notified = try queue.notifyAll(0x1000);
    try testing.expectEqual(@as(u32, 3), notified);
    try testing.expectEqual(@as(usize, 0), queue.waiters.items.len);
}

// Test ThreadLocal
test "thread local - initialization" {
    const allocator = testing.allocator;

    var tls = threads.ThreadLocal.init(allocator);
    defer tls.deinit();

    try testing.expectEqual(@as(usize, 0), tls.storage.count());
}

test "thread local - set and get" {
    const allocator = testing.allocator;

    var tls = threads.ThreadLocal.init(allocator);
    defer tls.deinit();

    try tls.set(0, "key1", Value{ .i32 = 42 });

    const value = tls.get(0, "key1");
    try testing.expect(value != null);
    try testing.expectEqual(@as(i32, 42), value.?.i32);
}

test "thread local - multiple threads" {
    const allocator = testing.allocator;

    var tls = threads.ThreadLocal.init(allocator);
    defer tls.deinit();

    try tls.set(0, "key", Value{ .i32 = 1 });
    try tls.set(1, "key", Value{ .i32 = 2 });
    try tls.set(2, "key", Value{ .i32 = 3 });

    try testing.expectEqual(@as(i32, 1), tls.get(0, "key").?.i32);
    try testing.expectEqual(@as(i32, 2), tls.get(1, "key").?.i32);
    try testing.expectEqual(@as(i32, 3), tls.get(2, "key").?.i32);
}

test "thread local - remove" {
    const allocator = testing.allocator;

    var tls = threads.ThreadLocal.init(allocator);
    defer tls.deinit();

    try tls.set(0, "key1", Value{ .i32 = 42 });
    try tls.remove(0, "key1");

    const value = tls.get(0, "key1");
    try testing.expect(value == null);
}
