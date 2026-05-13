const std = @import("std");
const testing = std.testing;
const promises = @import("../../src/wasm/promises.zig");
const Value = @import("../../src/wasm/value.zig").Value;

const Promise = promises.Promise;
const AsyncRuntime = promises.AsyncRuntime;
const AsyncFunction = promises.AsyncFunction;

// Test promise creation and states
test "promise creation - initial state is pending" {
    const allocator = testing.allocator;

    const promise = try Promise.init(allocator);
    defer promise.deinit();

    try testing.expectEqual(promises.PromiseState.pending, promise.state);
    try testing.expect(promise.result == null);
    try testing.expect(promise.error_msg == null);
}

test "promise resolve - state becomes fulfilled" {
    const allocator = testing.allocator;

    const promise = try Promise.init(allocator);
    defer promise.deinit();

    const value = Value{ .i32 = 42 };
    try promise.resolve(value);

    try testing.expectEqual(promises.PromiseState.fulfilled, promise.state);
    try testing.expect(promise.result != null);
    try testing.expectEqual(@as(i32, 42), promise.result.?.i32);
}

test "promise reject - state becomes rejected" {
    const allocator = testing.allocator;

    const promise = try Promise.init(allocator);
    defer promise.deinit();

    try promise.reject("Test error");

    try testing.expectEqual(promises.PromiseState.rejected, promise.state);
    try testing.expect(promise.error_msg != null);
    try testing.expectEqualStrings("Test error", promise.error_msg.?);
}

test "promise resolve twice - returns error" {
    const allocator = testing.allocator;

    const promise = try Promise.init(allocator);
    defer promise.deinit();

    try promise.resolve(Value{ .i32 = 42 });

    const result = promise.resolve(Value{ .i32 = 100 });
    try testing.expectError(error.PromiseAlreadySettled, result);
}

test "promise reject twice - returns error" {
    const allocator = testing.allocator;

    const promise = try Promise.init(allocator);
    defer promise.deinit();

    try promise.reject("First error");

    const result = promise.reject("Second error");
    try testing.expectError(error.PromiseAlreadySettled, result);
}

test "promise await - fulfilled promise returns value" {
    const allocator = testing.allocator;

    const promise = try Promise.init(allocator);
    defer promise.deinit();

    const value = Value{ .i32 = 42 };
    try promise.resolve(value);

    const result = try promise.await();
    try testing.expectEqual(@as(i32, 42), result.i32);
}

test "promise await - rejected promise returns error" {
    const allocator = testing.allocator;

    const promise = try Promise.init(allocator);
    defer promise.deinit();

    try promise.reject("Test error");

    const result = promise.await();
    try testing.expectError(error.PromiseRejected, result);
}

test "promise await - pending promise returns error" {
    const allocator = testing.allocator;

    const promise = try Promise.init(allocator);
    defer promise.deinit();

    const result = promise.await();
    try testing.expectError(error.PromisePending, result);
}

test "promise then callback - added successfully" {
    const allocator = testing.allocator;

    const promise = try Promise.init(allocator);
    defer promise.deinit();

    const callback = Promise.Callback{
        .func_idx = 1,
        .context = null,
    };

    try promise.then(callback);
    try testing.expectEqual(@as(usize, 1), promise.then_callbacks.items.len);
}

test "promise catch callback - added successfully" {
    const allocator = testing.allocator;

    const promise = try Promise.init(allocator);
    defer promise.deinit();

    const callback = Promise.Callback{
        .func_idx = 2,
        .context = null,
    };

    try promise.@"catch"(callback);
    try testing.expectEqual(@as(usize, 1), promise.catch_callbacks.items.len);
}

test "promise finally callback - added successfully" {
    const allocator = testing.allocator;

    const promise = try Promise.init(allocator);
    defer promise.deinit();

    const callback = Promise.Callback{
        .func_idx = 3,
        .context = null,
    };

    try promise.finally(callback);
    try testing.expectEqual(@as(usize, 1), promise.finally_callbacks.items.len);
}

