/// WebAssembly Asyncify Implementation
///
/// Asyncify enables suspending and resuming WebAssembly execution,
/// allowing synchronous-looking code to perform asynchronous operations.
///
/// Features:
/// - Stack unwinding and rewinding
/// - Suspend/resume points
/// - State preservation across async boundaries
/// - Integration with WASI async operations
///
/// References:
/// - https://github.com/WebAssembly/binaryen/blob/main/src/passes/Asyncify.cpp
/// - https://kripken.github.io/blog/wasm/2019/07/16/asyncify.html
const std = @import("std");
const Allocator = std.mem.Allocator;
const Value = @import("value.zig").Value;
const ValueType = @import("value.zig").Type;
const Log = @import("../util/fmt.zig").Log;

pub const Error = error{
    NotSuspended,
    AlreadySuspended,
    StackOverflow,
    StackUnderflow,
    InvalidState,
    OutOfMemory,
};

/// Asyncify state
pub const State = enum {
    none, // Normal execution
    unwinding, // Unwinding stack to suspend
    rewinding, // Rewinding stack to resume
};

/// Asyncify data structure
/// This is passed to asyncify_start_unwind and asyncify_start_rewind
pub const AsyncifyData = struct {
    // Stack buffer for storing unwound state
    stack_ptr: u32, // Current position in stack buffer
    stack_start: u32, // Start of stack buffer in memory
    stack_end: u32, // End of stack buffer in memory
};

/// Call frame saved during unwinding
pub const CallFrame = struct {
    func_index: u32,
    pc: usize, // Program counter (bytecode position)
    locals: []Value, // Local variables
    stack_size: usize, // Value stack size at this point
};

