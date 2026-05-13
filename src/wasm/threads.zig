/// WebAssembly Threads Proposal Implementation
/// This module handles atomic operations, shared memory, and thread management
/// for the WebAssembly shared-everything-concurrency proposal.
const std = @import("std");
const Io = std.Io;
const Value = @import("value.zig").Value;
const Module = @import("module.zig");
const Error = @import("op.zig").Error;
const SmallVec = @import("stack.zig").SmallVec;
const Log = @import("../util/fmt.zig").Log;
const builtin = @import("builtin");

/// Thread configuration for spawning
pub const ThreadConfig = struct {
    stack_size: usize = 1024 * 1024, // 1MB default stack
    guard_size: usize = 65536, // 64KB guard page
};

/// Thread message for inter-thread communication
pub const ThreadMessage = struct {
    id: u32,
    from_thread: u32,
    to_thread: u32,
    type: MessageType,
    data: []const u8,
    timestamp: i64,

    pub const MessageType = enum {
        data,
        signal,
        shutdown,
    };
};

/// Atomic operation types
pub const AtomicOp = enum(u32) {
    // Atomic loads
    i32_atomic_load = 0x10,
    i64_atomic_load = 0x11,
    i32_atomic_load8_u = 0x12,
    i32_atomic_load16_u = 0x13,
    i64_atomic_load8_u = 0x14,
    i64_atomic_load16_u = 0x15,
    i64_atomic_load32_u = 0x16,

    // Atomic stores
    i32_atomic_store = 0x17,
    i64_atomic_store = 0x18,
    i32_atomic_store8 = 0x19,
    i32_atomic_store16 = 0x1A,
    i64_atomic_store8 = 0x1B,
    i64_atomic_store16 = 0x1C,
    i64_atomic_store32 = 0x1D,

    // Atomic read-modify-write operations
    i32_atomic_rmw_add = 0x1E,
    i64_atomic_rmw_add = 0x1F,
    i32_atomic_rmw8_add_u = 0x20,
    i32_atomic_rmw16_add_u = 0x21,
    i64_atomic_rmw8_add_u = 0x22,
    i64_atomic_rmw16_add_u = 0x23,
    i64_atomic_rmw32_add_u = 0x24,

    i32_atomic_rmw_sub = 0x25,
    i64_atomic_rmw_sub = 0x26,
    i32_atomic_rmw8_sub_u = 0x27,
    i32_atomic_rmw16_sub_u = 0x28,
    i64_atomic_rmw8_sub_u = 0x29,
    i64_atomic_rmw16_sub_u = 0x2A,
    i64_atomic_rmw32_sub_u = 0x2B,

    i32_atomic_rmw_and = 0x2C,
    i64_atomic_rmw_and = 0x2D,
    i32_atomic_rmw8_and_u = 0x2E,
    i32_atomic_rmw16_and_u = 0x2F,
    i64_atomic_rmw8_and_u = 0x30,
    i64_atomic_rmw16_and_u = 0x31,
    i64_atomic_rmw32_and_u = 0x32,

    i32_atomic_rmw_or = 0x33,
    i64_atomic_rmw_or = 0x34,
    i32_atomic_rmw8_or_u = 0x35,
    i32_atomic_rmw16_or_u = 0x36,
    i64_atomic_rmw8_or_u = 0x37,
    i64_atomic_rmw16_or_u = 0x38,
    i64_atomic_rmw32_or_u = 0x39,

    i32_atomic_rmw_xor = 0x3A,
    i64_atomic_rmw_xor = 0x3B,
    i32_atomic_rmw8_xor_u = 0x3C,
    i32_atomic_rmw16_xor_u = 0x3D,
    i64_atomic_rmw8_xor_u = 0x3E,
    i64_atomic_rmw16_xor_u = 0x3F,
    i64_atomic_rmw32_xor_u = 0x40,

    i32_atomic_rmw_xchg = 0x41,
    i64_atomic_rmw_xchg = 0x42,
    i32_atomic_rmw8_xchg_u = 0x43,
    i32_atomic_rmw16_xchg_u = 0x44,
    i64_atomic_rmw8_xchg_u = 0x45,
    i64_atomic_rmw16_xchg_u = 0x46,
    i64_atomic_rmw32_xchg_u = 0x47,

    // Atomic compare-exchange
    i32_atomic_rmw_cmpxchg = 0x48,
    i64_atomic_rmw_cmpxchg = 0x49,
    i32_atomic_rmw8_cmpxchg_u = 0x4A,
    i32_atomic_rmw16_cmpxchg_u = 0x4B,
    i64_atomic_rmw8_cmpxchg_u = 0x4C,
    i64_atomic_rmw16_cmpxchg_u = 0x4D,
    i64_atomic_rmw32_cmpxchg_u = 0x4E,

    // Wait/notify operations
    memory_atomic_notify = 0x00,
    memory_atomic_wait32 = 0x01,
    memory_atomic_wait64 = 0x02,

    pub fn fromU32(val: u32) ?AtomicOp {
        return std.enums.fromInt(AtomicOp, val);
    }
};

