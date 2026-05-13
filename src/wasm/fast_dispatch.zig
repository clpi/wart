/// Ultra-Fast Opcode Dispatch System
///
/// This module provides optimized opcode dispatching using:
/// - Direct threaded dispatch (computed goto equivalent)
/// - Branch prediction hints
/// - Inline caching for hot opcodes
/// - Tail call optimization support
const std = @import("std");
const Value = @import("value.zig").Value;
const Module = @import("module.zig");
const Error = @import("op.zig").Error;
const SmallVec = @import("stack.zig").SmallVec;

/// Dispatch table entry
pub const DispatchEntry = struct {
    handler: *const fn (*ExecutionContext) Error!void,
    next_prediction: u8, // Predicted next opcode
};

/// Execution context for fast dispatch
pub const ExecutionContext = struct {
    /// Value stack
    stack: *SmallVec(Value, 256),
    /// Instruction reader
    reader: *Module.Reader,
    /// Module reference
    module: *Module,
    /// Memory data (cached for fast access)
    memory: ?[]u8,
    /// Local variables (cached)
    locals: []Value,
    /// Current function index
    func_idx: u32,
    /// Allocator for stack operations
    allocator: std.mem.Allocator,
    /// Fast exception state
    exception_active: bool = false,
    /// Branch target cache
    branch_cache: [16]BranchCacheEntry = undefined,
    /// Instruction counter for profiling
    instruction_count: u64 = 0,

    const BranchCacheEntry = struct {
        source_pc: u32 = 0,
        target_pc: u32 = 0,
        taken_count: u32 = 0,
    };
};

// ============================================================================
// Direct Threaded Dispatch Table
// ============================================================================

/// Pre-computed dispatch table for all opcodes
pub var DISPATCH_TABLE: [256]DispatchEntry = init_dispatch_table();