/// Asyncify context
pub const Asyncify = struct {
    const Self = @This();

    allocator: Allocator,
    state: State,

    // Saved execution state
    call_frames: std.ArrayList(CallFrame),
    value_stack: std.ArrayList(Value),

    // Asyncify data structure (in WASM memory)
    data: ?AsyncifyData,

    // Suspend/resume callback
    suspend_callback: ?*const fn () void,
    resume_callback: ?*const fn () void,

    // Statistics
    suspend_count: u64,
    resume_count: u64,

    pub fn init(allocator: Allocator) !*Self {
        const asyncify = try allocator.create(Self);
        asyncify.* = Self{
            .allocator = allocator,
            .state = .none,
            .call_frames = std.ArrayList(CallFrame).init(allocator),
            .value_stack = std.ArrayList(Value).init(allocator),
            .data = null,
            .suspend_callback = null,
            .resume_callback = null,
            .suspend_count = 0,
            .resume_count = 0,
        };
        return asyncify;
    }

    pub fn deinit(self: *Self) void {
        // Free call frames
        for (self.call_frames.items) |frame| {
            self.allocator.free(frame.locals);
        }
        self.call_frames.deinit();
        self.value_stack.deinit();
        self.allocator.destroy(self);
    }

    /// Start unwinding the stack to suspend execution
    pub fn startUnwind(self: *Self, data_ptr: u32, memory: []u8) !void {
        var o = Log.op("Asyncify", "startUnwind");
        o.log("Starting stack unwind (data_ptr=0x{X})", .{data_ptr});

        if (self.state != .none) {
            return Error.AlreadySuspended;
        }

        // Read asyncify data structure from WASM memory
        if (data_ptr + 12 > memory.len) {
            return Error.InvalidState;
        }

        const stack_start = std.mem.readInt(u32, memory[data_ptr..][0..4], .little);
        const stack_end = std.mem.readInt(u32, memory[data_ptr + 4 ..][0..4], .little);
        const stack_ptr = std.mem.readInt(u32, memory[data_ptr + 8 ..][0..4], .little);

        self.data = AsyncifyData{
            .stack_ptr = stack_ptr,
            .stack_start = stack_start,
            .stack_end = stack_end,
        };

        self.state = .unwinding;
        self.suspend_count += 1;

        o.log("Unwinding started (stack: 0x{X}..0x{X}, ptr: 0x{X})", .{ stack_start, stack_end, stack_ptr });
    }

    /// Start rewinding the stack to resume execution
    pub fn startRewind(self: *Self, data_ptr: u32, memory: []u8) !void {
        var o = Log.op("Asyncify", "startRewind");
        o.log("Starting stack rewind (data_ptr=0x{X})", .{data_ptr});

        if (self.state != .unwinding) {
            return Error.NotSuspended;
        }

        // Read asyncify data structure from WASM memory
        if (data_ptr + 12 > memory.len) {
            return Error.InvalidState;
        }

        const stack_start = std.mem.readInt(u32, memory[data_ptr..][0..4], .little);
        const stack_end = std.mem.readInt(u32, memory[data_ptr + 4 ..][0..4], .little);
        const stack_ptr = std.mem.readInt(u32, memory[data_ptr + 8 ..][0..4], .little);

        self.data = AsyncifyData{
            .stack_ptr = stack_ptr,
            .stack_start = stack_start,
            .stack_end = stack_end,
        };

        self.state = .rewinding;
        self.resume_count += 1;

        o.log("Rewinding started (stack: 0x{X}..0x{X}, ptr: 0x{X})", .{ stack_start, stack_end, stack_ptr });
    }

    /// Stop unwinding/rewinding
    pub fn stop(self: *Self) void {
        var o = Log.op("Asyncify", "stop");
        o.log("Stopping asyncify (state={s})", .{@tagName(self.state)});

        self.state = .none;
        self.data = null;
    }

    /// Get current asyncify state
    pub fn getState(self: *Self) State {
        return self.state;
    }

    /// Save call frame during unwinding
    pub fn saveFrame(self: *Self, func_index: u32, pc: usize, locals: []const Value, stack_size: usize) !void {
        var o = Log.op("Asyncify", "saveFrame");
        o.log("Saving frame (func={d}, pc={d}, locals={d}, stack={d})", .{ func_index, pc, locals.len, stack_size });

        // Copy locals
        const locals_copy = try self.allocator.alloc(Value, locals.len);
        @memcpy(locals_copy, locals);

        try self.call_frames.append(CallFrame{
            .func_index = func_index,
            .pc = pc,
            .locals = locals_copy,
            .stack_size = stack_size,
        });
    }

    /// Restore call frame during rewinding
    pub fn restoreFrame(self: *Self) ?CallFrame {
        if (self.call_frames.items.len == 0) {
            return null;
        }
        return self.call_frames.pop();
    }

    /// Save value stack
    pub fn saveValueStack(self: *Self, stack: []const Value) !void {
        var o = Log.op("Asyncify", "saveValueStack");
        o.log("Saving value stack ({d} values)", .{stack.len});

        self.value_stack.clearRetainingCapacity();
        try self.value_stack.appendSlice(stack);
    }

    /// Restore value stack
    pub fn restoreValueStack(self: *Self, stack: *std.ArrayList(Value)) !void {
        var o = Log.op("Asyncify", "restoreValueStack");
        o.log("Restoring value stack ({d} values)", .{self.value_stack.items.len});

        stack.clearRetainingCapacity();
        try stack.appendSlice(self.value_stack.items);
    }

    /// Write asyncify state to WASM memory
    pub fn writeState(self: *Self, memory: []u8) !void {
        if (self.data == null) return;

        const data = self.data.?;

        // Write stack pointer back to memory
        std.mem.writeInt(u32, memory[data.stack_start - 8 ..][0..4], data.stack_ptr, .little);

        var o = Log.op("Asyncify", "writeState");
        o.log("Wrote stack pointer: 0x{X}", .{data.stack_ptr});
    }

    /// Print asyncify statistics
    pub fn printStats(self: *Self) void {
        std.debug.print("=== Asyncify Statistics ===\n", .{});
        std.debug.print("State: {s}\n", .{@tagName(self.state)});
        std.debug.print("Suspends: {d}\n", .{self.suspend_count});
        std.debug.print("Resumes: {d}\n", .{self.resume_count});
        std.debug.print("Saved frames: {d}\n", .{self.call_frames.items.len});
        std.debug.print("Saved values: {d}\n", .{self.value_stack.items.len});
    }
};

/// Asyncify intrinsic functions
pub const Intrinsics = struct {
    /// asyncify_start_unwind(data: i32)
    pub fn startUnwind(asyncify: *Asyncify, data_ptr: u32, memory: []u8) !void {
        try asyncify.startUnwind(data_ptr, memory);
    }

    /// asyncify_stop_unwind()
    pub fn stopUnwind(asyncify: *Asyncify) void {
        asyncify.stop();
    }

    /// asyncify_start_rewind(data: i32)
    pub fn startRewind(asyncify: *Asyncify, data_ptr: u32, memory: []u8) !void {
        try asyncify.startRewind(data_ptr, memory);
    }

    /// asyncify_stop_rewind()
    pub fn stopRewind(asyncify: *Asyncify) void {
        asyncify.stop();
    }

    /// asyncify_get_state(): i32
    pub fn getState(asyncify: *Asyncify) i32 {
        return switch (asyncify.state) {
            .none => 0,
            .unwinding => 1,
            .rewinding => 2,
        };
    }
};