/// Execute an atomic operation
pub fn executeAtomic(
    stack: *SmallVec(Value, 256),
    memory: ?[]u8,
    reader: *Module.Reader,
    atomic_opcode: u32,
    allocator: std.mem.Allocator,
) !void {
    const op = AtomicOp.fromU32(atomic_opcode) orelse return Error.InvalidOpcode;

    switch (op) {
        // ===== ATOMIC LOADS =====

        .i32_atomic_load => {
            const flags = try reader.readLEB128();
            const offset = try reader.readLEB128();
            _ = flags;

            if (stack.items.len < 1) return Error.StackUnderflow;
            const addr_val = stack.pop().?;
            const addr = @as(u32, @bitCast(addr_val.i32)) + @as(u32, @intCast(offset));

            if (memory) |mem| {
                if (addr + 4 > mem.len) return Error.InvalidAccess;
                const val = std.mem.readInt(u32, mem[addr..][0..4], .little);
                try stack.append(allocator, .{ .i32 = @bitCast(val) });
            } else {
                return Error.InvalidAccess;
            }
        },

        .i64_atomic_load => {
            const flags = try reader.readLEB128();
            const offset = try reader.readLEB128();
            _ = flags;

            if (stack.items.len < 1) return Error.StackUnderflow;
            const addr_val = stack.pop().?;
            const addr = @as(u32, @bitCast(addr_val.i32)) + @as(u32, @intCast(offset));

            if (memory) |mem| {
                if (addr + 8 > mem.len) return Error.InvalidAccess;
                const val = std.mem.readInt(u64, mem[addr..][0..8], .little);
                try stack.append(allocator, .{ .i64 = @bitCast(val) });
            } else {
                return Error.InvalidAccess;
            }
        },

        .i32_atomic_load8_u => {
            const flags = try reader.readLEB128();
            const offset = try reader.readLEB128();
            _ = flags;

            if (stack.items.len < 1) return Error.StackUnderflow;
            const addr_val = stack.pop().?;
            const addr = @as(u32, @bitCast(addr_val.i32)) + @as(u32, @intCast(offset));

            if (memory) |mem| {
                if (addr + 1 > mem.len) return Error.InvalidAccess;
                const val = mem[addr];
                try stack.append(allocator, .{ .i32 = val });
            } else {
                return Error.InvalidAccess;
            }
        },

        .i32_atomic_load16_u => {
            const flags = try reader.readLEB128();
            const offset = try reader.readLEB128();
            _ = flags;

            if (stack.items.len < 1) return Error.StackUnderflow;
            const addr_val = stack.pop().?;
            const addr = @as(u32, @bitCast(addr_val.i32)) + @as(u32, @intCast(offset));

            if (memory) |mem| {
                if (addr + 2 > mem.len) return Error.InvalidAccess;
                const val = std.mem.readInt(u16, mem[addr..][0..2], .little);
                try stack.append(allocator, .{ .i32 = val });
            } else {
                return Error.InvalidAccess;
            }
        },

        .i64_atomic_load8_u => {
            const flags = try reader.readLEB128();
            const offset = try reader.readLEB128();
            _ = flags;

            if (stack.items.len < 1) return Error.StackUnderflow;
            const addr_val = stack.pop().?;
            const addr = @as(u32, @bitCast(addr_val.i32)) + @as(u32, @intCast(offset));

            if (memory) |mem| {
                if (addr + 1 > mem.len) return Error.InvalidAccess;
                const val = mem[addr];
                try stack.append(allocator, .{ .i64 = val });
            } else {
                return Error.InvalidAccess;
            }
        },

        .i64_atomic_load16_u => {
            const flags = try reader.readLEB128();
            const offset = try reader.readLEB128();
            _ = flags;

            if (stack.items.len < 1) return Error.StackUnderflow;
            const addr_val = stack.pop().?;
            const addr = @as(u32, @bitCast(addr_val.i32)) + @as(u32, @intCast(offset));

            if (memory) |mem| {
                if (addr + 2 > mem.len) return Error.InvalidAccess;
                const val = std.mem.readInt(u16, mem[addr..][0..2], .little);
                try stack.append(allocator, .{ .i64 = val });
            } else {
                return Error.InvalidAccess;
            }
        },

        .i64_atomic_load32_u => {
            const flags = try reader.readLEB128();
            const offset = try reader.readLEB128();
            _ = flags;

            if (stack.items.len < 1) return Error.StackUnderflow;
            const addr_val = stack.pop().?;
            const addr = @as(u32, @bitCast(addr_val.i32)) + @as(u32, @intCast(offset));

            if (memory) |mem| {
                if (addr + 4 > mem.len) return Error.InvalidAccess;
                const val = std.mem.readInt(u32, mem[addr..][0..4], .little);
                try stack.append(allocator, .{ .i64 = val });
            } else {
                return Error.InvalidAccess;
            }
        },

        // ===== ATOMIC STORES =====

        .i32_atomic_store => {
            const flags = try reader.readLEB128();
            const offset = try reader.readLEB128();
            _ = flags;

            if (stack.items.len < 2) return Error.StackUnderflow;
            const val = stack.pop().?.i32;
            const addr_val = stack.pop().?;
            const addr = @as(u32, @bitCast(addr_val.i32)) + @as(u32, @intCast(offset));

            if (memory) |mem| {
                if (addr + 4 > mem.len) return Error.InvalidAccess;
                std.mem.writeInt(u32, mem[addr..][0..4], @bitCast(val), .little);
            } else {
                return Error.InvalidAccess;
            }
        },

        .i64_atomic_store => {
            const flags = try reader.readLEB128();
            const offset = try reader.readLEB128();
            _ = flags;

            if (stack.items.len < 2) return Error.StackUnderflow;
            const val = stack.pop().?.i64;
            const addr_val = stack.pop().?;
            const addr = @as(u32, @bitCast(addr_val.i32)) + @as(u32, @intCast(offset));

            if (memory) |mem| {
                if (addr + 8 > mem.len) return Error.InvalidAccess;
                std.mem.writeInt(u64, mem[addr..][0..8], @bitCast(val), .little);
            } else {
                return Error.InvalidAccess;
            }
        },

        .i32_atomic_store8 => {
            const flags = try reader.readLEB128();
            const offset = try reader.readLEB128();
            _ = flags;

            if (stack.items.len < 2) return Error.StackUnderflow;
            const val = stack.pop().?.i32;
            const addr_val = stack.pop().?;
            const addr = @as(u32, @bitCast(addr_val.i32)) + @as(u32, @intCast(offset));

            if (memory) |mem| {
                if (addr + 1 > mem.len) return Error.InvalidAccess;
                mem[addr] = @truncate(@as(u32, @bitCast(val)));
            } else {
                return Error.InvalidAccess;
            }
        },

        .i32_atomic_store16 => {
            const flags = try reader.readLEB128();
            const offset = try reader.readLEB128();
            _ = flags;

            if (stack.items.len < 2) return Error.StackUnderflow;
            const val = stack.pop().?.i32;
            const addr_val = stack.pop().?;
            const addr = @as(u32, @bitCast(addr_val.i32)) + @as(u32, @intCast(offset));

            if (memory) |mem| {
                if (addr + 2 > mem.len) return Error.InvalidAccess;
                std.mem.writeInt(u16, mem[addr..][0..2], @truncate(@as(u32, @bitCast(val))), .little);
            } else {
                return Error.InvalidAccess;
            }
        },

        .i64_atomic_store8 => {
            const flags = try reader.readLEB128();
            const offset = try reader.readLEB128();
            _ = flags;

            if (stack.items.len < 2) return Error.StackUnderflow;
            const val = stack.pop().?.i64;
            const addr_val = stack.pop().?;
            const addr = @as(u32, @bitCast(addr_val.i32)) + @as(u32, @intCast(offset));

            if (memory) |mem| {
                if (addr + 1 > mem.len) return Error.InvalidAccess;
                mem[addr] = @truncate(@as(u64, @bitCast(val)));
            } else {
                return Error.InvalidAccess;
            }
        },

        .i64_atomic_store16 => {
            const flags = try reader.readLEB128();
            const offset = try reader.readLEB128();
            _ = flags;

            if (stack.items.len < 2) return Error.StackUnderflow;
            const val = stack.pop().?.i64;
            const addr_val = stack.pop().?;
            const addr = @as(u32, @bitCast(addr_val.i32)) + @as(u32, @intCast(offset));

            if (memory) |mem| {
                if (addr + 2 > mem.len) return Error.InvalidAccess;
                std.mem.writeInt(u16, mem[addr..][0..2], @truncate(@as(u64, @bitCast(val))), .little);
            } else {
                return Error.InvalidAccess;
            }
        },

        .i64_atomic_store32 => {
            const flags = try reader.readLEB128();
            const offset = try reader.readLEB128();
            _ = flags;

            if (stack.items.len < 2) return Error.StackUnderflow;
            const val = stack.pop().?.i64;
            const addr_val = stack.pop().?;
            const addr = @as(u32, @bitCast(addr_val.i32)) + @as(u32, @intCast(offset));

            if (memory) |mem| {
                if (addr + 4 > mem.len) return Error.InvalidAccess;
                std.mem.writeInt(u32, mem[addr..][0..4], @truncate(@as(u64, @bitCast(val))), .little);
            } else {
                return Error.InvalidAccess;
            }
        },

        // ===== ATOMIC RMW OPERATIONS =====
        // Proper atomic operations using Zig's atomic primitives

        .i32_atomic_rmw_add => {
            const flags = try reader.readLEB128();
            const offset = try reader.readLEB128();
            _ = flags;

            if (stack.items.len < 2) return Error.StackUnderflow;
            const val = stack.pop().?.i32;
            const addr_val = stack.pop().?;
            const addr = @as(u32, @bitCast(addr_val.i32)) + @as(u32, @intCast(offset));

            if (memory) |mem| {
                if (addr + 4 > mem.len) return Error.InvalidAccess;
                // Use atomic fetch-add operation
                const ptr = @as(*volatile u32, @ptrCast(@alignCast(&mem[addr])));
                const old_val = @atomicRmw(u32, ptr, .Add, @bitCast(val), .seq_cst);
                try stack.append(allocator, .{ .i32 = @bitCast(old_val) });
            } else {
                return Error.InvalidAccess;
            }
        },

        .i64_atomic_rmw_add => {
            const flags = try reader.readLEB128();
            const offset = try reader.readLEB128();
            _ = flags;

            if (stack.items.len < 2) return Error.StackUnderflow;
            const val = stack.pop().?.i64;
            const addr_val = stack.pop().?;
            const addr = @as(u32, @bitCast(addr_val.i32)) + @as(u32, @intCast(offset));

            if (memory) |mem| {
                if (addr + 8 > mem.len) return Error.InvalidAccess;
                // Use atomic fetch-add operation
                const ptr = @as(*volatile u64, @ptrCast(@alignCast(&mem[addr])));
                const old_val = @atomicRmw(u64, ptr, .Add, @bitCast(val), .seq_cst);
                try stack.append(allocator, .{ .i64 = @bitCast(old_val) });
            } else {
                return Error.InvalidAccess;
            }
        },

        // ===== WAIT/NOTIFY OPERATIONS =====
        // These are simplified implementations for single-threaded execution

        .memory_atomic_notify => {
            const flags = try reader.readLEB128();
            const offset = try reader.readLEB128();
            _ = flags;

            if (stack.items.len < 2) return Error.StackUnderflow;
            const count = stack.pop().?.i32;
            const addr_val = stack.pop().?;
            const addr = @as(u32, @bitCast(addr_val.i32)) + @as(u32, @intCast(offset));

            // In single-threaded mode, notify always succeeds
            _ = addr;
            _ = count;
            try stack.append(allocator, .{ .i32 = 0 }); // Number of threads woken up
        },

        .memory_atomic_wait32 => {
            const flags = try reader.readLEB128();
            const offset = try reader.readLEB128();
            _ = flags;

            if (stack.items.len < 4) return Error.StackUnderflow;
            const timeout = stack.pop().?.i64;
            const expected = stack.pop().?.i32;
            const addr_val = stack.pop().?;
            const addr = @as(u32, @bitCast(addr_val.i32)) + @as(u32, @intCast(offset));

            if (memory) |mem| {
                if (addr + 4 > mem.len) return Error.InvalidAccess;
                const current_val = std.mem.readInt(u32, mem[addr..][0..4], .little);

                if (@as(u32, @bitCast(current_val)) == @as(u32, @bitCast(expected))) {
                    // In single-threaded mode, we don't actually wait
                    _ = timeout;
                    try stack.append(allocator, .{ .i32 = 0 }); // NotEqual = 0
                } else {
                    try stack.append(allocator, .{ .i32 = 1 }); // NotEqual = 1
                }
            } else {
                return Error.InvalidAccess;
            }
        },

        .memory_atomic_wait64 => {
            const flags = try reader.readLEB128();
            const offset = try reader.readLEB128();
            _ = flags;

            if (stack.items.len < 4) return Error.StackUnderflow;
            const timeout = stack.pop().?.i64;
            const expected = stack.pop().?.i64;
            const addr_val = stack.pop().?;
            const addr = @as(u32, @bitCast(addr_val.i32)) + @as(u32, @intCast(offset));

            if (memory) |mem| {
                if (addr + 8 > mem.len) return Error.InvalidAccess;
                const current_val = std.mem.readInt(u64, mem[addr..][0..8], .little);

                if (@as(u64, @bitCast(current_val)) == @as(u64, @bitCast(expected))) {
                    // In single-threaded mode, we don't actually wait
                    _ = timeout;
                    try stack.append(allocator, .{ .i32 = 0 }); // NotEqual = 0
                } else {
                    try stack.append(allocator, .{ .i32 = 1 }); // NotEqual = 1
                }
            } else {
                return Error.InvalidAccess;
            }
        },

        // ===== ATOMIC COMPARE-EXCHANGE OPERATIONS =====

        .i32_atomic_rmw_cmpxchg => {
            const flags = try reader.readLEB128();
            const offset = try reader.readLEB128();
            _ = flags;

            if (stack.items.len < 3) return Error.StackUnderflow;
            const replacement = stack.pop().?.i32;
            const expected = stack.pop().?.i32;
            const addr_val = stack.pop().?;
            const addr = @as(u32, @bitCast(addr_val.i32)) + @as(u32, @intCast(offset));

            if (memory) |mem| {
                if (addr + 4 > mem.len) return Error.InvalidAccess;
                const ptr = @as(*volatile u32, @ptrCast(@alignCast(&mem[addr])));
                const expected_u32 = @as(u32, @bitCast(expected));
                const replacement_u32 = @as(u32, @bitCast(replacement));
                const old_val = @cmpxchgStrong(u32, ptr, expected_u32, replacement_u32, .seq_cst, .seq_cst) orelse expected_u32;
                try stack.append(allocator, .{ .i32 = @bitCast(old_val) });
            } else {
                return Error.InvalidAccess;
            }
        },

        .i64_atomic_rmw_cmpxchg => {
            const flags = try reader.readLEB128();
            const offset = try reader.readLEB128();
            _ = flags;

            if (stack.items.len < 3) return Error.StackUnderflow;
            const replacement = stack.pop().?.i64;
            const expected = stack.pop().?.i64;
            const addr_val = stack.pop().?;
            const addr = @as(u32, @bitCast(addr_val.i32)) + @as(u32, @intCast(offset));

            if (memory) |mem| {
                if (addr + 8 > mem.len) return Error.InvalidAccess;
                const ptr = @as(*volatile u64, @ptrCast(@alignCast(&mem[addr])));
                const expected_u64 = @as(u64, @bitCast(expected));
                const replacement_u64 = @as(u64, @bitCast(replacement));
                const old_val = @cmpxchgStrong(u64, ptr, expected_u64, replacement_u64, .seq_cst, .seq_cst) orelse expected_u64;
                try stack.append(allocator, .{ .i64 = @bitCast(old_val) });
            } else {
                return Error.InvalidAccess;
            }
        },

        // ===== SUB OPERATIONS =====

        .i32_atomic_rmw_sub => {
            const flags = try reader.readLEB128();
            const offset = try reader.readLEB128();
            _ = flags;

            if (stack.items.len < 2) return Error.StackUnderflow;
            const val = stack.pop().?.i32;
            const addr_val = stack.pop().?;
            const addr = @as(u32, @bitCast(addr_val.i32)) + @as(u32, @intCast(offset));

            if (memory) |mem| {
                if (addr + 4 > mem.len) return Error.InvalidAccess;
                const ptr = @as(*volatile u32, @ptrCast(@alignCast(&mem[addr])));
                const old_val = @atomicRmw(u32, ptr, .Sub, @bitCast(val), .seq_cst);
                try stack.append(allocator, .{ .i32 = @bitCast(old_val) });
            } else {
                return Error.InvalidAccess;
            }
        },

        .i64_atomic_rmw_sub => {
            const flags = try reader.readLEB128();
            const offset = try reader.readLEB128();
            _ = flags;

            if (stack.items.len < 2) return Error.StackUnderflow;
            const val = stack.pop().?.i64;
            const addr_val = stack.pop().?;
            const addr = @as(u32, @bitCast(addr_val.i32)) + @as(u32, @intCast(offset));

            if (memory) |mem| {
                if (addr + 8 > mem.len) return Error.InvalidAccess;
                const ptr = @as(*volatile u64, @ptrCast(@alignCast(&mem[addr])));
                const old_val = @atomicRmw(u64, ptr, .Sub, @bitCast(val), .seq_cst);
                try stack.append(allocator, .{ .i64 = @bitCast(old_val) });
            } else {
                return Error.InvalidAccess;
            }
        },

        .i32_atomic_rmw8_sub_u, .i32_atomic_rmw16_sub_u => |variant| {
            const flags = try reader.readLEB128();
            const offset = try reader.readLEB128();
            _ = flags;

            if (stack.items.len < 2) return Error.StackUnderflow;
            const val = stack.pop().?.i32;
            const addr_val = stack.pop().?;
            const addr = @as(u32, @bitCast(addr_val.i32)) + @as(u32, @intCast(offset));

            if (memory) |mem| {
                const size: u32 = if (variant == .i32_atomic_rmw8_sub_u) 1 else 2;
                if (addr + size > mem.len) return Error.InvalidAccess;

                if (size == 1) {
                    const ptr = @as(*volatile u8, @ptrCast(&mem[addr]));
                    const old_val = @atomicRmw(u8, ptr, .Sub, @truncate(@as(u32, @bitCast(val))), .seq_cst);
                    try stack.append(allocator, .{ .i32 = @as(i32, old_val) });
                } else {
                    const ptr = @as(*volatile u16, @ptrCast(@alignCast(&mem[addr])));
                    const old_val = @atomicRmw(u16, ptr, .Sub, @truncate(@as(u32, @bitCast(val))), .seq_cst);
                    try stack.append(allocator, .{ .i32 = @as(i32, old_val) });
                }
            } else {
                return Error.InvalidAccess;
            }
        },

        .i64_atomic_rmw8_sub_u, .i64_atomic_rmw16_sub_u, .i64_atomic_rmw32_sub_u => |variant| {
            const flags = try reader.readLEB128();
            const offset = try reader.readLEB128();
            _ = flags;

            if (stack.items.len < 2) return Error.StackUnderflow;
            const val = stack.pop().?.i64;
            const addr_val = stack.pop().?;
            const addr = @as(u32, @bitCast(addr_val.i32)) + @as(u32, @intCast(offset));

            if (memory) |mem| {
                const size: u32 = switch (variant) {
                    .i64_atomic_rmw8_sub_u => 1,
                    .i64_atomic_rmw16_sub_u => 2,
                    .i64_atomic_rmw32_sub_u => 4,
                    else => unreachable,
                };
                if (addr + size > mem.len) return Error.InvalidAccess;

                const old_val: i64 = switch (size) {
                    1 => blk: {
                        const ptr = @as(*volatile u8, @ptrCast(&mem[addr]));
                        break :blk @atomicRmw(u8, ptr, .Sub, @truncate(@as(u64, @bitCast(val))), .seq_cst);
                    },
                    2 => blk: {
                        const ptr = @as(*volatile u16, @ptrCast(@alignCast(&mem[addr])));
                        break :blk @atomicRmw(u16, ptr, .Sub, @truncate(@as(u64, @bitCast(val))), .seq_cst);
                    },
                    4 => blk: {
                        const ptr = @as(*volatile u32, @ptrCast(@alignCast(&mem[addr])));
                        break :blk @atomicRmw(u32, ptr, .Sub, @truncate(@as(u64, @bitCast(val))), .seq_cst);
                    },
                    else => unreachable,
                };
                try stack.append(allocator, .{ .i64 = old_val });
            } else {
                return Error.InvalidAccess;
            }
        },

        // ===== AND OPERATIONS =====

        .i32_atomic_rmw_and => {
            const flags = try reader.readLEB128();
            const offset = try reader.readLEB128();
            _ = flags;

            if (stack.items.len < 2) return Error.StackUnderflow;
            const val = stack.pop().?.i32;
            const addr_val = stack.pop().?;
            const addr = @as(u32, @bitCast(addr_val.i32)) + @as(u32, @intCast(offset));

            if (memory) |mem| {
                if (addr + 4 > mem.len) return Error.InvalidAccess;
                const ptr = @as(*volatile u32, @ptrCast(@alignCast(&mem[addr])));
                const old_val = @atomicRmw(u32, ptr, .And, @bitCast(val), .seq_cst);
                try stack.append(allocator, .{ .i32 = @bitCast(old_val) });
            } else {
                return Error.InvalidAccess;
            }
        },

        .i64_atomic_rmw_and => {
            const flags = try reader.readLEB128();
            const offset = try reader.readLEB128();
            _ = flags;

            if (stack.items.len < 2) return Error.StackUnderflow;
            const val = stack.pop().?.i64;
            const addr_val = stack.pop().?;
            const addr = @as(u32, @bitCast(addr_val.i32)) + @as(u32, @intCast(offset));

            if (memory) |mem| {
                if (addr + 8 > mem.len) return Error.InvalidAccess;
                const ptr = @as(*volatile u64, @ptrCast(@alignCast(&mem[addr])));
                const old_val = @atomicRmw(u64, ptr, .And, @bitCast(val), .seq_cst);
                try stack.append(allocator, .{ .i64 = @bitCast(old_val) });
            } else {
                return Error.InvalidAccess;
            }
        },

        .i32_atomic_rmw8_and_u, .i32_atomic_rmw16_and_u => |variant| {
            const flags = try reader.readLEB128();
            const offset = try reader.readLEB128();
            _ = flags;

            if (stack.items.len < 2) return Error.StackUnderflow;
            const val = stack.pop().?.i32;
            const addr_val = stack.pop().?;
            const addr = @as(u32, @bitCast(addr_val.i32)) + @as(u32, @intCast(offset));

            if (memory) |mem| {
                const size: u32 = if (variant == .i32_atomic_rmw8_and_u) 1 else 2;
                if (addr + size > mem.len) return Error.InvalidAccess;

                if (size == 1) {
                    const ptr = @as(*volatile u8, @ptrCast(&mem[addr]));
                    const old_val = @atomicRmw(u8, ptr, .And, @truncate(@as(u32, @bitCast(val))), .seq_cst);
                    try stack.append(allocator, .{ .i32 = @as(i32, old_val) });
                } else {
                    const ptr = @as(*volatile u16, @ptrCast(@alignCast(&mem[addr])));
                    const old_val = @atomicRmw(u16, ptr, .And, @truncate(@as(u32, @bitCast(val))), .seq_cst);
                    try stack.append(allocator, .{ .i32 = @as(i32, old_val) });
                }
            } else {
                return Error.InvalidAccess;
            }
        },

        .i64_atomic_rmw8_and_u, .i64_atomic_rmw16_and_u, .i64_atomic_rmw32_and_u => |variant| {
            const flags = try reader.readLEB128();
            const offset = try reader.readLEB128();
            _ = flags;

            if (stack.items.len < 2) return Error.StackUnderflow;
            const val = stack.pop().?.i64;
            const addr_val = stack.pop().?;
            const addr = @as(u32, @bitCast(addr_val.i32)) + @as(u32, @intCast(offset));

            if (memory) |mem| {
                const size: u32 = switch (variant) {
                    .i64_atomic_rmw8_and_u => 1,
                    .i64_atomic_rmw16_and_u => 2,
                    .i64_atomic_rmw32_and_u => 4,
                    else => unreachable,
                };
                if (addr + size > mem.len) return Error.InvalidAccess;

                const old_val: i64 = switch (size) {
                    1 => blk: {
                        const ptr = @as(*volatile u8, @ptrCast(&mem[addr]));
                        break :blk @atomicRmw(u8, ptr, .And, @truncate(@as(u64, @bitCast(val))), .seq_cst);
                    },
                    2 => blk: {
                        const ptr = @as(*volatile u16, @ptrCast(@alignCast(&mem[addr])));
                        break :blk @atomicRmw(u16, ptr, .And, @truncate(@as(u64, @bitCast(val))), .seq_cst);
                    },
                    4 => blk: {
                        const ptr = @as(*volatile u32, @ptrCast(@alignCast(&mem[addr])));
                        break :blk @atomicRmw(u32, ptr, .And, @truncate(@as(u64, @bitCast(val))), .seq_cst);
                    },
                    else => unreachable,
                };
                try stack.append(allocator, .{ .i64 = old_val });
            } else {
                return Error.InvalidAccess;
            }
        },

        // ===== OR OPERATIONS =====

        .i32_atomic_rmw_or => {
            const flags = try reader.readLEB128();
            const offset = try reader.readLEB128();
            _ = flags;

            if (stack.items.len < 2) return Error.StackUnderflow;
            const val = stack.pop().?.i32;
            const addr_val = stack.pop().?;
            const addr = @as(u32, @bitCast(addr_val.i32)) + @as(u32, @intCast(offset));

            if (memory) |mem| {
                if (addr + 4 > mem.len) return Error.InvalidAccess;
                const ptr = @as(*volatile u32, @ptrCast(@alignCast(&mem[addr])));
                const old_val = @atomicRmw(u32, ptr, .Or, @bitCast(val), .seq_cst);
                try stack.append(allocator, .{ .i32 = @bitCast(old_val) });
            } else {
                return Error.InvalidAccess;
            }
        },

        .i64_atomic_rmw_or => {
            const flags = try reader.readLEB128();
            const offset = try reader.readLEB128();
            _ = flags;

            if (stack.items.len < 2) return Error.StackUnderflow;
            const val = stack.pop().?.i64;
            const addr_val = stack.pop().?;
            const addr = @as(u32, @bitCast(addr_val.i32)) + @as(u32, @intCast(offset));

            if (memory) |mem| {
                if (addr + 8 > mem.len) return Error.InvalidAccess;
                const ptr = @as(*volatile u64, @ptrCast(@alignCast(&mem[addr])));
                const old_val = @atomicRmw(u64, ptr, .Or, @bitCast(val), .seq_cst);
                try stack.append(allocator, .{ .i64 = @bitCast(old_val) });
            } else {
                return Error.InvalidAccess;
            }
        },

        .i32_atomic_rmw8_or_u, .i32_atomic_rmw16_or_u => |variant| {
            const flags = try reader.readLEB128();
            const offset = try reader.readLEB128();
            _ = flags;

            if (stack.items.len < 2) return Error.StackUnderflow;
            const val = stack.pop().?.i32;
            const addr_val = stack.pop().?;
            const addr = @as(u32, @bitCast(addr_val.i32)) + @as(u32, @intCast(offset));

            if (memory) |mem| {
                const size: u32 = if (variant == .i32_atomic_rmw8_or_u) 1 else 2;
                if (addr + size > mem.len) return Error.InvalidAccess;

                if (size == 1) {
                    const ptr = @as(*volatile u8, @ptrCast(&mem[addr]));
                    const old_val = @atomicRmw(u8, ptr, .Or, @truncate(@as(u32, @bitCast(val))), .seq_cst);
                    try stack.append(allocator, .{ .i32 = @as(i32, old_val) });
                } else {
                    const ptr = @as(*volatile u16, @ptrCast(@alignCast(&mem[addr])));
                    const old_val = @atomicRmw(u16, ptr, .Or, @truncate(@as(u32, @bitCast(val))), .seq_cst);
                    try stack.append(allocator, .{ .i32 = @as(i32, old_val) });
                }
            } else {
                return Error.InvalidAccess;
            }
        },

        .i64_atomic_rmw8_or_u, .i64_atomic_rmw16_or_u, .i64_atomic_rmw32_or_u => |variant| {
            const flags = try reader.readLEB128();
            const offset = try reader.readLEB128();
            _ = flags;

            if (stack.items.len < 2) return Error.StackUnderflow;
            const val = stack.pop().?.i64;
            const addr_val = stack.pop().?;
            const addr = @as(u32, @bitCast(addr_val.i32)) + @as(u32, @intCast(offset));

            if (memory) |mem| {
                const size: u32 = switch (variant) {
                    .i64_atomic_rmw8_or_u => 1,
                    .i64_atomic_rmw16_or_u => 2,
                    .i64_atomic_rmw32_or_u => 4,
                    else => unreachable,
                };
                if (addr + size > mem.len) return Error.InvalidAccess;

                const old_val: i64 = switch (size) {
                    1 => blk: {
                        const ptr = @as(*volatile u8, @ptrCast(&mem[addr]));
                        break :blk @atomicRmw(u8, ptr, .Or, @truncate(@as(u64, @bitCast(val))), .seq_cst);
                    },
                    2 => blk: {
                        const ptr = @as(*volatile u16, @ptrCast(@alignCast(&mem[addr])));
                        break :blk @atomicRmw(u16, ptr, .Or, @truncate(@as(u64, @bitCast(val))), .seq_cst);
                    },
                    4 => blk: {
                        const ptr = @as(*volatile u32, @ptrCast(@alignCast(&mem[addr])));
                        break :blk @atomicRmw(u32, ptr, .Or, @truncate(@as(u64, @bitCast(val))), .seq_cst);
                    },
                    else => unreachable,
                };
                try stack.append(allocator, .{ .i64 = old_val });
            } else {
                return Error.InvalidAccess;
            }
        },

        // ===== XOR OPERATIONS =====

        .i32_atomic_rmw_xor => {
            const flags = try reader.readLEB128();
            const offset = try reader.readLEB128();
            _ = flags;

            if (stack.items.len < 2) return Error.StackUnderflow;
            const val = stack.pop().?.i32;
            const addr_val = stack.pop().?;
            const addr = @as(u32, @bitCast(addr_val.i32)) + @as(u32, @intCast(offset));

            if (memory) |mem| {
                if (addr + 4 > mem.len) return Error.InvalidAccess;
                const ptr = @as(*volatile u32, @ptrCast(@alignCast(&mem[addr])));
                const old_val = @atomicRmw(u32, ptr, .Xor, @bitCast(val), .seq_cst);
                try stack.append(allocator, .{ .i32 = @bitCast(old_val) });
            } else {
                return Error.InvalidAccess;
            }
        },

        .i64_atomic_rmw_xor => {
            const flags = try reader.readLEB128();
            const offset = try reader.readLEB128();
            _ = flags;

            if (stack.items.len < 2) return Error.StackUnderflow;
            const val = stack.pop().?.i64;
            const addr_val = stack.pop().?;
            const addr = @as(u32, @bitCast(addr_val.i32)) + @as(u32, @intCast(offset));

            if (memory) |mem| {
                if (addr + 8 > mem.len) return Error.InvalidAccess;
                const ptr = @as(*volatile u64, @ptrCast(@alignCast(&mem[addr])));
                const old_val = @atomicRmw(u64, ptr, .Xor, @bitCast(val), .seq_cst);
                try stack.append(allocator, .{ .i64 = @bitCast(old_val) });
            } else {
                return Error.InvalidAccess;
            }
        },

        .i32_atomic_rmw8_xor_u, .i32_atomic_rmw16_xor_u => |variant| {
            const flags = try reader.readLEB128();
            const offset = try reader.readLEB128();
            _ = flags;

            if (stack.items.len < 2) return Error.StackUnderflow;
            const val = stack.pop().?.i32;
            const addr_val = stack.pop().?;
            const addr = @as(u32, @bitCast(addr_val.i32)) + @as(u32, @intCast(offset));

            if (memory) |mem| {
                const size: u32 = if (variant == .i32_atomic_rmw8_xor_u) 1 else 2;
                if (addr + size > mem.len) return Error.InvalidAccess;

                if (size == 1) {
                    const ptr = @as(*volatile u8, @ptrCast(&mem[addr]));
                    const old_val = @atomicRmw(u8, ptr, .Xor, @truncate(@as(u32, @bitCast(val))), .seq_cst);
                    try stack.append(allocator, .{ .i32 = @as(i32, old_val) });
                } else {
                    const ptr = @as(*volatile u16, @ptrCast(@alignCast(&mem[addr])));
                    const old_val = @atomicRmw(u16, ptr, .Xor, @truncate(@as(u32, @bitCast(val))), .seq_cst);
                    try stack.append(allocator, .{ .i32 = @as(i32, old_val) });
                }
            } else {
                return Error.InvalidAccess;
            }
        },

        .i64_atomic_rmw8_xor_u, .i64_atomic_rmw16_xor_u, .i64_atomic_rmw32_xor_u => |variant| {
            const flags = try reader.readLEB128();
            const offset = try reader.readLEB128();
            _ = flags;

            if (stack.items.len < 2) return Error.StackUnderflow;
            const val = stack.pop().?.i64;
            const addr_val = stack.pop().?;
            const addr = @as(u32, @bitCast(addr_val.i32)) + @as(u32, @intCast(offset));

            if (memory) |mem| {
                const size: u32 = switch (variant) {
                    .i64_atomic_rmw8_xor_u => 1,
                    .i64_atomic_rmw16_xor_u => 2,
                    .i64_atomic_rmw32_xor_u => 4,
                    else => unreachable,
                };
                if (addr + size > mem.len) return Error.InvalidAccess;

                const old_val: i64 = switch (size) {
                    1 => blk: {
                        const ptr = @as(*volatile u8, @ptrCast(&mem[addr]));
                        break :blk @atomicRmw(u8, ptr, .Xor, @truncate(@as(u64, @bitCast(val))), .seq_cst);
                    },
                    2 => blk: {
                        const ptr = @as(*volatile u16, @ptrCast(@alignCast(&mem[addr])));
                        break :blk @atomicRmw(u16, ptr, .Xor, @truncate(@as(u64, @bitCast(val))), .seq_cst);
                    },
                    4 => blk: {
                        const ptr = @as(*volatile u32, @ptrCast(@alignCast(&mem[addr])));
                        break :blk @atomicRmw(u32, ptr, .Xor, @truncate(@as(u64, @bitCast(val))), .seq_cst);
                    },
                    else => unreachable,
                };
                try stack.append(allocator, .{ .i64 = old_val });
            } else {
                return Error.InvalidAccess;
            }
        },

        // ===== XCHG (EXCHANGE) OPERATIONS =====

        .i32_atomic_rmw_xchg => {
            const flags = try reader.readLEB128();
            const offset = try reader.readLEB128();
            _ = flags;

            if (stack.items.len < 2) return Error.StackUnderflow;
            const val = stack.pop().?.i32;
            const addr_val = stack.pop().?;
            const addr = @as(u32, @bitCast(addr_val.i32)) + @as(u32, @intCast(offset));

            if (memory) |mem| {
                if (addr + 4 > mem.len) return Error.InvalidAccess;
                const ptr = @as(*volatile u32, @ptrCast(@alignCast(&mem[addr])));
                const old_val = @atomicRmw(u32, ptr, .Xchg, @bitCast(val), .seq_cst);
                try stack.append(allocator, .{ .i32 = @bitCast(old_val) });
            } else {
                return Error.InvalidAccess;
            }
        },

        .i64_atomic_rmw_xchg => {
            const flags = try reader.readLEB128();
            const offset = try reader.readLEB128();
            _ = flags;

            if (stack.items.len < 2) return Error.StackUnderflow;
            const val = stack.pop().?.i64;
            const addr_val = stack.pop().?;
            const addr = @as(u32, @bitCast(addr_val.i32)) + @as(u32, @intCast(offset));

            if (memory) |mem| {
                if (addr + 8 > mem.len) return Error.InvalidAccess;
                const ptr = @as(*volatile u64, @ptrCast(@alignCast(&mem[addr])));
                const old_val = @atomicRmw(u64, ptr, .Xchg, @bitCast(val), .seq_cst);
                try stack.append(allocator, .{ .i64 = @bitCast(old_val) });
            } else {
                return Error.InvalidAccess;
            }
        },

        .i32_atomic_rmw8_xchg_u, .i32_atomic_rmw16_xchg_u => |variant| {
            const flags = try reader.readLEB128();
            const offset = try reader.readLEB128();
            _ = flags;

            if (stack.items.len < 2) return Error.StackUnderflow;
            const val = stack.pop().?.i32;
            const addr_val = stack.pop().?;
            const addr = @as(u32, @bitCast(addr_val.i32)) + @as(u32, @intCast(offset));

            if (memory) |mem| {
                const size: u32 = if (variant == .i32_atomic_rmw8_xchg_u) 1 else 2;
                if (addr + size > mem.len) return Error.InvalidAccess;

                if (size == 1) {
                    const ptr = @as(*volatile u8, @ptrCast(&mem[addr]));
                    const old_val = @atomicRmw(u8, ptr, .Xchg, @truncate(@as(u32, @bitCast(val))), .seq_cst);
                    try stack.append(allocator, .{ .i32 = @as(i32, old_val) });
                } else {
                    const ptr = @as(*volatile u16, @ptrCast(@alignCast(&mem[addr])));
                    const old_val = @atomicRmw(u16, ptr, .Xchg, @truncate(@as(u32, @bitCast(val))), .seq_cst);
                    try stack.append(allocator, .{ .i32 = @as(i32, old_val) });
                }
            } else {
                return Error.InvalidAccess;
            }
        },

        .i64_atomic_rmw8_xchg_u, .i64_atomic_rmw16_xchg_u, .i64_atomic_rmw32_xchg_u => |variant| {
            const flags = try reader.readLEB128();
            const offset = try reader.readLEB128();
            _ = flags;

            if (stack.items.len < 2) return Error.StackUnderflow;
            const val = stack.pop().?.i64;
            const addr_val = stack.pop().?;
            const addr = @as(u32, @bitCast(addr_val.i32)) + @as(u32, @intCast(offset));

            if (memory) |mem| {
                const size: u32 = switch (variant) {
                    .i64_atomic_rmw8_xchg_u => 1,
                    .i64_atomic_rmw16_xchg_u => 2,
                    .i64_atomic_rmw32_xchg_u => 4,
                    else => unreachable,
                };
                if (addr + size > mem.len) return Error.InvalidAccess;

                const old_val: i64 = switch (size) {
                    1 => blk: {
                        const ptr = @as(*volatile u8, @ptrCast(&mem[addr]));
                        break :blk @atomicRmw(u8, ptr, .Xchg, @truncate(@as(u64, @bitCast(val))), .seq_cst);
                    },
                    2 => blk: {
                        const ptr = @as(*volatile u16, @ptrCast(@alignCast(&mem[addr])));
                        break :blk @atomicRmw(u16, ptr, .Xchg, @truncate(@as(u64, @bitCast(val))), .seq_cst);
                    },
                    4 => blk: {
                        const ptr = @as(*volatile u32, @ptrCast(@alignCast(&mem[addr])));
                        break :blk @atomicRmw(u32, ptr, .Xchg, @truncate(@as(u64, @bitCast(val))), .seq_cst);
                    },
                    else => unreachable,
                };
                try stack.append(allocator, .{ .i64 = old_val });
            } else {
                return Error.InvalidAccess;
            }
        },

        // ===== NARROW CMPXCHG OPERATIONS =====

        .i32_atomic_rmw8_cmpxchg_u, .i32_atomic_rmw16_cmpxchg_u => |variant| {
            const flags = try reader.readLEB128();
            const offset = try reader.readLEB128();
            _ = flags;

            if (stack.items.len < 3) return Error.StackUnderflow;
            const replacement = stack.pop().?.i32;
            const expected = stack.pop().?.i32;
            const addr_val = stack.pop().?;
            const addr = @as(u32, @bitCast(addr_val.i32)) + @as(u32, @intCast(offset));

            if (memory) |mem| {
                const size: u32 = if (variant == .i32_atomic_rmw8_cmpxchg_u) 1 else 2;
                if (addr + size > mem.len) return Error.InvalidAccess;

                if (size == 1) {
                    const ptr = @as(*volatile u8, @ptrCast(&mem[addr]));
                    const expected_u8 = @as(u8, @truncate(@as(u32, @bitCast(expected))));
                    const replacement_u8 = @as(u8, @truncate(@as(u32, @bitCast(replacement))));
                    const old_val = @cmpxchgStrong(u8, ptr, expected_u8, replacement_u8, .seq_cst, .seq_cst) orelse expected_u8;
                    try stack.append(allocator, .{ .i32 = @as(i32, old_val) });
                } else {
                    const ptr = @as(*volatile u16, @ptrCast(@alignCast(&mem[addr])));
                    const expected_u16 = @as(u16, @truncate(@as(u32, @bitCast(expected))));
                    const replacement_u16 = @as(u16, @truncate(@as(u32, @bitCast(replacement))));
                    const old_val = @cmpxchgStrong(u16, ptr, expected_u16, replacement_u16, .seq_cst, .seq_cst) orelse expected_u16;
                    try stack.append(allocator, .{ .i32 = @as(i32, old_val) });
                }
            } else {
                return Error.InvalidAccess;
            }
        },

        .i64_atomic_rmw8_cmpxchg_u, .i64_atomic_rmw16_cmpxchg_u, .i64_atomic_rmw32_cmpxchg_u => |variant| {
            const flags = try reader.readLEB128();
            const offset = try reader.readLEB128();
            _ = flags;

            if (stack.items.len < 3) return Error.StackUnderflow;
            const replacement = stack.pop().?.i64;
            const expected = stack.pop().?.i64;
            const addr_val = stack.pop().?;
            const addr = @as(u32, @bitCast(addr_val.i32)) + @as(u32, @intCast(offset));

            if (memory) |mem| {
                const size: u32 = switch (variant) {
                    .i64_atomic_rmw8_cmpxchg_u => 1,
                    .i64_atomic_rmw16_cmpxchg_u => 2,
                    .i64_atomic_rmw32_cmpxchg_u => 4,
                    else => unreachable,
                };
                if (addr + size > mem.len) return Error.InvalidAccess;

                const old_val: i64 = switch (size) {
                    1 => blk: {
                        const ptr = @as(*volatile u8, @ptrCast(&mem[addr]));
                        const expected_u8 = @as(u8, @truncate(@as(u64, @bitCast(expected))));
                        const replacement_u8 = @as(u8, @truncate(@as(u64, @bitCast(replacement))));
                        break :blk @cmpxchgStrong(u8, ptr, expected_u8, replacement_u8, .seq_cst, .seq_cst) orelse expected_u8;
                    },
                    2 => blk: {
                        const ptr = @as(*volatile u16, @ptrCast(@alignCast(&mem[addr])));
                        const expected_u16 = @as(u16, @truncate(@as(u64, @bitCast(expected))));
                        const replacement_u16 = @as(u16, @truncate(@as(u64, @bitCast(replacement))));
                        break :blk @cmpxchgStrong(u16, ptr, expected_u16, replacement_u16, .seq_cst, .seq_cst) orelse expected_u16;
                    },
                    4 => blk: {
                        const ptr = @as(*volatile u32, @ptrCast(@alignCast(&mem[addr])));
                        const expected_u32 = @as(u32, @truncate(@as(u64, @bitCast(expected))));
                        const replacement_u32 = @as(u32, @truncate(@as(u64, @bitCast(replacement))));
                        break :blk @cmpxchgStrong(u32, ptr, expected_u32, replacement_u32, .seq_cst, .seq_cst) orelse expected_u32;
                    },
                    else => unreachable,
                };
                try stack.append(allocator, .{ .i64 = old_val });
            } else {
                return Error.InvalidAccess;
            }
        },

        // ===== NARROW ADD OPERATIONS (already partially implemented above) =====

        .i32_atomic_rmw8_add_u, .i32_atomic_rmw16_add_u => |variant| {
            const flags = try reader.readLEB128();
            const offset = try reader.readLEB128();
            _ = flags;

            if (stack.items.len < 2) return Error.StackUnderflow;
            const val = stack.pop().?.i32;
            const addr_val = stack.pop().?;
            const addr = @as(u32, @bitCast(addr_val.i32)) + @as(u32, @intCast(offset));

            if (memory) |mem| {
                const size: u32 = if (variant == .i32_atomic_rmw8_add_u) 1 else 2;
                if (addr + size > mem.len) return Error.InvalidAccess;

                if (size == 1) {
                    const ptr = @as(*volatile u8, @ptrCast(&mem[addr]));
                    const old_val = @atomicRmw(u8, ptr, .Add, @truncate(@as(u32, @bitCast(val))), .seq_cst);
                    try stack.append(allocator, .{ .i32 = @as(i32, old_val) });
                } else {
                    const ptr = @as(*volatile u16, @ptrCast(@alignCast(&mem[addr])));
                    const old_val = @atomicRmw(u16, ptr, .Add, @truncate(@as(u32, @bitCast(val))), .seq_cst);
                    try stack.append(allocator, .{ .i32 = @as(i32, old_val) });
                }
            } else {
                return Error.InvalidAccess;
            }
        },

        .i64_atomic_rmw8_add_u, .i64_atomic_rmw16_add_u, .i64_atomic_rmw32_add_u => |variant| {
            const flags = try reader.readLEB128();
            const offset = try reader.readLEB128();
            _ = flags;

            if (stack.items.len < 2) return Error.StackUnderflow;
            const val = stack.pop().?.i64;
            const addr_val = stack.pop().?;
            const addr = @as(u32, @bitCast(addr_val.i32)) + @as(u32, @intCast(offset));

            if (memory) |mem| {
                const size: u32 = switch (variant) {
                    .i64_atomic_rmw8_add_u => 1,
                    .i64_atomic_rmw16_add_u => 2,
                    .i64_atomic_rmw32_add_u => 4,
                    else => unreachable,
                };
                if (addr + size > mem.len) return Error.InvalidAccess;

                const old_val: i64 = switch (size) {
                    1 => blk: {
                        const ptr = @as(*volatile u8, @ptrCast(&mem[addr]));
                        break :blk @atomicRmw(u8, ptr, .Add, @truncate(@as(u64, @bitCast(val))), .seq_cst);
                    },
                    2 => blk: {
                        const ptr = @as(*volatile u16, @ptrCast(@alignCast(&mem[addr])));
                        break :blk @atomicRmw(u16, ptr, .Add, @truncate(@as(u64, @bitCast(val))), .seq_cst);
                    },
                    4 => blk: {
                        const ptr = @as(*volatile u32, @ptrCast(@alignCast(&mem[addr])));
                        break :blk @atomicRmw(u32, ptr, .Add, @truncate(@as(u64, @bitCast(val))), .seq_cst);
                    },
                    else => unreachable,
                };
                try stack.append(allocator, .{ .i64 = old_val });
            } else {
                return Error.InvalidAccess;
            }
        },
    }
}

