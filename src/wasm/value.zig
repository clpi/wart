const std = @import("std");
const Color = @import("../util/fmt/color.zig");
const Log = @import("../util/fmt.zig").Log;
const print = @import("../util/fmt.zig").print;

/// Re-export std.wasm.Valtype for MVP types
pub const StdValtype = std.wasm.Valtype;

pub const Error = error{
    InvalidType,
};

/// Value types including MVP types from std.wasm.Valtype plus GC proposal types.
/// MVP types match std.wasm.Valtype exactly for interoperability.
pub const Type = enum(u8) {
    // MVP types - same values as std.wasm.Valtype
    i32 = @intFromEnum(StdValtype.i32), // 0x7F
    i64 = @intFromEnum(StdValtype.i64), // 0x7E
    f32 = @intFromEnum(StdValtype.f32), // 0x7D
    f64 = @intFromEnum(StdValtype.f64), // 0x7C
    v128 = @intFromEnum(StdValtype.v128), // 0x7B
    // Reference types
    funcref = 0x70,
    externref = 0x6F,
    // GC proposal types
    anyref = 0x6E,
    eqref = 0x6D,
    i31ref = 0x6C,
    structref = 0x6B,
    arrayref = 0x6A,
    nullref = 0x69,
    // Block type marker
    block = 0x40,

    /// Convert from std.wasm.Valtype
    pub fn fromStdValtype(valtype: StdValtype) Type {
        return @enumFromInt(@intFromEnum(valtype));
    }

    /// Convert to std.wasm.Valtype (only for MVP numeric types)
    pub fn toStdValtype(self: Type) ?StdValtype {
        return switch (self) {
            .i32, .i64, .f32, .f64, .v128 => @enumFromInt(@intFromEnum(self)),
            else => null,
        };
    }

    /// Parse type byte - supports both MVP and extended types
    pub fn fromByte(byte: u8) Error!Type {
        const o = Log.op("Type", "fromByte");
        const e = Log.err("Type", "fromByte");
        o.log("Parsing type byte: 0x{X:0>2}", .{byte});

        // First try std.wasm.Valtype for MVP types
        if (std.enums.fromInt(StdValtype, byte)) |valtype| {
            return fromStdValtype(valtype);
        }

        // Extended types not in std.wasm.Valtype
        return switch (byte) {
            0x70 => .funcref,
            0x6F => .externref,
            0x6E => .anyref,
            0x6D => .eqref,
            0x6C => .i31ref,
            0x6B => .structref,
            0x6A => .arrayref,
            0x69 => .nullref,
            0x40 => .block,
            else => {
                e.log("Invalid type byte: 0x{X:0>2}", .{byte});
                return Error.InvalidType;
            },
        };
    }

    /// Check if this is a numeric type
    pub fn isNumeric(self: Type) bool {
        return switch (self) {
            .i32, .i64, .f32, .f64 => true,
            else => false,
        };
    }

    /// Check if this is a reference type
    pub fn isRef(self: Type) bool {
        return switch (self) {
            .funcref, .externref, .anyref, .eqref, .i31ref, .structref, .arrayref, .nullref => true,
            else => false,
        };
    }

    /// Check if this is a vector type
    pub fn isVector(self: Type) bool {
        return self == .v128;
    }
};

pub const GCRef = struct {
    index: u32,
    generation: u32,

    pub fn null_ref() GCRef {
        return .{ .index = 0xFFFFFFFF, .generation = 0 };
    }

    pub fn is_null(self: GCRef) bool {
        return self.index == 0xFFFFFFFF;
    }
};

pub const Value = union(Type) {
    i32: i32,
    i64: i64,
    f32: f32,
    f64: f64,
    v128: [16]u8,
    funcref: ?usize,
    externref: ?*anyopaque,
    anyref: GCRef,
    eqref: GCRef,
    i31ref: i32,
    structref: GCRef,
    arrayref: GCRef,
    nullref: void,
    block: void,
};