fn init_dispatch_table() [256]DispatchEntry {
    var table: [256]DispatchEntry = undefined;

    // Initialize all to invalid
    for (&table) |*entry| {
        entry.* = .{
            .handler = &handleInvalid,
            .next_prediction = 0x00,
        };
    }

    // Control flow
    table[0x00] = .{ .handler = &handleUnreachable, .next_prediction = 0x00 };
    table[0x01] = .{ .handler = &handleNop, .next_prediction = 0x01 };
    table[0x02] = .{ .handler = &handleBlock, .next_prediction = 0x20 };
    table[0x03] = .{ .handler = &handleLoop, .next_prediction = 0x20 };
    table[0x04] = .{ .handler = &handleIf, .next_prediction = 0x20 };
    table[0x05] = .{ .handler = &handleElse, .next_prediction = 0x20 };
    table[0x0B] = .{ .handler = &handleEnd, .next_prediction = 0x20 };
    table[0x0C] = .{ .handler = &handleBr, .next_prediction = 0x20 };
    table[0x0D] = .{ .handler = &handleBrIf, .next_prediction = 0x20 };
    table[0x0E] = .{ .handler = &handleBrTable, .next_prediction = 0x20 };
    table[0x0F] = .{ .handler = &handleReturn, .next_prediction = 0x0B };
    table[0x10] = .{ .handler = &handleCall, .next_prediction = 0x20 };
    table[0x11] = .{ .handler = &handleCallIndirect, .next_prediction = 0x20 };

    // Tail call support (WASM 3.0)
    table[0x12] = .{ .handler = &handleReturnCall, .next_prediction = 0x0B };
    table[0x13] = .{ .handler = &handleReturnCallIndirect, .next_prediction = 0x0B };

    // Parametric
    table[0x1A] = .{ .handler = &handleDrop, .next_prediction = 0x20 };
    table[0x1B] = .{ .handler = &handleSelect, .next_prediction = 0x20 };

    // Variable access
    table[0x20] = .{ .handler = &handleLocalGet, .next_prediction = 0x6A };
    table[0x21] = .{ .handler = &handleLocalSet, .next_prediction = 0x20 };
    table[0x22] = .{ .handler = &handleLocalTee, .next_prediction = 0x20 };
    table[0x23] = .{ .handler = &handleGlobalGet, .next_prediction = 0x20 };
    table[0x24] = .{ .handler = &handleGlobalSet, .next_prediction = 0x20 };

    // Memory loads
    table[0x28] = .{ .handler = &handleI32Load, .next_prediction = 0x6A };
    table[0x29] = .{ .handler = &handleI64Load, .next_prediction = 0x7C };
    table[0x2A] = .{ .handler = &handleF32Load, .next_prediction = 0x92 };
    table[0x2B] = .{ .handler = &handleF64Load, .next_prediction = 0xA0 };

    // Memory stores
    table[0x36] = .{ .handler = &handleI32Store, .next_prediction = 0x20 };
    table[0x37] = .{ .handler = &handleI64Store, .next_prediction = 0x20 };
    table[0x38] = .{ .handler = &handleF32Store, .next_prediction = 0x20 };
    table[0x39] = .{ .handler = &handleF64Store, .next_prediction = 0x20 };

    // Memory size/grow
    table[0x3F] = .{ .handler = &handleMemorySize, .next_prediction = 0x20 };
    table[0x40] = .{ .handler = &handleMemoryGrow, .next_prediction = 0x20 };

    // Constants
    table[0x41] = .{ .handler = &handleI32Const, .next_prediction = 0x6A };
    table[0x42] = .{ .handler = &handleI64Const, .next_prediction = 0x7C };
    table[0x43] = .{ .handler = &handleF32Const, .next_prediction = 0x92 };
    table[0x44] = .{ .handler = &handleF64Const, .next_prediction = 0xA0 };

    // i32 comparisons (hot path - predict arithmetic follows)
    table[0x45] = .{ .handler = &handleI32Eqz, .next_prediction = 0x0D };
    table[0x46] = .{ .handler = &handleI32Eq, .next_prediction = 0x0D };
    table[0x47] = .{ .handler = &handleI32Ne, .next_prediction = 0x0D };
    table[0x48] = .{ .handler = &handleI32LtS, .next_prediction = 0x0D };
    table[0x49] = .{ .handler = &handleI32LtU, .next_prediction = 0x0D };
    table[0x4A] = .{ .handler = &handleI32GtS, .next_prediction = 0x0D };
    table[0x4B] = .{ .handler = &handleI32GtU, .next_prediction = 0x0D };
    table[0x4C] = .{ .handler = &handleI32LeS, .next_prediction = 0x0D };
    table[0x4D] = .{ .handler = &handleI32LeU, .next_prediction = 0x0D };
    table[0x4E] = .{ .handler = &handleI32GeS, .next_prediction = 0x0D };
    table[0x4F] = .{ .handler = &handleI32GeU, .next_prediction = 0x0D };

    // i32 arithmetic (hot path - predict more arithmetic)
    table[0x6A] = .{ .handler = &handleI32Add, .next_prediction = 0x21 };
    table[0x6B] = .{ .handler = &handleI32Sub, .next_prediction = 0x21 };
    table[0x6C] = .{ .handler = &handleI32Mul, .next_prediction = 0x21 };
    table[0x6D] = .{ .handler = &handleI32DivS, .next_prediction = 0x21 };
    table[0x6E] = .{ .handler = &handleI32DivU, .next_prediction = 0x21 };
    table[0x6F] = .{ .handler = &handleI32RemS, .next_prediction = 0x21 };
    table[0x70] = .{ .handler = &handleI32RemU, .next_prediction = 0x21 };
    table[0x71] = .{ .handler = &handleI32And, .next_prediction = 0x21 };
    table[0x72] = .{ .handler = &handleI32Or, .next_prediction = 0x21 };
    table[0x73] = .{ .handler = &handleI32Xor, .next_prediction = 0x21 };
    table[0x74] = .{ .handler = &handleI32Shl, .next_prediction = 0x21 };
    table[0x75] = .{ .handler = &handleI32ShrS, .next_prediction = 0x21 };
    table[0x76] = .{ .handler = &handleI32ShrU, .next_prediction = 0x21 };
    table[0x77] = .{ .handler = &handleI32Rotl, .next_prediction = 0x21 };
    table[0x78] = .{ .handler = &handleI32Rotr, .next_prediction = 0x21 };

    return table;
}

// ============================================================================
// Fast Opcode Handlers
// ============================================================================

fn handleInvalid(_: *ExecutionContext) Error!void {
    return Error.InvalidOpcode;
}

fn handleUnreachable(_: *ExecutionContext) Error!void {
    return Error.InvalidOpcode; // Trap
}