/// Shared memory for multi-threaded execution
pub const SharedMemory = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    memory: []u8,
    is_shared: bool,
    max_pages: u32,
    mutex: @import("sync").Mutex,

    pub fn init(allocator: std.mem.Allocator, initial_pages: u32, max_pages: u32, shared: bool) !Self {
        const memory = try allocator.alloc(u8, initial_pages * 65536);
        return Self{
            .allocator = allocator,
            .memory = memory,
            .is_shared = shared,
            .max_pages = max_pages,
            .mutex = @import("sync").Mutex{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.memory);
    }

    pub fn grow(self: *Self, delta_pages: u32) !u32 {
        const old_pages = @as(u32, @intCast(self.memory.len / 65536));
        const new_pages = old_pages + delta_pages;

        if (new_pages > self.max_pages) return error.MemoryGrowFailed;

        self.mutex.lock();
        defer self.mutex.unlock();

        const new_memory = try self.allocator.realloc(self.memory, new_pages * 65536);
        self.memory = new_memory;

        return old_pages;
    }

    pub fn atomicLoad(self: *Self, addr: u32, comptime T: type) !T {
        if (addr + @sizeOf(T) > self.memory.len) return Error.InvalidAccess;

        if (self.is_shared) {
            self.mutex.lock();
            defer self.mutex.unlock();
        }

        return std.mem.readInt(T, self.memory[addr..][0..@sizeOf(T)], .little);
    }

    pub fn atomicStore(self: *Self, addr: u32, comptime T: type, value: T) !void {
        if (addr + @sizeOf(T) > self.memory.len) return Error.InvalidAccess;

        if (self.is_shared) {
            self.mutex.lock();
            defer self.mutex.unlock();
        }

        std.mem.writeInt(T, self.memory[addr..][0..@sizeOf(T)], value, .little);
    }

    pub fn atomicRMW(self: *Self, addr: u32, comptime T: type, value: T, comptime op: RMWOp) !T {
        if (addr + @sizeOf(T) > self.memory.len) return Error.InvalidAccess;

        self.mutex.lock();
        defer self.mutex.unlock();

        const old = std.mem.readInt(T, self.memory[addr..][0..@sizeOf(T)], .little);
        const new = switch (op) {
            .add => old +% value,
            .sub => old -% value,
            .and_ => old & value,
            .or_ => old | value,
            .xor => old ^ value,
            .xchg => value,
        };
        std.mem.writeInt(T, self.memory[addr..][0..@sizeOf(T)], new, .little);

        return old;
    }

    pub fn atomicCompareExchange(self: *Self, addr: u32, comptime T: type, expected: T, replacement: T) !T {
        if (addr + @sizeOf(T) > self.memory.len) return Error.InvalidAccess;

        self.mutex.lock();
        defer self.mutex.unlock();

        const current = std.mem.readInt(T, self.memory[addr..][0..@sizeOf(T)], .little);
        if (current == expected) {
            std.mem.writeInt(T, self.memory[addr..][0..@sizeOf(T)], replacement, .little);
        }

        return current;
    }

    pub const RMWOp = enum {
        add,
        sub,
        and_,
        or_,
        xor,
        xchg,
    };
};

