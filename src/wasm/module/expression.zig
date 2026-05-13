const std = @import("std");
const value = @import("../value.zig");
const Value = value.Value;
const ValueType = value.Type;

/// Represents a WebAssembly constant expression
/// Used in global initializers, element segments, and data segments
pub const Expression = @This();
    /// The operations in this expression
operations: std.ArrayList(Operation),
/// The allocator used for this expression
allocator: std.mem.Allocator,

pub const LoadInfo = struct {
    offset: u32,
    alignment: u32,
};

pub const Operation = union(enum) {
    /// i32.const value
    i32_const: i32,
    /// i64.const value
    i64_const: i64,
    /// f32.const value
    f32_const: f32,
    /// f64.const value
    f64_const: f64,
    /// v128.const value
    v128_const: [16]u8,
    /// global.get index
    global_get: u32,
    /// ref.null type
    ref_null: ValueType,
    /// ref.func index
    ref_func: u32,
    /// Memory load operations
    i32_load: LoadInfo,
    i64_load: LoadInfo,
    f32_load: LoadInfo,
    f64_load: LoadInfo,
    i32_load8_s: LoadInfo,
    i32_load8_u: LoadInfo,
    i32_load16_s: LoadInfo,
    i32_load16_u: LoadInfo,
    i64_load8_s: LoadInfo,
    i64_load8_u: LoadInfo,
    i64_load16_s: LoadInfo,
    i64_load16_u: LoadInfo,
    i64_load32_s: LoadInfo,
    i64_load32_u: LoadInfo,
    /// Table operations
    table_get: u32,
    table_size: u32,
    /// Arithmetic operations
    i32_add,
    i32_sub,
    i32_mul,
    i64_add,
    i64_sub,
    i64_mul,
};

pub fn init(allocator: std.mem.Allocator) Expression {
    return .{
        .operations = std.ArrayList(Operation).initCapacity(allocator, 0) catch unreachable,
        .allocator = allocator,
    };
}

pub fn deinit(self: *Expression) void {
    self.operations.deinit(self.allocator);
}

/// Parse a constant expression from a reader
/// Stops at the end opcode (0x0B)
pub fn parse(self: *Expression, reader: anytype) !void {
  while (true) {
        const opcode = try reader.readByte();
        if (opcode == 0x0B)
          break;
        const op = try self.parseOperation(opcode, reader);
        try self.operations.append(self.allocator, op);
    }
}

/// Evaluate this constant expression and return the result
/// The expression must evaluate to a single value on the stack
pub fn evaluate(self: *const Expression, module: anytype) !Value {
    var stack = std.ArrayList(Value).initCapacity(self.allocator, 0) catch unreachable;
    defer stack.deinit(self.allocator);
    for (self.operations.items) |op|
        try self.evaluateOperation(op, &stack, module, self.allocator);
    if (stack.items.len != 1)
        return error.InvalidConstantExpression;
    return stack.items[0];
}