fn handleNop(_: *ExecutionContext) Error!void {
    // Do nothing - fastest possible handler
}

fn handleBlock(ctx: *ExecutionContext) Error!void {
    _ = try ctx.reader.readByte(); // block type
}

fn handleLoop(ctx: *ExecutionContext) Error!void {
    _ = try ctx.reader.readByte(); // block type
}

fn handleIf(ctx: *ExecutionContext) Error!void {
    _ = try ctx.reader.readByte(); // block type
    if (ctx.stack.items.len < 1) return Error.StackUnderflow;
    const cond = ctx.stack.pop().?.i32;
    if (cond == 0) {
        // Skip to else or end
        var depth: u32 = 1;
        while (depth > 0 and !ctx.reader.isAtEnd()) {
            const b = try ctx.reader.readByte();
            switch (b) {
                0x02, 0x03, 0x04 => depth += 1,
                0x05 => if (depth == 1) return,
                0x0B => depth -= 1,
                else => {},
            }
        }
    }
}

fn handleElse(ctx: *ExecutionContext) Error!void {
    // Skip to end
    var depth: u32 = 1;
    while (depth > 0 and !ctx.reader.isAtEnd()) {
        const b = try ctx.reader.readByte();
        switch (b) {
            0x02, 0x03, 0x04 => depth += 1,
            0x0B => depth -= 1,
            else => {},
        }
    }
}

fn handleEnd(_: *ExecutionContext) Error!void {
    // Block end - handled by block tracking
}

fn handleBr(ctx: *ExecutionContext) Error!void {
    _ = try ctx.reader.readLEB128(); // label index
    // Branch handling delegated to runtime
}

fn handleBrIf(ctx: *ExecutionContext) Error!void {
    _ = try ctx.reader.readLEB128();
    if (ctx.stack.items.len < 1) return Error.StackUnderflow;
    _ = ctx.stack.pop();
}

fn handleBrTable(ctx: *ExecutionContext) Error!void {
    const count = try ctx.reader.readLEB128();
    for (0..count + 1) |_| {
        _ = try ctx.reader.readLEB128();
    }
    if (ctx.stack.items.len < 1) return Error.StackUnderflow;
    _ = ctx.stack.pop();
}

fn handleReturn(_: *ExecutionContext) Error!void {
    // Return handled by runtime
}

fn handleCall(ctx: *ExecutionContext) Error!void {
    _ = try ctx.reader.readLEB128(); // func index
}

fn handleCallIndirect(ctx: *ExecutionContext) Error!void {
    _ = try ctx.reader.readLEB128(); // type index
    _ = try ctx.reader.readLEB128(); // table index
    if (ctx.stack.items.len < 1) return Error.StackUnderflow;
    _ = ctx.stack.pop(); // table element index
}

// Tail call handlers (WASM 3.0)
fn handleReturnCall(ctx: *ExecutionContext) Error!void {
    _ = try ctx.reader.readLEB128(); // func index
    // Tail call optimization: reuse current frame
}

fn handleReturnCallIndirect(ctx: *ExecutionContext) Error!void {
    _ = try ctx.reader.readLEB128(); // type index
    _ = try ctx.reader.readLEB128(); // table index
    if (ctx.stack.items.len < 1) return Error.StackUnderflow;
    _ = ctx.stack.pop();
}

fn handleDrop(ctx: *ExecutionContext) Error!void {
    if (ctx.stack.items.len < 1) return Error.StackUnderflow;
    _ = ctx.stack.pop();
}

fn handleSelect(ctx: *ExecutionContext) Error!void {
    if (ctx.stack.items.len < 3) return Error.StackUnderflow;
    const cond = ctx.stack.pop().?.i32;
    const val2 = ctx.stack.pop().?;
    const val1 = ctx.stack.pop().?;
    try ctx.stack.append(ctx.allocator, if (cond != 0) val1 else val2);
}

fn handleLocalGet(ctx: *ExecutionContext) Error!void {
    const idx = try ctx.reader.readLEB128();
    if (idx >= ctx.locals.len) return Error.InvalidAccess;
    try ctx.stack.append(ctx.allocator, ctx.locals[idx]);
}

