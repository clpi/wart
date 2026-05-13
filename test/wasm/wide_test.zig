const std = @import("std");
const testing = std.testing;
const wide = @import("../../src/wasm/wide.zig");

const WideValue = wide.WideValue;
const WideArithmetic = wide.WideArithmetic;
const WideConvert = wide.WideConvert;
const WideFormat = wide.WideFormat;

// Test WideValue
test "wide value - u128 to low/high" {
    const value = WideValue{ .u128 = 0x123456789ABCDEF0FEDCBA9876543210 };
    const parts = value.toLowHigh();

    try testing.expectEqual(@as(u64, 0xFEDCBA9876543210), parts.low);
    try testing.expectEqual(@as(u64, 0x123456789ABCDEF0), parts.high);
}

test "wide value - from low/high unsigned" {
    const value = WideValue.fromLowHigh(0xFEDCBA9876543210, 0x123456789ABCDEF0, false);

    try testing.expectEqual(@as(u128, 0x123456789ABCDEF0FEDCBA9876543210), value.u128);
}

test "wide value - from low/high signed" {
    const value = WideValue.fromLowHigh(0xFEDCBA9876543210, 0x123456789ABCDEF0, true);

    const expected: i128 = @bitCast(@as(u128, 0x123456789ABCDEF0FEDCBA9876543210));
    try testing.expectEqual(expected, value.i128);
}

// Test arithmetic operations
test "add u128 - no overflow" {
    const a: u128 = 100;
    const b: u128 = 200;

    const result = WideArithmetic.addU128(a, b);
    try testing.expectEqual(@as(u128, 300), result.result);
    try testing.expect(!result.overflow);
}

test "add u128 - with overflow" {
    const a: u128 = std.math.maxInt(u128);
    const b: u128 = 1;

    const result = WideArithmetic.addU128(a, b);
    try testing.expectEqual(@as(u128, 0), result.result);
    try testing.expect(result.overflow);
}

test "add i128 - no overflow" {
    const a: i128 = -100;
    const b: i128 = 50;

    const result = WideArithmetic.addI128(a, b);
    try testing.expectEqual(@as(i128, -50), result.result);
    try testing.expect(!result.overflow);
}

test "sub u128 - no overflow" {
    const a: u128 = 300;
    const b: u128 = 100;

    const result = WideArithmetic.subU128(a, b);
    try testing.expectEqual(@as(u128, 200), result.result);
    try testing.expect(!result.overflow);
}

test "sub u128 - with underflow" {
    const a: u128 = 100;
    const b: u128 = 200;

    const result = WideArithmetic.subU128(a, b);
    try testing.expect(result.overflow);
}

test "mul u128 - basic" {
    const a: u128 = 12345;
    const b: u128 = 67890;

    const result = WideArithmetic.mulU128(a, b);
    try testing.expectEqual(@as(u128, 838102050), result);
}

test "mul i128 - basic" {
    const a: i128 = -100;
    const b: i128 = 50;

    const result = WideArithmetic.mulI128(a, b);
    try testing.expectEqual(@as(i128, -5000), result);
}

test "mul wide u128 - 256-bit result" {
    const a: u128 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    const b: u128 = 2;

    const result = WideArithmetic.mulWideU128(a, b);
    try testing.expectEqual(@as(u128, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFE), result.low);
    try testing.expectEqual(@as(u128, 1), result.high);
}

test "div u128 - basic" {
    const a: u128 = 1000;
    const b: u128 = 10;

    const result = try WideArithmetic.divU128(a, b);
    try testing.expectEqual(@as(u128, 100), result);
}

test "div u128 - by zero" {
    const a: u128 = 1000;
    const b: u128 = 0;

    const result = WideArithmetic.divU128(a, b);
    try testing.expectError(error.DivisionByZero, result);
}

test "div i128 - basic" {
    const a: i128 = -1000;
    const b: i128 = 10;

    const result = try WideArithmetic.divI128(a, b);
    try testing.expectEqual(@as(i128, -100), result);
}

test "div i128 - overflow" {
    const a: i128 = std.math.minInt(i128);
    const b: i128 = -1;

    const result = WideArithmetic.divI128(a, b);
    try testing.expectError(error.Overflow, result);
}

test "rem u128 - basic" {
    const a: u128 = 1005;
    const b: u128 = 100;

    const result = try WideArithmetic.remU128(a, b);
    try testing.expectEqual(@as(u128, 5), result);
}

