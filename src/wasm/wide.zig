/// Wide Arithmetic Operations (128-bit)
/// Provides i128 and u128 support for WebAssembly
const std = @import("std");
const Value = @import("value.zig").Value;

/// 128-bit unsigned integer
pub const u128 = u128;

/// 128-bit signed integer
pub const i128 = i128;

/// Wide value representation for stack operations
pub const WideValue = union(enum) {
    u128: u128,
    i128: i128,

    /// Convert to low/high 64-bit pairs
    pub fn toLowHigh(self: WideValue) struct { low: u64, high: u64 } {
        const bits: u128 = switch (self) {
            .u128 => |v| v,
            .i128 => |v| @bitCast(v),
        };
        return .{
            .low = @truncate(bits),
            .high = @truncate(bits >> 64),
        };
    }

    /// Create from low/high 64-bit pairs
    pub fn fromLowHigh(low: u64, high: u64, signed: bool) WideValue {
        const value = (@as(u128, high) << 64) | @as(u128, low);
        if (signed) {
            return .{ .i128 = @bitCast(value) };
        } else {
            return .{ .u128 = value };
        }
    }
};

/// 128-bit arithmetic operations
pub const WideArithmetic = struct {
    /// Add two u128 values
    pub fn addU128(a: u128, b: u128) struct { result: u128, overflow: bool } {
        const result, const overflow = @addWithOverflow(a, b);
        return .{ .result = result, .overflow = overflow == 1 };
    }

    /// Add two i128 values
    pub fn addI128(a: i128, b: i128) struct { result: i128, overflow: bool } {
        const result, const overflow = @addWithOverflow(a, b);
        return .{ .result = result, .overflow = overflow == 1 };
    }

    /// Subtract u128 values
    pub fn subU128(a: u128, b: u128) struct { result: u128, overflow: bool } {
        const result, const overflow = @subWithOverflow(a, b);
        return .{ .result = result, .overflow = overflow == 1 };
    }

    /// Subtract i128 values
    pub fn subI128(a: i128, b: i128) struct { result: i128, overflow: bool } {
        const result, const overflow = @subWithOverflow(a, b);
        return .{ .result = result, .overflow = overflow == 1 };
    }

    /// Multiply u128 values (returns low 128 bits)
    pub fn mulU128(a: u128, b: u128) u128 {
        return a *% b;
    }

    /// Multiply i128 values (returns low 128 bits)
    pub fn mulI128(a: i128, b: i128) i128 {
        return a *% b;
    }

    /// Multiply u128 values with full 256-bit result
    pub fn mulWideU128(a: u128, b: u128) struct { low: u128, high: u128 } {
        // Split into 64-bit parts
        const a_low = @as(u64, @truncate(a));
        const a_high = @as(u64, @truncate(a >> 64));
        const b_low = @as(u64, @truncate(b));
        const b_high = @as(u64, @truncate(b >> 64));

        // Perform 64-bit multiplications
        const ll = @as(u128, a_low) * @as(u128, b_low);
        const lh = @as(u128, a_low) * @as(u128, b_high);
        const hl = @as(u128, a_high) * @as(u128, b_low);
        const hh = @as(u128, a_high) * @as(u128, b_high);

        // Combine results
        const middle1 = lh + @as(u128, @truncate(ll >> 64));
        const middle2 = hl + @as(u128, @truncate(middle1));
        const low = (middle2 << 64) | @as(u128, @truncate(ll));
        const high = hh + @as(u128, @truncate(middle1 >> 64)) + @as(u128, @truncate(middle2 >> 64));

        return .{ .low = low, .high = high };
    }

    /// Divide u128 values
    pub fn divU128(a: u128, b: u128) !u128 {
        if (b == 0) return error.DivisionByZero;
        return a / b;
    }

    /// Divide i128 values
    pub fn divI128(a: i128, b: i128) !i128 {
        if (b == 0) return error.DivisionByZero;
        if (a == std.math.minInt(i128) and b == -1) return error.Overflow;
        return @divTrunc(a, b);
    }

    /// Remainder u128 values
    pub fn remU128(a: u128, b: u128) !u128 {
        if (b == 0) return error.DivisionByZero;
        return a % b;
    }

    /// Remainder i128 values
    pub fn remI128(a: i128, b: i128) !i128 {
        if (b == 0) return error.DivisionByZero;
        return @rem(a, b);
    }

    /// Bitwise AND
    pub fn andU128(a: u128, b: u128) u128 {
        return a & b;
    }

    /// Bitwise OR
    pub fn orU128(a: u128, b: u128) u128 {
        return a | b;
    }

    /// Bitwise XOR
    pub fn xorU128(a: u128, b: u128) u128 {
        return a ^ b;
    }

    /// Bitwise NOT
    pub fn notU128(a: u128) u128 {
        return ~a;
    }

    /// Shift left
    pub fn shlU128(a: u128, shift: u7) u128 {
        if (shift >= 128) return 0;
        return a << shift;
    }

    /// Shift right (logical)
    pub fn shrU128(a: u128, shift: u7) u128 {
        if (shift >= 128) return 0;
        return a >> shift;
    }

    /// Shift right (arithmetic)
    pub fn shrI128(a: i128, shift: u7) i128 {
        if (shift >= 128) {
            return if (a < 0) -1 else 0;
        }
        return a >> shift;
    }

    /// Rotate left
    pub fn rotlU128(a: u128, shift: u7) u128 {
        const s = @as(u7, @intCast(shift % 128));
        return (a << s) | (a >> (128 - s));
    }

    /// Rotate right
    pub fn rotrU128(a: u128, shift: u7) u128 {
        const s = @as(u7, @intCast(shift % 128));
        return (a >> s) | (a << (128 - s));
    }

    /// Count leading zeros
    pub fn clzU128(a: u128) u8 {
        return @clz(a);
    }

    /// Count trailing zeros
    pub fn ctzU128(a: u128) u8 {
        return @ctz(a);
    }

    /// Population count (number of 1 bits)
    pub fn popcntU128(a: u128) u8 {
        return @popCount(a);
    }

    /// Compare equal
    pub fn eqU128(a: u128, b: u128) bool {
        return a == b;
    }

    /// Compare not equal
    pub fn neU128(a: u128, b: u128) bool {
        return a != b;
    }

    /// Compare less than (unsigned)
    pub fn ltU128(a: u128, b: u128) bool {
        return a < b;
    }

    /// Compare less than (signed)
    pub fn ltI128(a: i128, b: i128) bool {
        return a < b;
    }

    /// Compare less than or equal (unsigned)
    pub fn leU128(a: u128, b: u128) bool {
        return a <= b;
    }

    /// Compare less than or equal (signed)
    pub fn leI128(a: i128, b: i128) bool {
        return a <= b;
    }

    /// Compare greater than (unsigned)
    pub fn gtU128(a: u128, b: u128) bool {
        return a > b;
    }

    /// Compare greater than (signed)
    pub fn gtI128(a: i128, b: i128) bool {
        return a > b;
    }

    /// Compare greater than or equal (unsigned)
    pub fn geU128(a: u128, b: u128) bool {
        return a >= b;
    }

    /// Compare greater than or equal (signed)
    pub fn geI128(a: i128, b: i128) bool {
        return a >= b;
    }

    /// Extend i64 to i128
    pub fn extendI64(a: i64) i128 {
        return @as(i128, a);
    }

    /// Extend u64 to u128
    pub fn extendU64(a: u64) u128 {
        return @as(u128, a);
    }

    /// Truncate u128 to u64
    pub fn truncateU128ToU64(a: u128) u64 {
        return @truncate(a);
    }

    /// Truncate i128 to i64
    pub fn truncateI128ToI64(a: i128) i64 {
        return @truncate(a);
    }

    /// Convert i128 to f64 (with potential precision loss)
    pub fn i128ToF64(a: i128) f64 {
        return @floatFromInt(a);
    }

    /// Convert u128 to f64 (with potential precision loss)
    pub fn u128ToF64(a: u128) f64 {
        return @floatFromInt(a);
    }

    /// Convert f64 to i128 (truncating)
    pub fn f64ToI128(a: f64) !i128 {
        if (std.math.isNan(a) or std.math.isInf(a)) return error.InvalidConversion;
        return @intFromFloat(a);
    }

    /// Convert f64 to u128 (truncating)
    pub fn f64ToU128(a: f64) !u128 {
        if (std.math.isNan(a) or std.math.isInf(a) or a < 0) return error.InvalidConversion;
        return @intFromFloat(a);
    }
};

