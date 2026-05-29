const std = @import("std");
const Reader = @This();

bytes: []const u8,
pos: usize = 0,

pub fn init(bytes: []const u8) Reader {
    return .{ .bytes = bytes };
}

/// ULTRA-FAST byte read - no bounds check for hot path
pub inline fn readByte(self: *Reader) !u8 {
    // Compiler hint: this branch is almost never taken
    if (self.pos >= self.bytes.len) return error.EndOfStream;
    const byte = self.bytes[self.pos];
    self.pos += 1;
    return byte;
}

/// ULTRA-FAST unchecked byte read - use only when you know there's data
pub inline fn readByteUnchecked(self: *Reader) u8 {
    const byte = self.bytes[self.pos];
    self.pos += 1;
    return byte;
}

/// ULTRA-FAST LEB128 read - optimized for single-byte case (>95% of cases)
pub inline fn readLEB128(self: *Reader) !u32 {
    // SUPER-FAST path: single-byte LEB128 (covers 0-127, most local/global indices)
    const byte = self.bytes[self.pos];
    self.pos += 1;
    if ((byte & 0x80) == 0) {
        return byte;
    }
    // 2-byte fast path (covers 128-16383, most offsets and larger indices)
    const byte2 = self.bytes[self.pos];
    self.pos += 1;
    if ((byte2 & 0x80) == 0) {
        return (@as(u32, byte & 0x7f)) | (@as(u32, byte2) << 7);
    }
    // Multi-byte case - rare, use slower path
    return self.readLEB128Slow2(byte, byte2);
}

/// Slow path for 3+ byte LEB128
fn readLEB128Slow2(self: *Reader, first_byte: u8, second_byte: u8) !u32 {
    var result: u32 = (@as(u32, first_byte & 0x7f)) | (@as(u32, second_byte & 0x7f) << 7);
    var shift: u5 = 14;
    while (true) {
        if (self.pos >= self.bytes.len) return error.EndOfStream;
        const next_byte = self.bytes[self.pos];
        self.pos += 1;
        result |= @as(u32, next_byte & 0x7f) << shift;
        if (next_byte & 0x80 == 0) break;
        if (shift >= 25) return error.Overflow;
        shift += 7;
    }
    return result;
}

pub fn readLEB128_u64(self: *Reader) !u64 {
    var result: u64 = 0;
    var shift: u6 = 0;
    while (true) {
        const byte = try self.readByte();
        result |= @as(u64, byte & 0x7F) << @as(u6, @intCast(shift));
        if (byte & 0x80 == 0) break;
        if (shift >= 57) return error.Overflow; // Prevent shift overflow: 57 + 7 = 64, max possible shift for u64
        shift +%= 7;
    }
    return result;
}

// Read signed LEB128 into i32
pub fn readSLEB32(self: *Reader) !i32 {
    var result: u32 = 0;
    var shift: u5 = 0;
    var byte: u8 = 0;

    while (true) {
        byte = try self.readByte();
        const low = @as(u32, byte & 0x7F);
        result |= (low << shift);
        if (byte & 0x80 == 0) break;
        if (shift >= 25) return error.Overflow; // Prevent shift overflow: 25 + 7 = 32, max possible shift for u32
        shift += 7;
    }

    // sign extend if needed
    if (shift < 32 and (byte & 0x40) != 0) {
        result |= (@as(u32, 0xFFFFFFFF) << shift);
    }

    return @as(i32, @bitCast(result));
}

// Read signed LEB128 into i64
pub fn readSLEB64(self: *Reader) !i64 {
    var result: i64 = 0;
    var shift: u6 = 0;
    var byte: u8 = 0;
    while (true) {
        byte = try self.readByte();
        const low = @as(i64, @intCast(byte & 0x7F));
        result |= (low << shift);
        if (byte & 0x80 == 0) break;
        if (shift >= 57) return error.Overflow; // Prevent shift overflow: 57 + 7 = 64, max possible shift for u64
        shift += 7;
    }
    if (shift < 64 and (byte & 0x40) != 0) {
        result |= @as(i64, -1) << shift;
    }
    return result;
}

pub fn readBytes(self: *Reader, len: usize) ![]const u8 {
    if (self.pos + len > self.bytes.len) return error.EndOfStream;
    const slice = self.bytes[self.pos .. self.pos + len];
    self.pos += len;
    return slice;
}

pub fn readName(self: *Reader, allocator: std.mem.Allocator) ![]u8 {
    const len = try self.readLEB128();
    const bytes = try self.readBytes(len);
    return try allocator.dupe(u8, bytes);
}

pub fn readF32(self: *Reader) !f32 {
    const bytes = try self.readBytes(4);
    return @as(f32, @bitCast(std.mem.readInt(u32, bytes[0..4], .little)));
}

pub fn readF64(self: *Reader) !f64 {
    const bytes = try self.readBytes(8);
    return @as(f64, @bitCast(std.mem.readInt(u64, bytes[0..8], .little)));
}