fn evaluateOperation(_: *const Expression, op: Operation, stack: *std.ArrayList(Value), module: anytype, allocator: std.mem.Allocator) !void {
    switch (op) {
        .i32_const => |val| try stack.append(allocator, .{ .i32 = val }),
        .i64_const => |val| try stack.append(allocator, .{ .i64 = val }),
        .f32_const => |val| try stack.append(allocator, .{ .f32 = val }),
        .f64_const => |val| try stack.append(allocator, .{ .f64 = val }),
        .v128_const => |val| try stack.append(allocator, .{ .v128 = val }),
        .global_get => |index| {
            if (index >= module.globals.items.len)
                return error.InvalidGlobalIndex;
            try stack.append(allocator, module.globals.items[index].value);
        },
        .ref_null => |val_type| {
            _ = val_type; // For now, just push a null reference
            try stack.append(allocator, .{ .funcref = null });
        },
        .ref_func => |index| {
            if (index >= module.functions.items.len)
                return error.InvalidFunctionIndex;
            try stack.append(allocator, .{ .funcref = index });
        },
        .i32_load => |info| {
            const addr = try popI32(stack);
            const effective_addr = @as(usize, @intCast(addr)) + info.offset;
            const mem_data = module.memory orelse return error.MemoryAccessOutOfBounds;
            if (effective_addr + 4 > mem_data.len)
                return error.MemoryAccessOutOfBounds;
            const val = std.mem.readInt(i32, mem_data[effective_addr..][0..4], .little);
            try stack.append(allocator, .{ .i32 = val });
        },
        .i64_load => |info| {
            const addr = try popI32(stack);
            const effective_addr = @as(usize, @intCast(addr)) + info.offset;
            const mem_data = module.memory orelse return error.MemoryAccessOutOfBounds;
            if (effective_addr + 8 > mem_data.len)
                return error.MemoryAccessOutOfBounds;
            const val = std.mem.readInt(i64, mem_data[effective_addr..][0..8], .little);
            try stack.append(allocator, .{ .i64 = val });
        },
        .f32_load => |info| {
            const addr = try popI32(stack);
            const effective_addr = @as(usize, @intCast(addr)) + info.offset;
            const mem_data = module.memory orelse return error.MemoryAccessOutOfBounds;
            if (effective_addr + 4 > mem_data.len)
                return error.MemoryAccessOutOfBounds;
            const val = std.mem.readInt(u32, mem_data[effective_addr..][0..4], .little);
            try stack.append(allocator, .{ .f32 = @bitCast(val) });
        },
        .f64_load => |info| {
            const addr = try popI32(stack);
            const effective_addr = @as(usize, @intCast(addr)) + info.offset;
            const mem_data = module.memory orelse return error.MemoryAccessOutOfBounds;
            if (effective_addr + 8 > mem_data.len)
                return error.MemoryAccessOutOfBounds;
            const val = std.mem.readInt(u64, mem_data[effective_addr..][0..8], .little);
            try stack.append(allocator, .{ .f64 = @bitCast(val) });
        },
        .i32_load8_s => |info| {
            const addr = try popI32(stack);
            const effective_addr = @as(usize, @intCast(addr)) + info.offset;
            const mem_data = module.memory orelse return error.MemoryAccessOutOfBounds;
            if (effective_addr >= mem_data.len)
                return error.MemoryAccessOutOfBounds;
            const val = @as(i8, @bitCast(mem_data[effective_addr]));
            try stack.append(allocator, .{ .i32 = val });
        },
        .i32_load8_u => |info| {
            const addr = try popI32(stack);
            const effective_addr = @as(usize, @intCast(addr)) + info.offset;
            const mem_data = module.memory orelse return error.MemoryAccessOutOfBounds;
            if (effective_addr >= mem_data.len)
                return error.MemoryAccessOutOfBounds;
            const val = mem_data[effective_addr];
            try stack.append(allocator, .{ .i32 = val });
        },
        .i32_load16_s => |info| {
            const addr = try popI32(stack);
            const effective_addr = @as(usize, @intCast(addr)) + info.offset;
            const mem_data = module.memory orelse return error.MemoryAccessOutOfBounds;
            if (effective_addr + 2 > mem_data.len)
                return error.MemoryAccessOutOfBounds;
            const val = std.mem.readInt(i16, mem_data[effective_addr..][0..2], .little);
            try stack.append(allocator, .{ .i32 = val });
        },
        .i32_load16_u => |info| {
            const addr = try popI32(stack);
            const effective_addr = @as(usize, @intCast(addr)) + info.offset;
            const mem_data = module.memory orelse return error.MemoryAccessOutOfBounds;
            if (effective_addr + 2 > mem_data.len)
                return error.MemoryAccessOutOfBounds;
            const val = std.mem.readInt(u16, mem_data[effective_addr..][0..2], .little);
            try stack.append(allocator, .{ .i32 = val });
        },
        .i64_load8_s => |info| {
            const addr = try popI32(stack);
            const effective_addr = @as(usize, @intCast(addr)) + info.offset;
            const mem_data = module.memory orelse return error.MemoryAccessOutOfBounds;
            if (effective_addr >= mem_data.len)
                return error.MemoryAccessOutOfBounds;
            const val = @as(i8, @bitCast(mem_data[effective_addr]));
            try stack.append(allocator, .{ .i64 = val });
        },
        .i64_load8_u => |info| {
            const addr = try popI32(stack);
            const effective_addr = @as(usize, @intCast(addr)) + info.offset;
            const mem_data = module.memory orelse return error.MemoryAccessOutOfBounds;
            if (effective_addr >= mem_data.len)
                return error.MemoryAccessOutOfBounds;
            const val = mem_data[effective_addr];
            try stack.append(allocator, .{ .i64 = val });
        },
        .i64_load16_s => |info| {
            const addr = try popI32(stack);
            const effective_addr = @as(usize, @intCast(addr)) + info.offset;
            const mem_data = module.memory orelse return error.MemoryAccessOutOfBounds;
            if (effective_addr + 2 > mem_data.len)
                return error.MemoryAccessOutOfBounds;
            const val = std.mem.readInt(i16, mem_data[effective_addr..][0..2], .little);
            try stack.append(allocator, .{ .i64 = val });
        },
        .i64_load16_u => |info| {
            const addr = try popI32(stack);
            const effective_addr = @as(usize, @intCast(addr)) + info.offset;
            const mem_data = module.memory orelse return error.MemoryAccessOutOfBounds;
            if (effective_addr + 2 > mem_data.len)
                return error.MemoryAccessOutOfBounds;
            const val = std.mem.readInt(u16, mem_data[effective_addr..][0..2], .little);
            try stack.append(allocator, .{ .i64 = val });
        },
        .i64_load32_s => |info| {
            const addr = try popI32(stack);
            const effective_addr = @as(usize, @intCast(addr)) + info.offset;
            const mem_data = module.memory orelse return error.MemoryAccessOutOfBounds;
            if (effective_addr + 4 > mem_data.len)
                return error.MemoryAccessOutOfBounds;
            const val = std.mem.readInt(i32, mem_data[effective_addr..][0..4], .little);
            try stack.append(allocator, .{ .i64 = val });
        },
        .i64_load32_u => |info| {
            const addr = try popI32(stack);
            const effective_addr = @as(usize, @intCast(addr)) + info.offset;
            const mem_data = module.memory orelse return error.MemoryAccessOutOfBounds;
            if (effective_addr + 4 > mem_data.len)
                return error.MemoryAccessOutOfBounds;
            const val = std.mem.readInt(u32, mem_data[effective_addr..][0..4], .little);
            try stack.append(allocator, .{ .i64 = val });
        },
        .table_get => |table_index| {
            const elem_index = try popI32(stack);
            // For now, assume table 0 and return a placeholder
            _ = table_index;
            _ = elem_index;
            try stack.append(allocator, .{ .funcref = null });
        },
        .table_size => |table_index| {
            // For now, return 0 as table size
            _ = table_index;
            try stack.append(allocator, .{ .i32 = 0 });
        },
        .i32_add => {
            const b = try popI32(stack);
            const a = try popI32(stack);
            try stack.append(allocator, .{ .i32 = a + b });
        },
        .i32_sub => {
            const b = try popI32(stack);
            const a = try popI32(stack);
            try stack.append(allocator, .{ .i32 = a - b });
        },
        .i32_mul => {
            const b = try popI32(stack);
            const a = try popI32(stack);
            try stack.append(allocator, .{ .i32 = a * b });
        },
        .i64_add => {
            const b = try popI64(stack);
            const a = try popI64(stack);
            try stack.append(allocator, .{ .i64 = a + b });
        },
        .i64_sub => {
            const b = try popI64(stack);
            const a = try popI64(stack);
            try stack.append(allocator, .{ .i64 = a - b });
        },
        .i64_mul => {
            const b = try popI64(stack);
            const a = try popI64(stack);
            try stack.append(allocator, .{ .i64 = a * b });
        },
    }
}