test "rem i128 - basic" {
    const a: i128 = -1005;
    const b: i128 = 100;

    const result = try WideArithmetic.remI128(a, b);
    try testing.expectEqual(@as(i128, -5), result);
}

// Test bitwise operations
test "and u128 - basic" {
    const a: u128 = 0xFF00;
    const b: u128 = 0x0FF0;

    const result = WideArithmetic.andU128(a, b);
    try testing.expectEqual(@as(u128, 0x0F00), result);
}

test "or u128 - basic" {
    const a: u128 = 0xFF00;
    const b: u128 = 0x00FF;

    const result = WideArithmetic.orU128(a, b);
    try testing.expectEqual(@as(u128, 0xFFFF), result);
}

test "xor u128 - basic" {
    const a: u128 = 0xFFFF;
    const b: u128 = 0xFF00;

    const result = WideArithmetic.xorU128(a, b);
    try testing.expectEqual(@as(u128, 0x00FF), result);
}

test "not u128 - basic" {
    const a: u128 = 0;

    const result = WideArithmetic.notU128(a);
    try testing.expectEqual(@as(u128, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF), result);
}

// Test shift operations
test "shl u128 - basic" {
    const a: u128 = 1;

    const result = WideArithmetic.shlU128(a, 8);
    try testing.expectEqual(@as(u128, 256), result);
}

test "shl u128 - overflow" {
    const a: u128 = 1;

    const result = WideArithmetic.shlU128(a, 128);
    try testing.expectEqual(@as(u128, 0), result);
}

test "shr u128 - basic" {
    const a: u128 = 256;

    const result = WideArithmetic.shrU128(a, 8);
    try testing.expectEqual(@as(u128, 1), result);
}

test "shr i128 - arithmetic positive" {
    const a: i128 = 256;

    const result = WideArithmetic.shrI128(a, 8);
    try testing.expectEqual(@as(i128, 1), result);
}

test "shr i128 - arithmetic negative" {
    const a: i128 = -256;

    const result = WideArithmetic.shrI128(a, 8);
    try testing.expectEqual(@as(i128, -1), result);
}

test "rotl u128 - basic" {
    const a: u128 = 0x1;

    const result = WideArithmetic.rotlU128(a, 127);
    try testing.expectEqual(@as(u128, 0x80000000000000000000000000000000), result);
}

test "rotr u128 - basic" {
    const a: u128 = 0x80000000000000000000000000000000;

    const result = WideArithmetic.rotrU128(a, 127);
    try testing.expectEqual(@as(u128, 0x1), result);
}

// Test bit counting
test "clz u128 - leading zeros" {
    const a: u128 = 0x00000000000000000000000000000001;

    const result = WideArithmetic.clzU128(a);
    try testing.expectEqual(@as(u8, 127), result);
}

test "ctz u128 - trailing zeros" {
    const a: u128 = 0x10000000000000000000000000000000;

    const result = WideArithmetic.ctzU128(a);
    try testing.expectEqual(@as(u8, 124), result);
}

test "popcnt u128 - basic" {
    const a: u128 = 0xFF;

    const result = WideArithmetic.popcntU128(a);
    try testing.expectEqual(@as(u8, 8), result);
}

// Test comparisons
test "eq u128 - equal" {
    try testing.expect(WideArithmetic.eqU128(42, 42));
}

test "eq u128 - not equal" {
    try testing.expect(!WideArithmetic.eqU128(42, 43));
}

test "lt u128 - less than" {
    try testing.expect(WideArithmetic.ltU128(10, 20));
}

test "lt i128 - less than" {
    try testing.expect(WideArithmetic.ltI128(-10, 10));
}

test "le u128 - less than or equal" {
    try testing.expect(WideArithmetic.leU128(10, 10));
    try testing.expect(WideArithmetic.leU128(10, 20));
}

test "gt u128 - greater than" {
    try testing.expect(WideArithmetic.gtU128(20, 10));
}

test "ge u128 - greater than or equal" {
    try testing.expect(WideArithmetic.geU128(10, 10));
    try testing.expect(WideArithmetic.geU128(20, 10));
}

// Test conversions
test "extend i64 to i128" {
    const a: i64 = -42;

    const result = WideArithmetic.extendI64(a);
    try testing.expectEqual(@as(i128, -42), result);
}

test "extend u64 to u128" {
    const a: u64 = 12345;

    const result = WideArithmetic.extendU64(a);
    try testing.expectEqual(@as(u128, 12345), result);
}