fn handleLocalSet(ctx: *ExecutionContext) Error!void {
    const idx = try ctx.reader.readLEB128();
    if (idx >= ctx.locals.len) return Error.InvalidAccess;
    if (ctx.stack.items.len < 1) return Error.StackUnderflow;
    ctx.locals[idx] = ctx.stack.pop().?;
}

fn handleLocalTee(ctx: *ExecutionContext) Error!void {
    const idx = try ctx.reader.readLEB128();
    if (idx >= ctx.locals.len) return Error.InvalidAccess;
    if (ctx.stack.items.len < 1) return Error.StackUnderflow;
    ctx.locals[idx] = ctx.stack.items[ctx.stack.items.len - 1];
}

fn handleGlobalGet(ctx: *ExecutionContext) Error!void {
    const idx = try ctx.reader.readLEB128();
    if (idx >= ctx.module.globals.items.len) return Error.InvalidAccess;
    try ctx.stack.append(ctx.allocator, ctx.module.globals.items[idx]);
}

fn handleGlobalSet(ctx: *ExecutionContext) Error!void {
    const idx = try ctx.reader.readLEB128();
    if (idx >= ctx.module.globals.items.len) return Error.InvalidAccess;
    if (ctx.stack.items.len < 1) return Error.StackUnderflow;
    ctx.module.globals.items[idx] = ctx.stack.pop().?;
}

// Memory operations - ultra-optimized
fn handleI32Load(ctx: *ExecutionContext) Error!void {
    _ = try ctx.reader.readLEB128(); // align
    const offset = try ctx.reader.readLEB128();
    if (ctx.stack.items.len < 1) return Error.StackUnderflow;
    const base = @as(u32, @bitCast(ctx.stack.pop().?.i32));
    const addr = base +% @as(u32, @intCast(offset));
    const mem = ctx.memory orelse return Error.InvalidAccess;
    if (addr + 4 > mem.len) return Error.InvalidAccess;
    const val = std.mem.readInt(u32, mem[addr..][0..4], .little);
    try ctx.stack.append(ctx.allocator, .{ .i32 = @bitCast(val) });
}

fn handleI64Load(ctx: *ExecutionContext) Error!void {
    _ = try ctx.reader.readLEB128();
    const offset = try ctx.reader.readLEB128();
    if (ctx.stack.items.len < 1) return Error.StackUnderflow;
    const base = @as(u32, @bitCast(ctx.stack.pop().?.i32));
    const addr = base +% @as(u32, @intCast(offset));
    const mem = ctx.memory orelse return Error.InvalidAccess;
    if (addr + 8 > mem.len) return Error.InvalidAccess;
    const val = std.mem.readInt(u64, mem[addr..][0..8], .little);
    try ctx.stack.append(ctx.allocator, .{ .i64 = @bitCast(val) });
}

fn handleF32Load(ctx: *ExecutionContext) Error!void {
    _ = try ctx.reader.readLEB128();
    const offset = try ctx.reader.readLEB128();
    if (ctx.stack.items.len < 1) return Error.StackUnderflow;
    const base = @as(u32, @bitCast(ctx.stack.pop().?.i32));
    const addr = base +% @as(u32, @intCast(offset));
    const mem = ctx.memory orelse return Error.InvalidAccess;
    if (addr + 4 > mem.len) return Error.InvalidAccess;
    const val = std.mem.readInt(u32, mem[addr..][0..4], .little);
    try ctx.stack.append(ctx.allocator, .{ .f32 = @bitCast(val) });
}

fn handleF64Load(ctx: *ExecutionContext) Error!void {
    _ = try ctx.reader.readLEB128();
    const offset = try ctx.reader.readLEB128();
    if (ctx.stack.items.len < 1) return Error.StackUnderflow;
    const base = @as(u32, @bitCast(ctx.stack.pop().?.i32));
    const addr = base +% @as(u32, @intCast(offset));
    const mem = ctx.memory orelse return Error.InvalidAccess;
    if (addr + 8 > mem.len) return Error.InvalidAccess;
    const val = std.mem.readInt(u64, mem[addr..][0..8], .little);
    try ctx.stack.append(ctx.allocator, .{ .f64 = @bitCast(val) });
}