/// Load 128-bit value from memory
pub fn load128(memory: []const u8, addr: u32) !u128 {
    if (addr + 16 > memory.len) return error.OutOfBounds;

    const low = std.mem.readInt(u64, memory[addr..][0..8], .little);
    const high = std.mem.readInt(u64, memory[addr + 8 ..][0..8], .little);

    return (@as(u128, high) << 64) | @as(u128, low);
}

/// Store 128-bit value to memory
pub fn store128(memory: []u8, addr: u32, value: u128) !void {
    if (addr + 16 > memory.len) return error.OutOfBounds;

    const low: u64 = @truncate(value);
    const high: u64 = @truncate(value >> 64);

    std.mem.writeInt(u64, memory[addr..][0..8], low, .little);
    std.mem.writeInt(u64, memory[addr + 8 ..][0..8], high, .little);
}

/// Convert between different representations
pub const WideConvert = struct {
    /// Split u128 into two u64 values (low, high)
    pub fn splitU128(value: u128) struct { low: u64, high: u64 } {
        return .{
            .low = @truncate(value),
            .high = @truncate(value >> 64),
        };
    }

    /// Combine two u64 values into u128
    pub fn combineU64(low: u64, high: u64) u128 {
        return (@as(u128, high) << 64) | @as(u128, low);
    }

    /// Split i128 into two i64 values
    pub fn splitI128(value: i128) struct { low: i64, high: i64 } {
        const u_value: u128 = @bitCast(value);
        return .{
            .low = @bitCast(@as(u64, @truncate(u_value))),
            .high = @bitCast(@as(u64, @truncate(u_value >> 64))),
        };
    }

    /// Combine two i64 values into i128
    pub fn combineI64(low: i64, high: i64) i128 {
        const u_low: u64 = @bitCast(low);
        const u_high: u64 = @bitCast(high);
        const combined = (@as(u128, u_high) << 64) | @as(u128, u_low);
        return @bitCast(combined);
    }
};