test "truncate u128 to u64" {
    const a: u128 = 0x123456789ABCDEF0FEDCBA9876543210;

    const result = WideArithmetic.truncateU128ToU64(a);
    try testing.expectEqual(@as(u64, 0xFEDCBA9876543210), result);
}

test "i128 to f64" {
    const a: i128 = 1000000;

    const result = WideArithmetic.i128ToF64(a);
    try testing.expectApproxEqAbs(@as(f64, 1000000.0), result, 0.1);
}

test "u128 to f64" {
    const a: u128 = 1000000;

    const result = WideArithmetic.u128ToF64(a);
    try testing.expectApproxEqAbs(@as(f64, 1000000.0), result, 0.1);
}

test "f64 to i128" {
    const a: f64 = -1000.5;

    const result = try WideArithmetic.f64ToI128(a);
    try testing.expectEqual(@as(i128, -1000), result);
}

test "f64 to u128" {
    const a: f64 = 1000.5;

    const result = try WideArithmetic.f64ToU128(a);
    try testing.expectEqual(@as(u128, 1000), result);
}

test "f64 to i128 - NaN" {
    const a: f64 = std.math.nan(f64);

    const result = WideArithmetic.f64ToI128(a);
    try testing.expectError(error.InvalidConversion, result);
}

// Test memory operations
test "load128 - basic" {
    const allocator = testing.allocator;
    var memory = try allocator.alloc(u8, 32);
    defer allocator.free(memory);

    std.mem.writeInt(u64, memory[0..8], 0xFEDCBA9876543210, .little);
    std.mem.writeInt(u64, memory[8..16], 0x123456789ABCDEF0, .little);

    const value = try wide.load128(memory, 0);
    try testing.expectEqual(@as(u128, 0x123456789ABCDEF0FEDCBA9876543210), value);
}

test "store128 - basic" {
    const allocator = testing.allocator;
    var memory = try allocator.alloc(u8, 32);
    defer allocator.free(memory);

    try wide.store128(memory, 0, 0x123456789ABCDEF0FEDCBA9876543210);

    const low = std.mem.readInt(u64, memory[0..8], .little);
    const high = std.mem.readInt(u64, memory[8..16], .little);

    try testing.expectEqual(@as(u64, 0xFEDCBA9876543210), low);
    try testing.expectEqual(@as(u64, 0x123456789ABCDEF0), high);
}

// Test WideConvert
test "split u128" {
    const value: u128 = 0x123456789ABCDEF0FEDCBA9876543210;
    const parts = WideConvert.splitU128(value);

    try testing.expectEqual(@as(u64, 0xFEDCBA9876543210), parts.low);
    try testing.expectEqual(@as(u64, 0x123456789ABCDEF0), parts.high);
}

test "combine u64" {
    const low: u64 = 0xFEDCBA9876543210;
    const high: u64 = 0x123456789ABCDEF0;

    const value = WideConvert.combineU64(low, high);
    try testing.expectEqual(@as(u128, 0x123456789ABCDEF0FEDCBA9876543210), value);
}

test "split i128" {
    const value: i128 = -12345;
    const parts = WideConvert.splitI128(value);

    const reconstructed = WideConvert.combineI64(parts.low, parts.high);
    try testing.expectEqual(value, reconstructed);
}

// Test WideFormat
test "u128 to decimal" {
    const allocator = testing.allocator;

    const str = try WideFormat.u128ToDecimal(allocator, 12345);
    defer allocator.free(str);

    try testing.expectEqualStrings("12345", str);
}

test "u128 to decimal - zero" {
    const allocator = testing.allocator;

    const str = try WideFormat.u128ToDecimal(allocator, 0);
    defer allocator.free(str);

    try testing.expectEqualStrings("0", str);
}

test "i128 to decimal - positive" {
    const allocator = testing.allocator;

    const str = try WideFormat.i128ToDecimal(allocator, 12345);
    defer allocator.free(str);

    try testing.expectEqualStrings("12345", str);
}

test "i128 to decimal - negative" {
    const allocator = testing.allocator;

    const str = try WideFormat.i128ToDecimal(allocator, -12345);
    defer allocator.free(str);

    try testing.expectEqualStrings("-12345", str);
}

test "u128 to hex" {
    const allocator = testing.allocator;

    const str = try WideFormat.u128ToHex(allocator, 0x123);
    defer allocator.free(str);

    try testing.expect(std.mem.containsAtLeast(u8, str, 1, "123"));
}