/// Thread pool for WebAssembly thread execution
pub const ThreadPool = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    threads: std.ArrayList(WorkerThread),
    max_threads: u32,
    shared_memory: ?*SharedMemory,
    next_thread_id: u32 = 0,
    running: bool = true,
    message_queue: std.ArrayList(ThreadMessage),
    message_mutex: @import("sync").Mutex,
    message_cond: @import("sync").Condition,

    pub const WorkerThread = struct {
        id: u32,
        is_running: bool,
        exit_code: u32,
        func_idx: u32,
        args: []Value,
        stack_base: usize,
        tls_offset: usize,
        native_thread: ?std.Thread,

        pub fn init(id: u32, func_idx: u32, args: []Value) WorkerThread {
            return WorkerThread{
                .id = id,
                .is_running = false,
                .exit_code = 0,
                .func_idx = func_idx,
                .args = args,
                .stack_base = 0,
                .tls_offset = 0,
                .native_thread = null,
            };
        }

        pub fn deinit(self: *WorkerThread, allocator: std.mem.Allocator) void {
            allocator.free(self.args);
        }
    };

    pub fn init(allocator: std.mem.Allocator, max_threads: u32) Self {
        return Self{
            .allocator = allocator,
            .threads = .empty,
            .max_threads = max_threads,
            .shared_memory = null,
            .message_queue = .empty,
            .message_mutex = @import("sync").Mutex{},
            .message_cond = @import("sync").Condition{},
        };
    }

    pub fn deinit(self: *Self) void {
        // Signal all threads to shutdown
        self.running = false;
        self.message_cond.broadcast();

        // Wait for and cleanup all threads
        for (self.threads.items) |*worker| {
            self.joinThread(worker.id) catch {};
            worker.deinit(self.allocator);
        }

        self.threads.deinit(self.allocator);
        self.message_queue.deinit(self.allocator);
    }

    pub fn setSharedMemory(self: *Self, memory: *SharedMemory) void {
        self.shared_memory = memory;
    }

    pub fn spawnThread(self: *Self, func_idx: u32, args: []const Value) !u32 {
        if (self.threads.items.len >= self.max_threads) return error.TooManyThreads;
        if (builtin.single_threaded) return error.SingleThreaded;

        const thread_id = self.next_thread_id;
        self.next_thread_id += 1;

        const args_copy = try self.allocator.dupe(Value, args);

        var worker = WorkerThread.init(thread_id, func_idx, args_copy);

        // Spawn the actual thread
        const native_thread = try std.Thread.spawn(.{}, threadWorker, .{ self, thread_id });
        worker.native_thread = native_thread;
        worker.is_running = true;

        try self.threads.append(self.allocator, worker);

        var o = Log.op("ThreadPool", "spawnThread");
        o.log("Spawned thread: id={d}, func={d}", .{ thread_id, func_idx });

        return thread_id;
    }

    fn threadWorker(pool: *Self, thread_id: u32) void {
        var o = Log.op("ThreadWorker", "run");
        o.log("Thread started: id={d}", .{thread_id});

        // Find our worker
        const worker_idx = for (pool.threads.items, 0..) |w, i| {
            if (w.id == thread_id) break i;
        } else {
            o.log("Thread not found in pool!", .{});
            return;
        };

        const worker = &pool.threads.items[worker_idx];

        // Execute the function (this would call into the WASM runtime)
        // For now, just mark as running
        worker.is_running = true;

        // Wait for shutdown signal
        pool.message_mutex.lock();
        defer pool.message_mutex.unlock();

        while (pool.running) {
            pool.message_cond.wait(&pool.message_mutex);
        }

        o.log("Thread exiting: id={d}", .{thread_id});
        worker.is_running = false;
    }

    pub fn joinThread(self: *Self, thread_id: u32) !void {
        for (self.threads.items) |*worker| {
            if (worker.id == thread_id) {
                if (worker.native_thread) |thread| {
                    thread.join();
                    worker.native_thread = null;
                }
                worker.is_running = false;
                return;
            }
        }
        return error.InvalidThreadId;
    }

    pub fn killThread(self: *Self, thread_id: u32, exit_code: u32) !void {
        for (self.threads.items) |*worker| {
            if (worker.id == thread_id) {
                worker.exit_code = exit_code;
                worker.is_running = false;
                if (worker.native_thread) |thread| {
                    thread.join();
                    worker.native_thread = null;
                }
                return;
            }
        }
        return error.InvalidThreadId;
    }

    pub fn getThreadCount(self: *Self) u32 {
        return @intCast(self.threads.items.len);
    }

    pub fn getActiveThreadCount(self: *Self) u32 {
        var count: u32 = 0;
        for (self.threads.items) |*worker| {
            if (worker.is_running) count += 1;
        }
        return count;
    }

    pub fn sendMessage(self: *Self, from: u32, to: u32, msg_type: ThreadMessage.MessageType, data: []const u8) !void {
        const message = ThreadMessage{
            .id = self.nextMessageId(),
            .from_thread = from,
            .to_thread = to,
            .type = msg_type,
            .data = try self.allocator.dupe(u8, data),
            .timestamp = @import("../util/time.zig").nanoTimestamp(),
        };

        self.message_mutex.lock();
        defer self.message_mutex.unlock();

        try self.message_queue.append(self.allocator, message);
        self.message_cond.signal();
    }

    fn nextMessageId(self: *Self) u32 {
        _ = self;
        return std.crypto.randomInt(u32);
    }

    pub fn tryReceiveMessage(self: *Self, thread_id: u32) ?ThreadMessage {
        self.message_mutex.lock();
        defer self.message_mutex.unlock();

        for (self.message_queue.items, 0..) |msg, i| {
            if (msg.to_thread == thread_id) {
                return self.message_queue.orderedRemove(i);
            }
        }
        return null;
    }
};

