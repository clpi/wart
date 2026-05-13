const std = @import("std");
const Value = @import("value.zig").Value;
const ComponentTypes = @import("component_types.zig");
const ComponentValType = ComponentTypes.ComponentValType;
const CanonicalOptions = ComponentTypes.CanonicalOptions;

/// Canonical ABI implementation for Component Model
/// Based on the Canonical ABI specification
pub const CanonicalABI = struct {
    allocator: std.mem.Allocator,
    memory: ?[]u8 = null,
    realloc_func: ?u32 = null,
    string_encoding: CanonicalOptions.StringEncoding = .utf8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
        };
    }

    /// Lower a component value to core WebAssembly values
    pub fn lower(self: *Self, value: ComponentValue, typ: *const ComponentValType) ![]Value {
        return switch (typ.*) {
            .bool => &[_]Value{Value{ .i32 = if (value.bool) 1 else 0 }},
            .s8, .u8 => &[_]Value{Value{ .i32 = value.i32 }},
            .s16, .u16 => &[_]Value{Value{ .i32 = value.i32 }},
            .s32, .u32 => &[_]Value{Value{ .i32 = value.i32 }},
            .s64, .u64 => &[_]Value{Value{ .i64 = value.i64 }},
            .f32 => &[_]Value{Value{ .f32 = value.f32 }},
            .f64 => &[_]Value{Value{ .f64 = value.f64 }},
            .char => &[_]Value{Value{ .i32 = value.i32 }},

            .string => try self.lowerString(value.string),
            .list => try self.lowerList(value.list, typ.list),
            .record => try self.lowerRecord(value.record, typ.record),
            .variant => try self.lowerVariant(value.variant, typ.variant),
            .option => try self.lowerOption(value.option, typ.option),
            .result => try self.lowerResult(value.result, typ.result),

            .own, .borrow => &[_]Value{Value{ .i32 = value.handle }},

            else => error.UnsupportedType,
        };
    }

    /// Lift core WebAssembly values to a component value
    pub fn lift(self: *Self, values: []const Value, typ: *const ComponentValType) !ComponentValue {
        return switch (typ.*) {
            .bool => ComponentValue{ .bool = values[0].i32 != 0 },
            .s8, .s16, .s32 => ComponentValue{ .i32 = values[0].i32 },
            .u8, .u16, .u32 => ComponentValue{ .i32 = values[0].i32 },
            .s64, .u64 => ComponentValue{ .i64 = values[0].i64 },
            .f32 => ComponentValue{ .f32 = values[0].f32 },
            .f64 => ComponentValue{ .f64 = values[0].f64 },
            .char => ComponentValue{ .i32 = values[0].i32 },

            .string => ComponentValue{ .string = try self.liftString(values) },
            .list => ComponentValue{ .list = try self.liftList(values, typ.list) },
            .record => ComponentValue{ .record = try self.liftRecord(values, typ.record) },
            .variant => ComponentValue{ .variant = try self.liftVariant(values, typ.variant) },
            .option => ComponentValue{ .option = try self.liftOption(values, typ.option) },
            .result => ComponentValue{ .result = try self.liftResult(values, typ.result) },

            .own, .borrow => ComponentValue{ .handle = @intCast(values[0].i32) },

            else => error.UnsupportedType,
        };
    }

    // String lowering/lifting

    fn lowerString(self: *Self, str: []const u8) ![]Value {
        if (self.memory == null) {
            return error.NoMemoryConfigured;
        }

        // For now, return pointer and length
        // In a full implementation, we would allocate memory using realloc
        const ptr = @intFromPtr(str.ptr);
        const len = str.len;

        return &[_]Value{
            Value{ .i32 = @intCast(ptr) },
            Value{ .i32 = @intCast(len) },
        };
    }

    fn liftString(self: *Self, values: []const Value) ![]const u8 {
        if (values.len < 2) return error.InvalidStringRepresentation;

        const ptr: usize = @intCast(values[0].i32);
        const len: usize = @intCast(values[1].i32);

        if (self.memory) |mem| {
            if (ptr + len > mem.len) return error.OutOfBounds;
            return mem[ptr .. ptr + len];
        }

        return error.NoMemoryConfigured;
    }

    // List lowering/lifting

    fn lowerList(self: *Self, list: []const ComponentValue, element_type: *const ComponentValType) ![]Value {
        _ = self;
        _ = list;
        _ = element_type;
        // Simplified: return pointer and length
        return &[_]Value{
            Value{ .i32 = 0 },
            Value{ .i32 = 0 },
        };
    }

    fn liftList(self: *Self, values: []const Value, element_type: *const ComponentValType) ![]const ComponentValue {
        _ = self;
        _ = values;
        _ = element_type;
        // Simplified: return empty list
        return &[_]ComponentValue{};
    }

    // Record lowering/lifting

    fn lowerRecord(self: *Self, record: []const ComponentValue, fields: []const ComponentValType.Field) ![]Value {
        _ = self;
        _ = record;
        _ = fields;
        // Simplified implementation
        return &[_]Value{};
    }

    fn liftRecord(self: *Self, values: []const Value, fields: []const ComponentValType.Field) ![]const ComponentValue {
        _ = self;
        _ = values;
        _ = fields;
        return &[_]ComponentValue{};
    }

    // Variant lowering/lifting

    fn lowerVariant(self: *Self, variant: Variant, cases: []const ComponentValType.Case) ![]Value {
        _ = self;
        _ = variant;
        _ = cases;
        return &[_]Value{};
    }

    fn liftVariant(self: *Self, values: []const Value, cases: []const ComponentValType.Case) !Variant {
        _ = self;
        _ = values;
        _ = cases;
        return Variant{ .tag = 0, .value = null };
    }

    // Option lowering/lifting

    fn lowerOption(self: *Self, option: ?*const ComponentValue, inner_type: *const ComponentValType) ![]Value {
        if (option) |val| {
            const result = try self.lower(val.*, inner_type);
            // Prepend discriminant
            const with_discriminant = try self.allocator.alloc(Value, result.len + 1);
            with_discriminant[0] = Value{ .i32 = 1 }; // Some
            @memcpy(with_discriminant[1..], result);
            return with_discriminant;
        } else {
            return &[_]Value{Value{ .i32 = 0 }}; // None
        }
    }

    fn liftOption(self: *Self, values: []const Value, inner_type: *const ComponentValType) !?*ComponentValue {
        if (values.len < 1) return error.InvalidOption;

        const discriminant = values[0].i32;
        if (discriminant == 0) {
            return null;
        } else {
            const inner = try self.allocator.create(ComponentValue);
            inner.* = try self.lift(values[1..], inner_type);
            return inner;
        }
    }

    // Result lowering/lifting

    fn lowerResult(self: *Self, result: Result, result_type: ComponentValType.Result) ![]Value {
        _ = self;
        _ = result;
        _ = result_type;
        return &[_]Value{Value{ .i32 = 0 }};
    }

    fn liftResult(self: *Self, values: []const Value, result_type: ComponentValType.Result) !Result {
        _ = self;
        _ = values;
        _ = result_type;
        return Result{ .is_ok = true, .value = null };
    }
};

/// Component value representation
pub const ComponentValue = union(enum) {
    bool: bool,
    i32: i32,
    i64: i64,
    f32: f32,
    f64: f64,
    string: []const u8,
    list: []const ComponentValue,
    record: []const ComponentValue,
    variant: Variant,
    option: ?*const ComponentValue,
    result: Result,
    handle: u32,
};

pub const Variant = struct {
    tag: u32,
    value: ?*const ComponentValue,
};

pub const Result = struct {
    is_ok: bool,
    value: ?*const ComponentValue,
};
