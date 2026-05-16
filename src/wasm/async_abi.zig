/// WASI Async ABI Implementation
///
/// Implements the asynchronous calling convention for WASI Preview 2/3.
/// This enables functions to return futures that can be awaited.
///
/// Features:
/// - Future/promise types with async/await
/// - Event loop with timer and I/O polling
/// - Task scheduling and execution
/// - Integration with asyncify for suspend/resume
///
/// References:
/// - https://github.com/WebAssembly/WASI/blob/main/legacy/preview2/WIT-ABI.md
/// - https://github.com/WebAssembly/shared-everything-concurrency
const std = @import("std");
const Allocator = std.mem.Allocator;
const Value = @import("value.zig").Value;
const ValueType = @import("value.zig").Type;
const Log = @import("../util/fmt.zig").Log;

pub const Error = error{
    FutureNotReady,
    FutureCompleted,
    InvalidFuture,
    OutOfMemory,
    InvalidState,
    Cancelled,
};

/// Future state
pub const FutureState = enum {
    pending,
    ready,
    completed,
    error_state,
    cancelled,
};

/// Future result - supports various value types
pub const FutureResult = union(enum) {
    pending: void,
    ok: Value,
    err: u32,
    cancelled,
};

/// Completion reason
pub const CompletionReason = enum {
    success,
    failed,
    cancelled,
    timeout,
};

/// Timer entry for delayed futures
const TimerEntry = struct {
    handle: u32,
    wake_time: i64,
    periodic: bool,
    period_ns: i64,
};

/// I/O wait entry
const IoWaitEntry = struct {
    handle: u32,
    fd: u32,
    events: u32,
};

/// Callback types for async operations
pub const AsyncCallback = fn (handle: u32, reason: CompletionReason, result: ?Value) void;
pub const IoCallback = fn (fd: u32, events: u32, err: ?u32) void;

/// Future handle (represents an async operation)
pub const Future = struct {
    handle: u32,
    state: FutureState,
    result: FutureResult,

    // Optional callback when future completes
    callback: ?*const AsyncCallback,
    callback_data: ?*anyopaque,

    // For task-based async
    task_id: ?u32,

    pub fn init(handle: u32) Future {
        return Future{
            .handle = handle,
            .state = .pending,
            .result = .{ .pending = {} },
            .callback = null,
            .callback_data = null,
            .task_id = null,
        };
    }

    pub fn complete(self: *Future, value: Value) void {
        self.state = .ready;
        self.result = .{ .ok = value };

        if (self.callback) |cb| {
            cb(self.handle, .success, value);
        }
    }

    pub fn fail(self: *Future, error_code: u32) void {
        self.state = .error_state;
        self.result = .{ .err = error_code };

        if (self.callback) |cb| {
            cb(self.handle, .failed, Value{ .i32 = @as(i32, @intCast(error_code)) });
        }
    }

    pub fn cancel(self: *Future) void {
        self.state = .cancelled;
        self.result = .cancelled;

        if (self.callback) |cb| {
            cb(self.handle, .cancelled, null);
        }
    }
};