// Test Promise.all()
test "promise all - all resolved returns resolved" {
    const allocator = testing.allocator;

    var p1 = try Promise.init(allocator);
    defer p1.deinit();
    try p1.resolve(Value{ .i32 = 1 });

    var p2 = try Promise.init(allocator);
    defer p2.deinit();
    try p2.resolve(Value{ .i32 = 2 });

    var p3 = try Promise.init(allocator);
    defer p3.deinit();
    try p3.resolve(Value{ .i32 = 3 });

    const promises_array = [_]*Promise{ p1, p2, p3 };
    const result = try promises.all(allocator, &promises_array);
    defer result.deinit();

    try testing.expectEqual(promises.PromiseState.fulfilled, result.state);
}

test "promise all - one rejected returns rejected" {
    const allocator = testing.allocator;

    var p1 = try Promise.init(allocator);
    defer p1.deinit();
    try p1.resolve(Value{ .i32 = 1 });

    var p2 = try Promise.init(allocator);
    defer p2.deinit();
    try p2.reject("Error in p2");

    var p3 = try Promise.init(allocator);
    defer p3.deinit();
    try p3.resolve(Value{ .i32 = 3 });

    const promises_array = [_]*Promise{ p1, p2, p3 };
    const result = try promises.all(allocator, &promises_array);
    defer result.deinit();

    try testing.expectEqual(promises.PromiseState.rejected, result.state);
}

// Test Promise.race()
test "promise race - first fulfilled wins" {
    const allocator = testing.allocator;

    var p1 = try Promise.init(allocator);
    defer p1.deinit();
    try p1.resolve(Value{ .i32 = 1 });

    var p2 = try Promise.init(allocator);
    defer p2.deinit();
    // p2 is pending

    var p3 = try Promise.init(allocator);
    defer p3.deinit();
    // p3 is pending

    const promises_array = [_]*Promise{ p1, p2, p3 };
    const result = try promises.race(allocator, &promises_array);
    defer result.deinit();

    try testing.expectEqual(promises.PromiseState.fulfilled, result.state);
    try testing.expectEqual(@as(i32, 1), result.result.?.i32);
}

test "promise race - first rejected wins" {
    const allocator = testing.allocator;

    var p1 = try Promise.init(allocator);
    defer p1.deinit();
    try p1.reject("First error");

    var p2 = try Promise.init(allocator);
    defer p2.deinit();
    // p2 is pending

    const promises_array = [_]*Promise{ p1, p2 };
    const result = try promises.race(allocator, &promises_array);
    defer result.deinit();

    try testing.expectEqual(promises.PromiseState.rejected, result.state);
}

// Test Promise.any()
test "promise any - first fulfilled wins" {
    const allocator = testing.allocator;

    var p1 = try Promise.init(allocator);
    defer p1.deinit();
    try p1.reject("Error 1");

    var p2 = try Promise.init(allocator);
    defer p2.deinit();
    try p2.resolve(Value{ .i32 = 2 });

    var p3 = try Promise.init(allocator);
    defer p3.deinit();
    try p3.reject("Error 3");

    const promises_array = [_]*Promise{ p1, p2, p3 };
    const result = try promises.any(allocator, &promises_array);
    defer result.deinit();

    try testing.expectEqual(promises.PromiseState.fulfilled, result.state);
    try testing.expectEqual(@as(i32, 2), result.result.?.i32);
}

test "promise any - all rejected returns rejected" {
    const allocator = testing.allocator;

    var p1 = try Promise.init(allocator);
    defer p1.deinit();
    try p1.reject("Error 1");

    var p2 = try Promise.init(allocator);
    defer p2.deinit();
    try p2.reject("Error 2");

    const promises_array = [_]*Promise{ p1, p2 };
    const result = try promises.any(allocator, &promises_array);
    defer result.deinit();

    try testing.expectEqual(promises.PromiseState.rejected, result.state);
}