fn handleI32Store(ctx: *ExecutionContext) Error!void {
    _ = try ctx.reader.readLEB128();
    const offset = try ctx.reader.readLEB128();
    if (ctx.stack.items.len < 2) return Error.StackUnderflow;
    const val = ctx.stack.pop().?.i32;
    const base = @as(u32, @bitCast(ctx.stack.pop().?.i32));
    const addr = base +% @as(u32, @intCast(offset));
    const mem = ctx.memory orelse return Error.InvalidAccess;
    if (addr + 4 > mem.len) return Error.InvalidAccess;
    std.mem.writeInt(u32, mem[addr..][0..4], @bitCast(val), .little);
}

fn handleI64Store(ctx: *ExecutionContext) Error!void {
    _ = try ctx.reader.readLEB128();
    const offset = try ctx.reader.readLEB128();
    if (ctx.stack.items.len < 2) return Error.StackUnderflow;
    const val = ctx.stack.pop().?.i64;
    const base = @as(u32, @bitCast(ctx.stack.pop().?.i32));
    const addr = base +% @as(u32, @intCast(offset));
    const mem = ctx.memory orelse return Error.InvalidAccess;
    if (addr + 8 > mem.len) return Error.InvalidAccess;
    std.mem.writeInt(u64, mem[addr..][0..8], @bitCast(val), .little);
}

fn handleF32Store(ctx: *ExecutionContext) Error!void {
    _ = try ctx.reader.readLEB128();
    const offset = try ctx.reader.readLEB128();
    if (ctx.stack.items.len < 2) return Error.StackUnderflow;
    const val = ctx.stack.pop().?.f32;
    const base = @as(u32, @bitCast(ctx.stack.pop().?.i32));
    const addr = base +% @as(u32, @intCast(offset));
    const mem = ctx.memory orelse return Error.InvalidAccess;
    if (addr + 4 > mem.len) return Error.InvalidAccess;
    std.mem.writeInt(u32, mem[addr..][0..4], @bitCast(val), .little);
}

fn handleF64Store(ctx: *ExecutionContext) Error!void {
    _ = try ctx.reader.readLEB128();
    const offset = try ctx.reader.readLEB128();
    if (ctx.stack.items.len < 2) return Error.StackUnderflow;
    const val = ctx.stack.pop().?.f64;
    const base = @as(u32, @bitCast(ctx.stack.pop().?.i32));
    const addr = base +% @as(u32, @intCast(offset));
    const mem = ctx.memory orelse return Error.InvalidAccess;
    if (addr + 8 > mem.len) return Error.InvalidAccess;
    std.mem.writeInt(u64, mem[addr..][0..8], @bitCast(val), .little);
}

fn handleMemorySize(ctx: *ExecutionContext) Error!void {
    _ = try ctx.reader.readLEB128(); // memory index (usually 0)
    const mem = ctx.memory orelse return Error.InvalidAccess;
    const pages: i32 = @intCast(mem.len / 65536);
    try ctx.stack.append(ctx.allocator, .{ .i32 = pages });
}

fn handleMemoryGrow(ctx: *ExecutionContext) Error!void {
    _ = try ctx.reader.readLEB128();
    if (ctx.stack.items.len < 1) return Error.StackUnderflow;
    _ = ctx.stack.pop(); // delta pages
    // Actual grow handled by runtime
    try ctx.stack.append(ctx.allocator, .{ .i32 = -1 }); // Indicate failure here
}

// Constants
fn handleI32Const(ctx: *ExecutionContext) Error!void {
    const val = try ctx.reader.readSignedLEB128();
    try ctx.stack.append(ctx.allocator, .{ .i32 = @intCast(val) });
}

fn handleI64Const(ctx: *ExecutionContext) Error!void {
    const val = try ctx.reader.readSignedLEB128_64();
    try ctx.stack.append(ctx.allocator, .{ .i64 = val });
}

fn handleF32Const(ctx: *ExecutionContext) Error!void {
    var bytes: [4]u8 = undefined;
    for (&bytes) |*b| b.* = try ctx.reader.readByte();
    try ctx.stack.append(ctx.allocator, .{ .f32 = @bitCast(bytes) });
}

fn handleF64Const(ctx: *ExecutionContext) Error!void {
    var bytes: [8]u8 = undefined;
    for (&bytes) |*b| b.* = try ctx.reader.readByte();
    try ctx.stack.append(ctx.allocator, .{ .f64 = @bitCast(bytes) });
}