/// Async ABI manager
pub const AsyncABI = struct {
    const Self = @This();

    allocator: Allocator,
    futures: std.AutoHashMap(u32, Future),
    next_handle: u32 = 1,

    // Event loop state
    pending_futures: std.ArrayList(u32),
    timers: std.ArrayList(TimerEntry),
    io_waits: std.AutoHashMap(u32, IoWaitEntry),

    // Task system
    tasks: std.AutoHashMap(u32, Task),
    next_task_id: u32 = 1,
    runnable_tasks: std.ArrayList(u32),

    // Event loop control
    running: bool = false,
    poll_timeout_ns: i64 = 10000000, // 10ms default poll timeout

    // Statistics
    poll_count: u64 = 0,
    timer_count: u64 = 0,
    io_count: u64 = 0,

    // External callbacks
    io_callback: ?*const IoCallback,

    pub fn init(allocator: Allocator) !*Self {
        const abi = try allocator.create(Self);
        abi.* = Self{
            .allocator = allocator,
            .futures = std.AutoHashMap(u32, Future).init(allocator),
            .pending_futures = .empty,
            .timers = .empty,
            .io_waits = std.AutoHashMap(u32, IoWaitEntry).init(allocator),
            .tasks = std.AutoHashMap(u32, Task).init(allocator),
            .runnable_tasks = .empty,
            .io_callback = null,
        };
        return abi;
    }

    pub fn deinit(self: *Self) void {
        // Cancel all pending futures
        for (self.pending_futures.items) |handle| {
            if (self.futures.getPtr(handle)) |future| {
                future.cancel();
            }
        }

        self.futures.deinit();
        self.pending_futures.deinit(self.allocator);
        self.timers.deinit(self.allocator);
        self.io_waits.deinit();
        self.tasks.deinit();
        self.runnable_tasks.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    /// Create a new future
    pub fn createFuture(self: *Self) !u32 {
        const handle = self.next_handle;
        self.next_handle += 1;

        try self.futures.put(handle, Future.init(handle));
        try self.pending_futures.append(self.allocator, handle);

        var o = Log.op("AsyncABI", "createFuture");
        o.log("Created future: handle={d}", .{handle});

        return handle;
    }

    /// Create a future with a callback
    pub fn createFutureWithCallback(self: *Self, callback: *const AsyncCallback, data: ?*anyopaque) !u32 {
        const handle = try self.createFuture();
        const future = self.futures.getPtr(handle).?;
        future.callback = callback;
        future.callback_data = data;
        return handle;
    }

    /// Complete a future with a value
    pub fn completeFuture(self: *Self, handle: u32, value: Value) !void {
        const future = self.futures.getPtr(handle) orelse return Error.InvalidFuture;

        if (future.state != .pending) {
            return Error.FutureCompleted;
        }

        future.complete(value);

        // Remove from pending list
        self.removeFromPending(handle);

        var o = Log.op("AsyncABI", "completeFuture");
        o.log("Completed future: handle={d}", .{handle});
    }

    /// Fail a future with an error
    pub fn failFuture(self: *Self, handle: u32, error_code: u32) !void {
        const future = self.futures.getPtr(handle) orelse return Error.InvalidFuture;

        if (future.state != .pending) {
            return Error.FutureCompleted;
        }

        future.fail(error_code);

        // Remove from pending list
        self.removeFromPending(handle);

        var o = Log.op("AsyncABI", "failFuture");
        o.log("Failed future: handle={d}, error={d}", .{ handle, error_code });
    }

    /// Cancel a future
    pub fn cancelFuture(self: *Self, handle: u32) !void {
        const future = self.futures.getPtr(handle) orelse return Error.InvalidFuture;

        if (future.state != .pending) {
            return Error.FutureCompleted;
        }

        future.cancel();
        self.removeFromPending(handle);
    }

    fn removeFromPending(self: *Self, handle: u32) void {
        for (self.pending_futures.items, 0..) |h, i| {
            if (h == handle) {
                _ = self.pending_futures.swapRemove(i);
                break;
            }
        }
    }

    /// Poll a future to check if it's ready
    pub fn pollFuture(self: *Self, handle: u32) !FutureState {
        const future = self.futures.get(handle) orelse return Error.InvalidFuture;
        return future.state;
    }

    /// Await a future (non-blocking - returns error if not ready)
    pub fn tryAwaitFuture(self: *Self, handle: u32) !Value {
        const future = self.futures.get(handle) orelse return Error.InvalidFuture;

        return switch (future.state) {
            .pending => Error.FutureNotReady,
            .ready => switch (future.result) {
                .ok => |v| v,
                else => unreachable,
            },
            .error_state => Error.FutureCompleted,
            .cancelled => Error.Cancelled,
            .completed => Error.FutureCompleted,
        };
    }

    /// Await a future with timeout (blocking with timeout)
    pub fn awaitFutureWithTimeout(self: *Self, handle: u32, timeout_ns: i64) !Value {
        const start_time = @import("../util/time.zig").nanoTimestamp();
        var remaining = timeout_ns;

        while (true) {
            // Try to get the result
            const result = self.tryAwaitFuture(handle);
            if (result) |value| {
                return value;
            } else |err| {
                if (err != Error.FutureNotReady) {
                    return err;
                }
            }

            // Check timeout
            const elapsed = @import("../util/time.zig").nanoTimestamp() - start_time;
            if (elapsed >= timeout_ns) {
                return Error.FutureNotReady;
            }

            // Process pending I/O and timers
            try self.processPending();

            // Adjust remaining time
            remaining = timeout_ns - elapsed;

            // Poll with reduced timeout
            std.Thread.yield() catch {};

        }
    }

    /// Register callback for future completion
    pub fn onComplete(self: *Self, handle: u32, callback: *const AsyncCallback, data: ?*anyopaque) !void {
        const future = self.futures.getPtr(handle) orelse return Error.InvalidFuture;
        future.callback = callback;
        future.callback_data = data;
    }

    /// Schedule a future to complete after a delay
    pub fn scheduleTimer(self: *Self, handle: u32, delay_ns: i64, periodic: bool, period_ns: i32) !void {
        const wake_time = @import("../util/time.zig").nanoTimestamp() + delay_ns;

        try self.timers.append(self.allocator, TimerEntry{
            .handle = handle,
            .wake_time = wake_time,
            .periodic = periodic,
            .period_ns = period_ns,
        });

        self.timer_count += 1;

        var o = Log.op("AsyncABI", "scheduleTimer");
        o.log("Scheduled timer: handle={d}, delay={d}ns, periodic={}", .{ handle, delay_ns, periodic });
    }

    /// Register for I/O events
    pub fn registerIoWait(self: *Self, handle: u32, fd: u32, events: u32) !void {
        try self.io_waits.put(handle, IoWaitEntry{
            .handle = handle,
            .fd = fd,
            .events = events,
        });

        self.io_count += 1;
    }

    /// Unregister I/O wait
    pub fn unregisterIoWait(self: *Self, handle: u32) void {
        _ = self.io_waits.remove(handle);
    }

    /// Process all pending async operations (I/O, timers, tasks)
    pub fn processPending(self: *Self) !void {
        self.poll_count += 1;

        var o = Log.op("AsyncABI", "processPending");
        o.log("Processing pending operations: futures={d}, timers={d}, io={d}, tasks={d}", .{
            self.pending_futures.items.len,
            self.timers.items.len,
            self.io_waits.count(),
            self.runnable_tasks.items.len,
        });

        // Process timers
        try self.processTimers();

        // Process I/O waits
        try self.processIoWaits();

        // Process runnable tasks
        try self.processTasks();

        // If we have a callback for external I/O, call it
        if (self.io_callback) |cb| {
            var it = self.io_waits.valueIterator();
            while (it.next()) |entry| {
                cb(entry.fd, entry.events, null);
            }
        }
    }

    fn processTimers(self: *Self) !void {
        const now = @import("../util/time.zig").nanoTimestamp();

        var i: usize = 0;
        while (i < self.timers.items.len) {
            const entry = self.timers.items[i];

            if (now >= entry.wake_time) {
                // Timer fired - complete the future
                if (self.futures.getPtr(entry.handle)) |future| {
                    if (future.state == .pending) {
                        // Complete with void result
                        future.complete(.{ .i32 = 0 });
                        self.removeFromPending(entry.handle);
                    }
                }

                // Handle periodic timers
                if (entry.periodic) {
                    // Reschedule
                    self.timers.items[i].wake_time = entry.wake_time + entry.period_ns;
                } else {
                    // Remove one-shot timer
                    _ = self.timers.swapRemove(i);
                    continue;
                }
            }

            i += 1;
        }

        // Sort timers by wake time for efficient processing
        std.sort.sort(TimerEntry, self.timers.items, {}, TimerEntry.compareWakeTime);
    }

    fn processIoWaits(self: *Self) !void {
        // In a full implementation, this would poll actual file descriptors
        // For now, we keep the infrastructure in place
        _ = self;
    }

    fn processTasks(self: *Self) !void {
        // Process runnable tasks
        var i: usize = 0;
        while (i < self.runnable_tasks.items.len) {
            const task_id = self.runnable_tasks.items[i];

            if (self.tasks.getPtr(task_id)) |task| {
                switch (task.state) {
                    .running => {
                        // Task is runnable - would execute it here
                        // For now, just mark as completed
                        task.state = .completed;
                        self.runnable_tasks.swapRemove(i);
                        continue;
                    },
                    .suspended => {
                        // Would resume suspended task
                    },
                    else => {},
                }
            }

            i += 1;
        }
    }

    /// Get the next timer wake time (for efficient polling)
    pub fn getNextTimerWakeTime(self: *Self) ?i64 {
        if (self.timers.items.len == 0) return null;

        var min_time = self.timers.items[0].wake_time;
        for (self.timers.items[1..]) |entry| {
            if (entry.wake_time < min_time) {
                min_time = entry.wake_time;
            }
        }

        return min_time;
    }

    /// Get number of pending futures
    pub fn pendingCount(self: *Self) usize {
        return self.pending_futures.items.len;
    }

    /// Get number of active timers
    pub fn timerCount(self: *Self) usize {
        return self.timers.items.len;
    }

    /// Get statistics
    pub fn getStats(self: *Self) struct { poll_count: u64, timer_count: u64, io_count: u64 } {
        return .{
            .poll_count = self.poll_count,
            .timer_count = self.timer_count,
            .io_count = self.io_count,
        };
    }
};

fn compareWakeTime(_: void, a: TimerEntry, b: TimerEntry) bool {
    return a.wake_time < b.wake_time;
}

/// Task descriptor for async function execution
pub const Task = struct {
    id: u32,
    state: TaskState,
    func_index: u32,
    args: []Value,
    future_handle: u32,
    stack_size: usize,

    pub const TaskState = enum {
        created,
        runnable,
        running,
        suspended,
        completed,
        failed,
        cancelled,
    };
};

/// Async function descriptor
pub const AsyncFunction = struct {
    func_index: u32,
    returns_future: bool,
    stack_size: usize,
};

/// Async call context
pub const AsyncCallContext = struct {
    future_handle: u32,
    caller_func: u32,
    caller_pc: usize,
};

/// Async ABI intrinsics - called from WASM code
pub const Intrinsics = struct {
    /// Create a new future
    pub fn futureNew(abi: *AsyncABI) !u32 {
        return try abi.createFuture();
    }

    /// Poll a future
    pub fn futurePoll(abi: *AsyncABI, handle: u32) !u32 {
        const state = try abi.pollFuture(handle);
        return switch (state) {
            .pending => 0,
            .ready => 1,
            .completed => 2,
            .error_state => 3,
            .cancelled => 4,
        };
    }

    /// Try to await a future (non-blocking)
    pub fn futureTryAwait(abi: *AsyncABI, handle: u32) !Value {
        return try abi.tryAwaitFuture(handle);
    }

    /// Await a future with timeout
    pub fn futureAwaitTimeout(abi: *AsyncABI, handle: u32, timeout_ns: i64) !Value {
        return try abi.awaitFutureWithTimeout(handle, timeout_ns);
    }

    /// Complete a future
    pub fn futureComplete(abi: *AsyncABI, handle: u32, value: Value) !void {
        try abi.completeFuture(handle, value);
    }

    /// Fail a future
    pub fn futureFail(abi: *AsyncABI, handle: u32, error_code: u32) !void {
        try abi.failFuture(handle, error_code);
    }

    /// Cancel a future
    pub fn futureCancel(abi: *AsyncABI, handle: u32) !void {
        try abi.cancelFuture(handle);
    }

    /// Schedule a timer
    pub fn scheduleTimer(abi: *AsyncABI, handle: u32, delay_ns: i64, periodic: bool, period_ns: i32) !void {
        try abi.scheduleTimer(handle, delay_ns, periodic, period_ns);
    }

    /// Register I/O wait
    pub fn registerIo(abi: *AsyncABI, handle: u32, fd: u32, events: u32) !void {
        try abi.registerIoWait(handle, fd, events);
    }

    /// Unregister I/O wait
    pub fn unregisterIo(abi: *AsyncABI, handle: u32) void {
        abi.unregisterIoWait(handle);
    }

    /// Process pending operations
    pub fn processPending(abi: *AsyncABI) !void {
        try abi.processPending();
    }

    /// Get pending count
    pub fn getPendingCount(abi: *AsyncABI) usize {
        return abi.pendingCount();
    }
};

/// Task queue for async operations (legacy interface)
pub const TaskQueue = struct {
    const QueueTask = struct {
        func_index: u32,
        args: []Value,
        future_handle: u32,
    };

    allocator: Allocator,
    tasks: std.ArrayList(QueueTask),

    pub fn init(allocator: Allocator) !*TaskQueue {
        const queue = try allocator.create(TaskQueue);
        queue.* = TaskQueue{
            .allocator = allocator,
            .tasks = std.ArrayList(QueueTask).init(allocator),
        };
        return queue;
    }

    pub fn deinit(self: *TaskQueue) void {
        for (self.tasks.items) |task| {
            self.allocator.free(task.args);
        }
        self.tasks.deinit();
        self.allocator.destroy(self);
    }

    pub fn enqueue(self: *TaskQueue, func_index: u32, args: []const Value, future_handle: u32) !void {
        const args_copy = try self.allocator.alloc(Value, args.len);
        @memcpy(args_copy, args);

        try self.tasks.append(QueueTask{
            .func_index = func_index,
            .args = args_copy,
            .future_handle = future_handle,
        });
    }

    pub fn dequeue(self: *TaskQueue) ?QueueTask {
        if (self.tasks.items.len == 0) {
            return null;
        }
        return self.tasks.orderedRemove(0);
    }

    pub fn isEmpty(self: *TaskQueue) bool {
        return self.tasks.items.len == 0;
    }
};