fn popI32(stack: *std.ArrayList(Value)) anyerror!i32 {
    // return if (stack.items.len == 0) .StackUnderflow;
    const val = stack.pop() orelse return error.StackUnderflow;
    return switch (val) {
        .i32 => |v| v,
        else => error.TypeMismatch,
    };
}

fn popI64(stack: *std.ArrayList(Value)) !i64 {
    if (stack.items.len == 0) return error.StackUnderflow;
    const val = stack.pop() orelse return error.StackUnderflow;
    return switch (val) {
        .i64 => |v| v,
        else => error.TypeMismatch,
    };
}

inline fn parseOperation(self: *Expression, opcode: u8, reader: anytype) !Operation {
    _ = self; // unused for now
    return switch (opcode) {
        0x41 => blk: { // i32.const
            const val = try reader.readLEB128();
            break :blk .{ .i32_const = @intCast(val) };
        },
        0x42 => blk: { // i64.const
            const val = try reader.readLEB128();
            break :blk .{ .i64_const = @intCast(val) };
        },
        0x43 => blk: { // f32.const
            const float_bytes = try reader.readBytes(4);
            const val = @as(f32, @bitCast(std.mem.readInt(u32, float_bytes[0..4], .little)));
            break :blk .{ .f32_const = val };
        },
        0x44 => blk: { // f64.const
            const double_bytes = try reader.readBytes(8);
            const val = @as(f64, @bitCast(std.mem.readInt(u64, double_bytes[0..8], .little)));
            break :blk .{ .f64_const = val };
        },
        0xFD => blk: { // v128.const (0xFD 0x0C)
            const sub_op = try reader.readLEB128();
            if (sub_op != 0x0C) return error.InvalidOpcode;
            const bytes = try reader.readBytes(16);
            var v: [16]u8 = undefined;
            @memcpy(&v, bytes[0..16]);
            break :blk .{ .v128_const = v };
        },
        0x23 => blk: { // global.get
            const index = try reader.readLEB128();
            break :blk .{ .global_get = @intCast(index) };
        },
        0xD0 => blk: { // ref.null
            const type_byte = try reader.readByte();
            const val_type = try ValueType.fromByte(type_byte);
            break :blk .{ .ref_null = val_type };
        },
        0xD2 => blk: { // ref.func
            const index = try reader.readLEB128();
            break :blk .{ .ref_func = @intCast(index) };
        },
        0x28 => blk: { // i32.load
            const alignment = try reader.readLEB128();
            const offset = try reader.readLEB128();
            break :blk .{ .i32_load = .{ .offset = @intCast(offset), .alignment = @intCast(alignment) } };
        },
        0x29 => blk: { // i64.load
            const alignment = try reader.readLEB128();
            const offset = try reader.readLEB128();
            break :blk .{ .i64_load = .{ .offset = @intCast(offset), .alignment = @intCast(alignment) } };
        },
        0x2A => blk: { // f32.load
            const alignment = try reader.readLEB128();
            const offset = try reader.readLEB128();
            break :blk .{ .f32_load = .{ .offset = @intCast(offset), .alignment = @intCast(alignment) } };
        },
        0x2B => blk: { // f64.load
            const alignment = try reader.readLEB128();
            const offset = try reader.readLEB128();
            break :blk .{ .f64_load = .{ .offset = @intCast(offset), .alignment = @intCast(alignment) } };
        },
        0x2C => blk: { // i32.load8_s
            const alignment = try reader.readLEB128();
            const offset = try reader.readLEB128();
            break :blk .{ .i32_load8_s = .{ .offset = @intCast(offset), .alignment = @intCast(alignment) } };
        },
        0x2D => blk: { // i32.load8_u
            const alignment = try reader.readLEB128();
            const offset = try reader.readLEB128();
            break :blk .{ .i32_load8_u = .{ .offset = @intCast(offset), .alignment = @intCast(alignment) } };
        },
        0x2E => blk: { // i32.load16_s
            const alignment = try reader.readLEB128();
            const offset = try reader.readLEB128();
            break :blk .{ .i32_load16_s = .{ .offset = @intCast(offset), .alignment = @intCast(alignment) } };
        },
        0x2F => blk: { // i32.load16_u
            const alignment = try reader.readLEB128();
            const offset = try reader.readLEB128();
            break :blk .{ .i32_load16_u = .{ .offset = @intCast(offset), .alignment = @intCast(alignment) } };
        },
        0x30 => blk: { // i64.load8_s
            const alignment = try reader.readLEB128();
            const offset = try reader.readLEB128();
            break :blk .{ .i64_load8_s = .{ .offset = @intCast(offset), .alignment = @intCast(alignment) } };
        },
        0x31 => blk: { // i64.load8_u
            const alignment = try reader.readLEB128();
            const offset = try reader.readLEB128();
            break :blk .{ .i64_load8_u = .{ .offset = @intCast(offset), .alignment = @intCast(alignment) } };
        },
        0x32 => blk: { // i64.load16_s
            const alignment = try reader.readLEB128();
            const offset = try reader.readLEB128();
            break :blk .{ .i64_load16_s = .{ .offset = @intCast(offset), .alignment = @intCast(alignment) } };
        },
        0x33 => blk: { // i64.load16_u
            const alignment = try reader.readLEB128();
            const offset = try reader.readLEB128();
            break :blk .{ .i64_load16_u = .{ .offset = @intCast(offset), .alignment = @intCast(alignment) } };
        },
        0x34 => blk: { // i64.load32_s
            const alignment = try reader.readLEB128();
            const offset = try reader.readLEB128();
            break :blk .{ .i64_load32_s = .{ .offset = @intCast(offset), .alignment = @intCast(alignment) } };
        },
        0x35 => blk: { // i64.load32_u
            const alignment = try reader.readLEB128();
            const offset = try reader.readLEB128();
            break :blk .{ .i64_load32_u = .{ .offset = @intCast(offset), .alignment = @intCast(alignment) } };
        },
        0x25 => blk: { // table.get
            const table_index = try reader.readLEB128();
            break :blk .{ .table_get = @intCast(table_index) };
        },
        0xFC => blk: { // table.size (0xFC 0x10)
            const sub_op = try reader.readLEB128();
            if (sub_op != 0x10) return error.InvalidOpcode;
            const table_index = try reader.readLEB128();
            break :blk .{ .table_size = @intCast(table_index) };
        },
        0x6A => .i32_add, // i32.add
        0x7C => .i64_add, // i64.add
        0x6B => .i32_sub, // i32.sub
        0x7D => .i64_sub, // i64.sub
        0x6C => .i32_mul, // i32.mul
        0x7E => .i64_mul, // i64.mul
        else => return error.InvalidOpcode,
    };


}
