/// WebAssembly JavaScript Promise Integration
/// Provides async/await interop for WASM modules
const std = @import("std");
const Value = @import("value.zig").Value;

/// Promise state
pub const PromiseState = enum {
    pending,
    fulfilled,
    rejected,
};

/// Promise structure
pub const Promise = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    state: PromiseState,
    result: ?Value,
    error_msg: ?[]const u8,
    then_callbacks: std.ArrayList(Callback),
    catch_callbacks: std.ArrayList(Callback),
    finally_callbacks: std.ArrayList(Callback),

    pub const Callback = struct {
        func_idx: u32,
        context: ?*anyopaque,
    };

    pub fn init(allocator: std.mem.Allocator) !*Self {
        const self = try allocator.create(Self);
        self.* = Self{
            .allocator = allocator,
            .state = .pending,
            .result = null,
            .error_msg = null,
            .then_callbacks = std.ArrayList(Callback).init(allocator),
            .catch_callbacks = std.ArrayList(Callback).init(allocator),
            .finally_callbacks = std.ArrayList(Callback).init(allocator),
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        if (self.error_msg) |msg| {
            self.allocator.free(msg);
        }
        self.then_callbacks.deinit();
        self.catch_callbacks.deinit();
        self.finally_callbacks.deinit();
        self.allocator.destroy(self);
    }

    /// Resolve the promise with a value
    pub fn resolve(self: *Self, value: Value) !void {
        if (self.state != .pending) return error.PromiseAlreadySettled;

        self.state = .fulfilled;
        self.result = value;

        // Execute then callbacks
        for (self.then_callbacks.items) |callback| {
            _ = callback; // Would execute callback here
        }

        // Execute finally callbacks
        for (self.finally_callbacks.items) |callback| {
            _ = callback; // Would execute callback here
        }
    }

    /// Reject the promise with an error
    pub fn reject(self: *Self, error_msg: []const u8) !void {
        if (self.state != .pending) return error.PromiseAlreadySettled;

        self.state = .rejected;
        self.error_msg = try self.allocator.dupe(u8, error_msg);

        // Execute catch callbacks
        for (self.catch_callbacks.items) |callback| {
            _ = callback; // Would execute callback here
        }

        // Execute finally callbacks
        for (self.finally_callbacks.items) |callback| {
            _ = callback; // Would execute callback here
        }
    }

    /// Add a then callback
    pub fn then(self: *Self, callback: Callback) !void {
        if (self.state == .fulfilled) {
            // Execute immediately if already resolved
            _ = callback;
        } else if (self.state == .pending) {
            try self.then_callbacks.append(callback);
        }
    }

    /// Add a catch callback
    pub fn @"catch"(self: *Self, callback: Callback) !void {
        if (self.state == .rejected) {
            // Execute immediately if already rejected
            _ = callback;
        } else if (self.state == .pending) {
            try self.catch_callbacks.append(callback);
        }
    }

    /// Add a finally callback
    pub fn finally(self: *Self, callback: Callback) !void {
        if (self.state != .pending) {
            // Execute immediately if already settled
            _ = callback;
        } else {
            try self.finally_callbacks.append(callback);
        }
    }

    /// Get the promise result (blocking)
    pub fn await(self: *Self) !Value {
        // In a real async implementation, this would wait for the promise to settle
        // For now, we just check the current state
        return switch (self.state) {
            .fulfilled => self.result orelse error.NoResult,
            .rejected => error.PromiseRejected,
            .pending => error.PromisePending,
        };
    }
};

/// Promise.all() - waits for all promises to resolve
pub fn all(allocator: std.mem.Allocator, promises: []*Promise) !*Promise {
    const result_promise = try Promise.init(allocator);
    errdefer result_promise.deinit();

    // Check if all are resolved
    var all_resolved = true;
    for (promises) |p| {
        if (p.state == .rejected) {
            try result_promise.reject("One or more promises rejected");
            return result_promise;
        }
        if (p.state == .pending) {
            all_resolved = false;
        }
    }

    if (all_resolved) {
        // All resolved - create array of results
        // For simplicity, just resolve with first result
        if (promises.len > 0 and promises[0].result != null) {
            try result_promise.resolve(promises[0].result.?);
        }
    }

    return result_promise;
}

/// Promise.race() - resolves with first promise that settles
pub fn race(allocator: std.mem.Allocator, promises: []*Promise) !*Promise {
    const result_promise = try Promise.init(allocator);
    errdefer result_promise.deinit();

    // Find first settled promise
    for (promises) |p| {
        switch (p.state) {
            .fulfilled => {
                if (p.result) |result| {
                    try result_promise.resolve(result);
                    return result_promise;
                }
            },
            .rejected => {
                if (p.error_msg) |msg| {
                    try result_promise.reject(msg);
                    return result_promise;
                }
            },
            .pending => continue,
        }
    }

    // All still pending
    return result_promise;
}