// Test Promise.allSettled()
test "promise allSettled - waits for all to settle" {
    const allocator = testing.allocator;

    var p1 = try Promise.init(allocator);
    defer p1.deinit();
    try p1.resolve(Value{ .i32 = 1 });

    var p2 = try Promise.init(allocator);
    defer p2.deinit();
    try p2.reject("Error");

    var p3 = try Promise.init(allocator);
    defer p3.deinit();
    try p3.resolve(Value{ .i32 = 3 });

    const promises_array = [_]*Promise{ p1, p2, p3 };
    const result = try promises.allSettled(allocator, &promises_array);
    defer result.deinit();

    try testing.expectEqual(promises.PromiseState.fulfilled, result.state);
    try testing.expectEqual(@as(i32, 3), result.result.?.i32);
}

// Test helper functions
test "promise resolved - creates fulfilled promise" {
    const allocator = testing.allocator;

    const promise = try promises.resolved(allocator, Value{ .i32 = 42 });
    defer promise.deinit();

    try testing.expectEqual(promises.PromiseState.fulfilled, promise.state);
    try testing.expectEqual(@as(i32, 42), promise.result.?.i32);
}

test "promise rejected - creates rejected promise" {
    const allocator = testing.allocator;

    const promise = try promises.rejected(allocator, "Test error");
    defer promise.deinit();

    try testing.expectEqual(promises.PromiseState.rejected, promise.state);
    try testing.expectEqualStrings("Test error", promise.error_msg.?);
}

// Test AsyncFunction
test "async function - creation and initialization" {
    const allocator = testing.allocator;

    const func = try AsyncFunction.init(allocator, 5);
    defer func.deinit();

    try testing.expectEqual(@as(u32, 5), func.func_idx);
    try testing.expect(!func.is_running);
    try testing.expect(func.result == null);
}

test "async function - execute returns promise" {
    const allocator = testing.allocator;

    const func = try AsyncFunction.init(allocator, 5);
    defer func.deinit();

    const promise = try func.execute();
    // Don't defer promise.deinit() because func owns it

    try testing.expectEqual(promises.PromiseState.pending, promise.state);
}

test "async function - execute twice returns error" {
    const allocator = testing.allocator;

    const func = try AsyncFunction.init(allocator, 5);
    defer func.deinit();

    // Set is_running manually for testing
    func.is_running = true;

    const result = func.execute();
    try testing.expectError(error.AlreadyRunning, result);
}

// Test AsyncRuntime
test "async runtime - initialization" {
    const allocator = testing.allocator;

    var runtime = AsyncRuntime.init(allocator);
    defer runtime.deinit();

    try testing.expectEqual(@as(usize, 0), runtime.pending_promises.items.len);
    try testing.expectEqual(@as(usize, 0), runtime.async_functions.items.len);
    try testing.expectEqual(@as(usize, 0), runtime.microtask_queue.items.len);
}

test "async runtime - register promise" {
    const allocator = testing.allocator;

    var runtime = AsyncRuntime.init(allocator);
    defer runtime.deinit();

    const promise = try Promise.init(allocator);
    // Don't defer - runtime will clean it up

    try runtime.registerPromise(promise);
    try testing.expectEqual(@as(usize, 1), runtime.pending_promises.items.len);
}

test "async runtime - register async function" {
    const allocator = testing.allocator;

    var runtime = AsyncRuntime.init(allocator);
    defer runtime.deinit();

    const func = try AsyncFunction.init(allocator, 5);
    // Don't defer - runtime will clean it up

    try runtime.registerAsyncFunction(func);
    try testing.expectEqual(@as(usize, 1), runtime.async_functions.items.len);
}

test "async runtime - has pending work" {
    const allocator = testing.allocator;

    var runtime = AsyncRuntime.init(allocator);
    defer runtime.deinit();

    try testing.expect(!runtime.hasPendingWork());

    const promise = try Promise.init(allocator);
    try runtime.registerPromise(promise);

    try testing.expect(runtime.hasPendingWork());
}

test "async runtime - run event loop removes settled promises" {
    const allocator = testing.allocator;

    var runtime = AsyncRuntime.init(allocator);
    defer runtime.deinit();

    const promise = try Promise.init(allocator);
    try promise.resolve(Value{ .i32 = 42 });
    try runtime.registerPromise(promise);

    try testing.expectEqual(@as(usize, 1), runtime.pending_promises.items.len);

    try runtime.runEventLoop();

    try testing.expectEqual(@as(usize, 0), runtime.pending_promises.items.len);
}