/// Wait/notify queue for thread synchronization (futex-style)
pub const WaitQueue = struct {
    const Self = @This();
    const WaitEntry = struct {
        addr: u32,
        thread_id: u32,
        expected_value: u64,
        timeout_ns: i64,
        notified: bool,
        condition: @import("sync").Condition,
    };

    allocator: std.mem.Allocator,
    waiters: std.ArrayList(WaitEntry),
    mutex: @import("sync").Mutex,
    timeout_resolutions: std.ArrayList(*WaitEntry),

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .waiters = std.ArrayList(WaitEntry).init(allocator),
            .mutex = @import("sync").Mutex{},
            .timeout_resolutions = std.ArrayList(*WaitEntry).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        // Signal all waiters to wake up
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.waiters.items) |*entry| {
            entry.notified = true;
            entry.condition.broadcast();
        }

        self.waiters.deinit();
        self.timeout_resolutions.deinit();
    }

    /// Wait on a memory address (32-bit)
    pub fn wait32(self: *Self, addr: u32, expected: u32, timeout_ns: i64) !i32 {
        self.mutex.lock();
        defer self.mutex.unlock();

        const entry = WaitEntry{
            .addr = addr,
            .thread_id = 0, // Would be set to actual thread ID
            .expected_value = expected,
            .timeout_ns = timeout_ns,
            .notified = false,
            .condition = @import("sync").Condition{},
        };

        try self.waiters.append(entry);
        try self.timeout_resolutions.append(&self.waiters.items[self.waiters.items.len - 1]);

        // Wait for notification or timeout
        const deadline = if (timeout_ns > 0) @import("../util/time.zig").nanoTimestamp() + timeout_ns else 0;

        while (!entry.notified) {
            if (timeout_ns > 0) {
                const remaining = deadline - @import("../util/time.zig").nanoTimestamp();
                if (remaining <= 0) {
                    // Timeout
                    entry.notified = true;
                    return 2; // TimedOut
                }
                entry.condition.timedwait(&self.mutex, @as(u64, @intCast(remaining))) catch {};
            } else {
                entry.condition.wait(&self.mutex);
            }
        }

        return 0; // NotEqual - value didn't match
    }

    /// Wait on a memory address (64-bit)
    pub fn wait64(self: *Self, addr: u32, expected: u64, timeout_ns: i64) !i32 {
        self.mutex.lock();
        defer self.mutex.unlock();

        const entry = WaitEntry{
            .addr = addr,
            .thread_id = 0,
            .expected_value = expected,
            .timeout_ns = timeout_ns,
            .notified = false,
            .condition = @import("sync").Condition{},
        };

        try self.waiters.append(entry);
        try self.timeout_resolutions.append(&self.waiters.items[self.waiters.items.len - 1]);

        const deadline = if (timeout_ns > 0) @import("../util/time.zig").nanoTimestamp() + timeout_ns else 0;

        while (!entry.notified) {
            if (timeout_ns > 0) {
                const remaining = deadline - @import("../util/time.zig").nanoTimestamp();
                if (remaining <= 0) {
                    entry.notified = true;
                    return 2; // TimedOut
                }
                entry.condition.timedwait(&self.mutex, @as(u64, @intCast(remaining))) catch {};
            } else {
                entry.condition.wait(&self.mutex);
            }
        }

        return 0;
    }

    /// Notify threads waiting on an address
    pub fn notify(self: *Self, addr: u32, count: u32, all: bool) !u32 {
        self.mutex.lock();
        defer self.mutex.unlock();

        var notified: u32 = 0;
        var i: usize = 0;

        while (i < self.waiters.items.len and notified < count) {
            const entry = &self.waiters.items[i];

            if (entry.addr == addr) {
                entry.notified = true;
                entry.condition.broadcast();
                notified += 1;

                if (!all) {
                    _ = self.waiters.swapRemove(i);
                    continue;
                }
            }

            i += 1;
        }

        return notified;
    }

    /// Notify all threads waiting on an address
    pub fn notifyAll(self: *Self, addr: u32) !u32 {
        return self.notify(addr, std.math.maxInt(u32), true);
    }

    /// Get wait count for an address
    pub fn getWaitCount(self: *Self, addr: u32) usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        var count: usize = 0;
        for (self.waiters.items) |entry| {
            if (entry.addr == addr) count += 1;
        }
        return count;
    }
};