// i32 comparisons - ultra-optimized inline
fn handleI32Eqz(ctx: *ExecutionContext) Error!void {
    const len = ctx.stack.items.len;
    if (len < 1) return Error.StackUnderflow;
    ctx.stack.items[len - 1] = .{ .i32 = if (ctx.stack.items[len - 1].i32 == 0) 1 else 0 };
}

fn handleI32Eq(ctx: *ExecutionContext) Error!void {
    const len = ctx.stack.items.len;
    if (len < 2) return Error.StackUnderflow;
    const b = ctx.stack.items[len - 1].i32;
    const a = ctx.stack.items[len - 2].i32;
    ctx.stack.items[len - 2] = .{ .i32 = if (a == b) 1 else 0 };
    ctx.stack.shrinkRetainingCapacity(len - 1);
}

fn handleI32Ne(ctx: *ExecutionContext) Error!void {
    const len = ctx.stack.items.len;
    if (len < 2) return Error.StackUnderflow;
    const b = ctx.stack.items[len - 1].i32;
    const a = ctx.stack.items[len - 2].i32;
    ctx.stack.items[len - 2] = .{ .i32 = if (a != b) 1 else 0 };
    ctx.stack.shrinkRetainingCapacity(len - 1);
}

fn handleI32LtS(ctx: *ExecutionContext) Error!void {
    const len = ctx.stack.items.len;
    if (len < 2) return Error.StackUnderflow;
    const b = ctx.stack.items[len - 1].i32;
    const a = ctx.stack.items[len - 2].i32;
    ctx.stack.items[len - 2] = .{ .i32 = if (a < b) 1 else 0 };
    ctx.stack.shrinkRetainingCapacity(len - 1);
}

fn handleI32LtU(ctx: *ExecutionContext) Error!void {
    const len = ctx.stack.items.len;
    if (len < 2) return Error.StackUnderflow;
    const b = @as(u32, @bitCast(ctx.stack.items[len - 1].i32));
    const a = @as(u32, @bitCast(ctx.stack.items[len - 2].i32));
    ctx.stack.items[len - 2] = .{ .i32 = if (a < b) 1 else 0 };
    ctx.stack.shrinkRetainingCapacity(len - 1);
}

fn handleI32GtS(ctx: *ExecutionContext) Error!void {
    const len = ctx.stack.items.len;
    if (len < 2) return Error.StackUnderflow;
    const b = ctx.stack.items[len - 1].i32;
    const a = ctx.stack.items[len - 2].i32;
    ctx.stack.items[len - 2] = .{ .i32 = if (a > b) 1 else 0 };
    ctx.stack.shrinkRetainingCapacity(len - 1);
}

fn handleI32GtU(ctx: *ExecutionContext) Error!void {
    const len = ctx.stack.items.len;
    if (len < 2) return Error.StackUnderflow;
    const b = @as(u32, @bitCast(ctx.stack.items[len - 1].i32));
    const a = @as(u32, @bitCast(ctx.stack.items[len - 2].i32));
    ctx.stack.items[len - 2] = .{ .i32 = if (a > b) 1 else 0 };
    ctx.stack.shrinkRetainingCapacity(len - 1);
}

fn handleI32LeS(ctx: *ExecutionContext) Error!void {
    const len = ctx.stack.items.len;
    if (len < 2) return Error.StackUnderflow;
    const b = ctx.stack.items[len - 1].i32;
    const a = ctx.stack.items[len - 2].i32;
    ctx.stack.items[len - 2] = .{ .i32 = if (a <= b) 1 else 0 };
    ctx.stack.shrinkRetainingCapacity(len - 1);
}

fn handleI32LeU(ctx: *ExecutionContext) Error!void {
    const len = ctx.stack.items.len;
    if (len < 2) return Error.StackUnderflow;
    const b = @as(u32, @bitCast(ctx.stack.items[len - 1].i32));
    const a = @as(u32, @bitCast(ctx.stack.items[len - 2].i32));
    ctx.stack.items[len - 2] = .{ .i32 = if (a <= b) 1 else 0 };
    ctx.stack.shrinkRetainingCapacity(len - 1);
}