/// Promise.any() - resolves with first fulfilled promise
pub fn any(allocator: std.mem.Allocator, promises: []*Promise) !*Promise {
    const result_promise = try Promise.init(allocator);
    errdefer result_promise.deinit();

    // Find first fulfilled promise
    var all_rejected = true;
    for (promises) |p| {
        if (p.state == .fulfilled) {
            if (p.result) |result| {
                try result_promise.resolve(result);
                return result_promise;
            }
        }
        if (p.state == .pending) {
            all_rejected = false;
        }
    }

    if (all_rejected) {
        try result_promise.reject("All promises rejected");
    }

    return result_promise;
}

/// Promise.allSettled() - waits for all promises to settle (resolve or reject)
pub fn allSettled(allocator: std.mem.Allocator, promises: []*Promise) !*Promise {
    const result_promise = try Promise.init(allocator);
    errdefer result_promise.deinit();

    // Check if all are settled
    var all_settled = true;
    for (promises) |p| {
        if (p.state == .pending) {
            all_settled = false;
            break;
        }
    }

    if (all_settled) {
        // For simplicity, just resolve with a marker value
        try result_promise.resolve(Value{ .i32 = @intCast(promises.len) });
    }

    return result_promise;
}

/// Create a resolved promise
pub fn resolved(allocator: std.mem.Allocator, value: Value) !*Promise {
    const promise = try Promise.init(allocator);
    try promise.resolve(value);
    return promise;
}

/// Create a rejected promise
pub fn rejected(allocator: std.mem.Allocator, error_msg: []const u8) !*Promise {
    const promise = try Promise.init(allocator);
    try promise.reject(error_msg);
    return promise;
}

/// Async function executor
pub const AsyncFunction = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    func_idx: u32,
    is_running: bool,
    result: ?*Promise,

    pub fn init(allocator: std.mem.Allocator, func_idx: u32) !*Self {
        const self = try allocator.create(Self);
        self.* = Self{
            .allocator = allocator,
            .func_idx = func_idx,
            .is_running = false,
            .result = null,
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        if (self.result) |result| {
            result.deinit();
        }
        self.allocator.destroy(self);
    }

    /// Execute the async function
    pub fn execute(self: *Self) !*Promise {
        if (self.is_running) return error.AlreadyRunning;

        self.is_running = true;
        defer self.is_running = false;

        // Create a promise for the result
        const promise = try Promise.init(self.allocator);
        self.result = promise;

        // In a real implementation, this would call the WASM function
        // For now, just return a pending promise
        return promise;
    }

    /// Wait for the async function to complete
    pub fn await(self: *Self) !Value {
        if (self.result) |promise| {
            return promise.await();
        }
        return error.NotExecuted;
    }
};

/// Async/await runtime for managing promise execution
pub const AsyncRuntime = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    pending_promises: std.ArrayList(*Promise),
    async_functions: std.ArrayList(*AsyncFunction),
    microtask_queue: std.ArrayList(MicroTask),

    pub const MicroTask = struct {
        callback: *const fn (*anyopaque) anyerror!void,
        context: *anyopaque,
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .pending_promises = std.ArrayList(*Promise).init(allocator),
            .async_functions = std.ArrayList(*AsyncFunction).init(allocator),
            .microtask_queue = std.ArrayList(MicroTask).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.pending_promises.items) |promise| {
            promise.deinit();
        }
        self.pending_promises.deinit();

        for (self.async_functions.items) |func| {
            func.deinit();
        }
        self.async_functions.deinit();

        self.microtask_queue.deinit();
    }

    /// Register a promise for tracking
    pub fn registerPromise(self: *Self, promise: *Promise) !void {
        try self.pending_promises.append(promise);
    }

    /// Register an async function
    pub fn registerAsyncFunction(self: *Self, func: *AsyncFunction) !void {
        try self.async_functions.append(func);
    }

    /// Queue a microtask
    pub fn queueMicrotask(self: *Self, task: MicroTask) !void {
        try self.microtask_queue.append(task);
    }

    /// Process all pending microtasks
    pub fn processMicrotasks(self: *Self) !void {
        while (self.microtask_queue.items.len > 0) {
            const task = self.microtask_queue.orderedRemove(0);
            try task.callback(task.context);
        }
    }

    /// Run the event loop until all promises settle
    pub fn runEventLoop(self: *Self) !void {
        // Process microtasks
        try self.processMicrotasks();

        // Check for settled promises and remove them
        var i: usize = 0;
        while (i < self.pending_promises.items.len) {
            const promise = self.pending_promises.items[i];
            if (promise.state != .pending) {
                _ = self.pending_promises.orderedRemove(i);
                // Don't increment i since we removed an element
            } else {
                i += 1;
            }
        }
    }

    /// Check if any promises are still pending
    pub fn hasPendingWork(self: *Self) bool {
        return self.pending_promises.items.len > 0 or self.microtask_queue.items.len > 0;
    }
};
