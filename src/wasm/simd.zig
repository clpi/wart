const std = @import("std");
const Value = @import("value.zig").Value;

/// SIMD helper functions for v128 operations
/// Helper to interpret v128 as 16x i8
pub inline fn asI8x16(v: [16]u8) [16]i8 {
    var result: [16]i8 = undefined;
    for (v, 0..) |byte, i| {
        result[i] = @bitCast(byte);
    }
    return result;
}

/// Helper to interpret v128 as 8x i16
pub inline fn asI16x8(v: [16]u8) [8]i16 {
    var result: [8]i16 = undefined;
    for (0..8) |i| {
        const idx = i * 2;
        result[i] = @bitCast(@as(u16, v[idx]) | (@as(u16, v[idx + 1]) << 8));
    }
    return result;
}

/// Helper to interpret v128 as 4x i32
pub inline fn asI32x4(v: [16]u8) [4]i32 {
    var result: [4]i32 = undefined;
    for (0..4) |i| {
        const idx = i * 4;
        result[i] = @bitCast(@as(u32, v[idx]) |
            (@as(u32, v[idx + 1]) << 8) |
            (@as(u32, v[idx + 2]) << 16) |
            (@as(u32, v[idx + 3]) << 24));
    }
    return result;
}

/// Helper to interpret v128 as 2x i64
pub inline fn asI64x2(v: [16]u8) [2]i64 {
    var result: [2]i64 = undefined;
    for (0..2) |i| {
        const idx = i * 8;
        result[i] = @bitCast(@as(u64, v[idx]) |
            (@as(u64, v[idx + 1]) << 8) |
            (@as(u64, v[idx + 2]) << 16) |
            (@as(u64, v[idx + 3]) << 24) |
            (@as(u64, v[idx + 4]) << 32) |
            (@as(u64, v[idx + 5]) << 40) |
            (@as(u64, v[idx + 6]) << 48) |
            (@as(u64, v[idx + 7]) << 56));
    }
    return result;
}

/// Helper to interpret v128 as 4x f32
pub inline fn asF32x4(v: [16]u8) [4]f32 {
    const i32s = asI32x4(v);
    var result: [4]f32 = undefined;
    for (i32s, 0..) |val, i| {
        result[i] = @bitCast(val);
    }
    return result;
}

/// Helper to interpret v128 as 2x f64
pub inline fn asF64x2(v: [16]u8) [2]f64 {
    const i64s = asI64x2(v);
    var result: [2]f64 = undefined;
    for (i64s, 0..) |val, i| {
        result[i] = @bitCast(val);
    }
    return result;
}

/// Convert i8x16 back to v128
pub inline fn fromI8x16(v: [16]i8) [16]u8 {
    var result: [16]u8 = undefined;
    for (v, 0..) |val, i| {
        result[i] = @bitCast(val);
    }
    return result;
}

/// Convert i16x8 back to v128
pub inline fn fromI16x8(v: [8]i16) [16]u8 {
    var result: [16]u8 = undefined;
    for (v, 0..) |val, i| {
        const u_val: u16 = @bitCast(val);
        const idx = i * 2;
        result[idx] = @truncate(u_val);
        result[idx + 1] = @truncate(u_val >> 8);
    }
    return result;
}

/// Convert i32x4 back to v128
pub inline fn fromI32x4(v: [4]i32) [16]u8 {
    var result: [16]u8 = undefined;
    for (v, 0..) |val, i| {
        const u_val: u32 = @bitCast(val);
        const idx = i * 4;
        result[idx] = @truncate(u_val);
        result[idx + 1] = @truncate(u_val >> 8);
        result[idx + 2] = @truncate(u_val >> 16);
        result[idx + 3] = @truncate(u_val >> 24);
    }
    return result;
}

/// Convert i64x2 back to v128
pub inline fn fromI64x2(v: [2]i64) [16]u8 {
    var result: [16]u8 = undefined;
    for (v, 0..) |val, i| {
        const u_val: u64 = @bitCast(val);
        const idx = i * 8;
        result[idx] = @truncate(u_val);
        result[idx + 1] = @truncate(u_val >> 8);
        result[idx + 2] = @truncate(u_val >> 16);
        result[idx + 3] = @truncate(u_val >> 24);
        result[idx + 4] = @truncate(u_val >> 32);
        result[idx + 5] = @truncate(u_val >> 40);
        result[idx + 6] = @truncate(u_val >> 48);
        result[idx + 7] = @truncate(u_val >> 56);
    }
    return result;
}

/// Convert f32x4 back to v128
pub inline fn fromF32x4(v: [4]f32) [16]u8 {
    var i32s: [4]i32 = undefined;
    for (v, 0..) |val, i| {
        i32s[i] = @bitCast(val);
    }
    return fromI32x4(i32s);
}

/// Convert f64x2 back to v128
pub inline fn fromF64x2(v: [2]f64) [16]u8 {
    var i64s: [2]i64 = undefined;
    for (v, 0..) |val, i| {
        i64s[i] = @bitCast(val);
    }
    return fromI64x2(i64s);
}

/// Saturating addition for i8
pub inline fn addSatI8(a: i8, b: i8) i8 {
    const result = @as(i16, a) + @as(i16, b);
    if (result > 127) return 127;
    if (result < -128) return -128;
    return @intCast(result);
}

/// Saturating addition for u8
pub inline fn addSatU8(a: u8, b: u8) u8 {
    const result = @as(u16, a) + @as(u16, b);
    if (result > 255) return 255;
    return @intCast(result);
}

/// Saturating subtraction for i8
pub inline fn subSatI8(a: i8, b: i8) i8 {
    const result = @as(i16, a) - @as(i16, b);
    if (result > 127) return 127;
    if (result < -128) return -128;
    return @intCast(result);
}

/// Saturating subtraction for u8
pub inline fn subSatU8(a: u8, b: u8) u8 {
    if (a < b) return 0;
    return a - b;
}

/// Saturating addition for i16
pub inline fn addSatI16(a: i16, b: i16) i16 {
    const result = @as(i32, a) + @as(i32, b);
    if (result > 32767) return 32767;
    if (result < -32768) return -32768;
    return @intCast(result);
}

/// Saturating addition for u16
pub inline fn addSatU16(a: u16, b: u16) u16 {
    const result = @as(u32, a) + @as(u32, b);
    if (result > 65535) return 65535;
    return @intCast(result);
}

/// Saturating subtraction for i16
pub inline fn subSatI16(a: i16, b: i16) i16 {
    const result = @as(i32, a) - @as(i32, b);
    if (result > 32767) return 32767;
    if (result < -32768) return -32768;
    return @intCast(result);
}

/// Saturating subtraction for u16
pub inline fn subSatU16(a: u16, b: u16) u16 {
    if (a < b) return 0;
    return a - b;
}

/// Average rounding up for u8
pub inline fn avgrU8(a: u8, b: u8) u8 {
    return @intCast((@as(u16, a) + @as(u16, b) + 1) >> 1);
}

/// Average rounding up for u16
pub inline fn avgrU16(a: u16, b: u16) u16 {
    return @intCast((@as(u32, a) + @as(u32, b) + 1) >> 1);
}