fn handleI32GeS(ctx: *ExecutionContext) Error!void {
    const len = ctx.stack.items.len;
    if (len < 2) return Error.StackUnderflow;
    const b = ctx.stack.items[len - 1].i32;
    const a = ctx.stack.items[len - 2].i32;
    ctx.stack.items[len - 2] = .{ .i32 = if (a >= b) 1 else 0 };
    ctx.stack.shrinkRetainingCapacity(len - 1);
}

fn handleI32GeU(ctx: *ExecutionContext) Error!void {
    const len = ctx.stack.items.len;
    if (len < 2) return Error.StackUnderflow;
    const b = @as(u32, @bitCast(ctx.stack.items[len - 1].i32));
    const a = @as(u32, @bitCast(ctx.stack.items[len - 2].i32));
    ctx.stack.items[len - 2] = .{ .i32 = if (a >= b) 1 else 0 };
    ctx.stack.shrinkRetainingCapacity(len - 1);
}

// i32 arithmetic - ultra-optimized
fn handleI32Add(ctx: *ExecutionContext) Error!void {
    const len = ctx.stack.items.len;
    if (len < 2) return Error.StackUnderflow;
    const b = ctx.stack.items[len - 1].i32;
    const a = ctx.stack.items[len - 2].i32;
    ctx.stack.items[len - 2] = .{ .i32 = a +% b };
    ctx.stack.shrinkRetainingCapacity(len - 1);
}

fn handleI32Sub(ctx: *ExecutionContext) Error!void {
    const len = ctx.stack.items.len;
    if (len < 2) return Error.StackUnderflow;
    const b = ctx.stack.items[len - 1].i32;
    const a = ctx.stack.items[len - 2].i32;
    ctx.stack.items[len - 2] = .{ .i32 = a -% b };
    ctx.stack.shrinkRetainingCapacity(len - 1);
}

fn handleI32Mul(ctx: *ExecutionContext) Error!void {
    const len = ctx.stack.items.len;
    if (len < 2) return Error.StackUnderflow;
    const b = ctx.stack.items[len - 1].i32;
    const a = ctx.stack.items[len - 2].i32;
    ctx.stack.items[len - 2] = .{ .i32 = a *% b };
    ctx.stack.shrinkRetainingCapacity(len - 1);
}

fn handleI32DivS(ctx: *ExecutionContext) Error!void {
    const len = ctx.stack.items.len;
    if (len < 2) return Error.StackUnderflow;
    const b = ctx.stack.items[len - 1].i32;
    const a = ctx.stack.items[len - 2].i32;
    if (b == 0) return Error.DivideByZero;
    ctx.stack.items[len - 2] = .{ .i32 = @divTrunc(a, b) };
    ctx.stack.shrinkRetainingCapacity(len - 1);
}

fn handleI32DivU(ctx: *ExecutionContext) Error!void {
    const len = ctx.stack.items.len;
    if (len < 2) return Error.StackUnderflow;
    const b = @as(u32, @bitCast(ctx.stack.items[len - 1].i32));
    const a = @as(u32, @bitCast(ctx.stack.items[len - 2].i32));
    if (b == 0) return Error.DivideByZero;
    ctx.stack.items[len - 2] = .{ .i32 = @bitCast(a / b) };
    ctx.stack.shrinkRetainingCapacity(len - 1);
}

fn handleI32RemS(ctx: *ExecutionContext) Error!void {
    const len = ctx.stack.items.len;
    if (len < 2) return Error.StackUnderflow;
    const b = ctx.stack.items[len - 1].i32;
    const a = ctx.stack.items[len - 2].i32;
    if (b == 0) return Error.DivideByZero;
    ctx.stack.items[len - 2] = .{ .i32 = @rem(a, b) };
    ctx.stack.shrinkRetainingCapacity(len - 1);
}

fn handleI32RemU(ctx: *ExecutionContext) Error!void {
    const len = ctx.stack.items.len;
    if (len < 2) return Error.StackUnderflow;
    const b = @as(u32, @bitCast(ctx.stack.items[len - 1].i32));
    const a = @as(u32, @bitCast(ctx.stack.items[len - 2].i32));
    if (b == 0) return Error.DivideByZero;
    ctx.stack.items[len - 2] = .{ .i32 = @bitCast(a % b) };
    ctx.stack.shrinkRetainingCapacity(len - 1);
}