/// Thread-local storage
pub const ThreadLocal = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    storage: std.AutoHashMap(u32, std.StringHashMap(Value)),
    mutex: @import("sync").Mutex,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .storage = std.AutoHashMap(u32, std.StringHashMap(Value)).init(allocator),
            .mutex = @import("sync").Mutex{},
        };
    }

    pub fn deinit(self: *Self) void {
        var it = self.storage.valueIterator();
        while (it.next()) |map| {
            map.deinit();
        }
        self.storage.deinit();
    }

    pub fn set(self: *Self, thread_id: u32, key: []const u8, value: Value) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const result = try self.storage.getOrPut(thread_id);
        if (!result.found_existing) {
            result.value_ptr.* = std.StringHashMap(Value).init(self.allocator);
        }

        const key_copy = try self.allocator.dupe(u8, key);
        try result.value_ptr.put(key_copy, value);
    }

    pub fn get(self: *Self, thread_id: u32, key: []const u8) ?Value {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.storage.get(thread_id)) |map| {
            return map.get(key);
        }
        return null;
    }

    pub fn remove(self: *Self, thread_id: u32, key: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.storage.getPtr(thread_id)) |map| {
            if (map.fetchRemove(key)) |entry| {
                self.allocator.free(entry.key);
            }
        }
    }
};