/// Decimal string representation
pub const WideFormat = struct {
    /// Convert u128 to decimal string
    pub fn u128ToDecimal(allocator: std.mem.Allocator, value: u128) ![]const u8 {
        if (value == 0) return allocator.dupe(u8, "0");

        var buf = std.ArrayList(u8).init(allocator);
        defer buf.deinit();

        var temp = value;
        while (temp > 0) {
            const digit = @as(u8, @intCast(temp % 10));
            try buf.append('0' + digit);
            temp /= 10;
        }

        // Reverse the digits
        std.mem.reverse(u8, buf.items);
        return buf.toOwnedSlice();
    }

    /// Convert i128 to decimal string
    pub fn i128ToDecimal(allocator: std.mem.Allocator, value: i128) ![]const u8 {
        if (value == 0) return allocator.dupe(u8, "0");

        const is_negative = value < 0;
        const abs_value: u128 = @abs(value);

        var buf = std.ArrayList(u8).init(allocator);
        defer buf.deinit();

        if (is_negative) {
            try buf.append('-');
        }

        var temp = abs_value;
        var digits = std.ArrayList(u8).init(allocator);
        defer digits.deinit();

        while (temp > 0) {
            const digit = @as(u8, @intCast(temp % 10));
            try digits.append('0' + digit);
            temp /= 10;
        }

        // Reverse and append digits
        std.mem.reverse(u8, digits.items);
        try buf.appendSlice(digits.items);

        return buf.toOwnedSlice();
    }

    /// Convert u128 to hexadecimal string
    pub fn u128ToHex(allocator: std.mem.Allocator, value: u128) ![]const u8 {
        return std.fmt.allocPrint(allocator, "0x{x:0>32}", .{value});
    }

    /// Convert i128 to hexadecimal string
    pub fn i128ToHex(allocator: std.mem.Allocator, value: i128) ![]const u8 {
        const u_value: u128 = @bitCast(value);
        return std.fmt.allocPrint(allocator, "0x{x:0>32}", .{u_value});
    }
};