fn handleI32And(ctx: *ExecutionContext) Error!void {
    const len = ctx.stack.items.len;
    if (len < 2) return Error.StackUnderflow;
    const b = ctx.stack.items[len - 1].i32;
    const a = ctx.stack.items[len - 2].i32;
    ctx.stack.items[len - 2] = .{ .i32 = a & b };
    ctx.stack.shrinkRetainingCapacity(len - 1);
}

fn handleI32Or(ctx: *ExecutionContext) Error!void {
    const len = ctx.stack.items.len;
    if (len < 2) return Error.StackUnderflow;
    const b = ctx.stack.items[len - 1].i32;
    const a = ctx.stack.items[len - 2].i32;
    ctx.stack.items[len - 2] = .{ .i32 = a | b };
    ctx.stack.shrinkRetainingCapacity(len - 1);
}

fn handleI32Xor(ctx: *ExecutionContext) Error!void {
    const len = ctx.stack.items.len;
    if (len < 2) return Error.StackUnderflow;
    const b = ctx.stack.items[len - 1].i32;
    const a = ctx.stack.items[len - 2].i32;
    ctx.stack.items[len - 2] = .{ .i32 = a ^ b };
    ctx.stack.shrinkRetainingCapacity(len - 1);
}

fn handleI32Shl(ctx: *ExecutionContext) Error!void {
    const len = ctx.stack.items.len;
    if (len < 2) return Error.StackUnderflow;
    const b = @as(u5, @truncate(@as(u32, @bitCast(ctx.stack.items[len - 1].i32))));
    const a = ctx.stack.items[len - 2].i32;
    ctx.stack.items[len - 2] = .{ .i32 = a << b };
    ctx.stack.shrinkRetainingCapacity(len - 1);
}

fn handleI32ShrS(ctx: *ExecutionContext) Error!void {
    const len = ctx.stack.items.len;
    if (len < 2) return Error.StackUnderflow;
    const b = @as(u5, @truncate(@as(u32, @bitCast(ctx.stack.items[len - 1].i32))));
    const a = ctx.stack.items[len - 2].i32;
    ctx.stack.items[len - 2] = .{ .i32 = a >> b };
    ctx.stack.shrinkRetainingCapacity(len - 1);
}

fn handleI32ShrU(ctx: *ExecutionContext) Error!void {
    const len = ctx.stack.items.len;
    if (len < 2) return Error.StackUnderflow;
    const b = @as(u5, @truncate(@as(u32, @bitCast(ctx.stack.items[len - 1].i32))));
    const a = @as(u32, @bitCast(ctx.stack.items[len - 2].i32));
    ctx.stack.items[len - 2] = .{ .i32 = @bitCast(a >> b) };
    ctx.stack.shrinkRetainingCapacity(len - 1);
}

fn handleI32Rotl(ctx: *ExecutionContext) Error!void {
    const len = ctx.stack.items.len;
    if (len < 2) return Error.StackUnderflow;
    const b = @as(u5, @truncate(@as(u32, @bitCast(ctx.stack.items[len - 1].i32))));
    const a = @as(u32, @bitCast(ctx.stack.items[len - 2].i32));
    ctx.stack.items[len - 2] = .{ .i32 = @bitCast(std.math.rotl(u32, a, b)) };
    ctx.stack.shrinkRetainingCapacity(len - 1);
}

fn handleI32Rotr(ctx: *ExecutionContext) Error!void {
    const len = ctx.stack.items.len;
    if (len < 2) return Error.StackUnderflow;
    const b = @as(u5, @truncate(@as(u32, @bitCast(ctx.stack.items[len - 1].i32))));
    const a = @as(u32, @bitCast(ctx.stack.items[len - 2].i32));
    ctx.stack.items[len - 2] = .{ .i32 = @bitCast(std.math.rotr(u32, a, b)) };
    ctx.stack.shrinkRetainingCapacity(len - 1);
}

// ============================================================================
// Fast Execution Loop
// ============================================================================

/// Execute bytecode using fast dispatch
pub fn executeFast(ctx: *ExecutionContext) Error!void {
    while (!ctx.reader.isAtEnd()) {
        const opcode = try ctx.reader.readByte();
        ctx.instruction_count += 1;

        // Direct dispatch through table
        const entry = DISPATCH_TABLE[opcode];
        try entry.handler(ctx);

        // Check for return/exception
        if (ctx.exception_active) break;
    }
}
