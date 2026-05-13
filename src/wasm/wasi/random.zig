const std = @import("std");
const crypto = std.crypto;

/// WASI Preview 2 Random Implementation
/// Implements wasi:random/random@0.2.0 and wasi:random/insecure@0.2.0
pub const RandomError = error{
    InsufficientEntropy,
    SystemRandomUnavailable,
};

/// Cryptographically secure random number generator
pub const Random = struct {
    const Self = @This();

    /// Get cryptographically secure random bytes
    pub fn getRandomBytes(buffer: []u8) !void {
        crypto.random.bytes(buffer);
    }

    /// Get a single random u8
    pub fn getRandomU8() !u8 {
        return crypto.random.int(u8);
    }

    /// Get a single random u16
    pub fn getRandomU16() !u16 {
        return crypto.random.int(u16);
    }

    /// Get a single random u32
    pub fn getRandomU32() !u32 {
        return crypto.random.int(u32);
    }

    /// Get a single random u64
    pub fn getRandomU64() !u64 {
        return crypto.random.int(u64);
    }

    /// Get random bytes with specific length
    pub fn getBytesLen(comptime len: usize) ![len]u8 {
        var buffer: [len]u8 = undefined;
        try getRandomBytes(&buffer);
        return buffer;
    }

    /// Fill an array of integers with random values
    pub fn fillInts(comptime T: type, buffer: []T) !void {
        for (buffer) |*item| {
            item.* = crypto.random.int(T);
        }
    }

    /// Get random value in range [min, max)
    pub fn intRange(comptime T: type, min: T, max: T) !T {
        if (max <= min) return error.InvalidRange;
        const range = max - min;
        return min + @as(T, @intCast(crypto.random.int(T) % range));
    }

    /// Get random float in range [0.0, 1.0)
    pub fn float(comptime T: type) !T {
        switch (T) {
            f32 => return crypto.random.float(f32),
            f64 => return crypto.random.float(f64),
            else => @compileError("Only f32 and f64 supported"),
        }
    }

    /// Get random boolean
    pub fn boolean() !bool {
        return (try getRandomU8()) & 1 == 1;
    }

    /// Shuffle a slice using Fisher-Yates algorithm
    pub fn shuffle(comptime T: type, slice: []T) !void {
        if (slice.len <= 1) return;

        var i = slice.len;
        while (i > 1) {
            i -= 1;
            const j = try intRange(usize, 0, i + 1);
            std.mem.swap(T, &slice[i], &slice[j]);
        }
    }

    /// Get random element from slice
    pub fn choice(comptime T: type, slice: []const T) !T {
        if (slice.len == 0) return error.EmptySlice;
        const index = try intRange(usize, 0, slice.len);
        return slice[index];
    }
};

/// Insecure (but fast) random number generator
/// Uses for non-cryptographic purposes where speed > security
pub const InsecureRandom = struct {
    const Self = @This();
    prng: std.Random.Xoshiro256,

    pub fn init(seed: u64) Self {
        var prng = std.Random.DefaultPrng.init(seed);
        return Self{
            .prng = prng,
        };
    }

    pub fn initWithSystemSeed() !Self {
        const seed = crypto.random.int(u64);
        return init(seed);
    }

    pub fn getRandomBytes(self: *Self, buffer: []u8) void {
        self.prng.random().bytes(buffer);
    }

    pub fn getRandomU8(self: *Self) u8 {
        return self.prng.random().int(u8);
    }

    pub fn getRandomU16(self: *Self) u16 {
        return self.prng.random().int(u16);
    }

    pub fn getRandomU32(self: *Self) u32 {
        return self.prng.random().int(u32);
    }

    pub fn getRandomU64(self: *Self) u64 {
        return self.prng.random().int(u64);
    }

    pub fn intRange(self: *Self, comptime T: type, min: T, max: T) T {
        if (max <= min) return min;
        const range = max - min;
        return min + @as(T, @intCast(self.prng.random().int(T) % range));
    }

    pub fn float(self: *Self, comptime T: type) T {
        return self.prng.random().float(T);
    }

    pub fn boolean(self: *Self) bool {
        return self.getRandomU8() & 1 == 1;
    }

    pub fn shuffle(self: *Self, comptime T: type, slice: []T) void {
        if (slice.len <= 1) return;

        var i = slice.len;
        while (i > 1) {
            i -= 1;
            const j = self.intRange(usize, 0, i + 1);
            std.mem.swap(T, &slice[i], &slice[j]);
        }
    }

    pub fn choice(self: *Self, comptime T: type, slice: []const T) ?T {
        if (slice.len == 0) return null;
        const index = self.intRange(usize, 0, slice.len);
        return slice[index];
    }
};

/// UUID v4 generation
pub const UUID = struct {
    bytes: [16]u8,

    pub fn v4() !UUID {
        var uuid: UUID = undefined;
        try Random.getRandomBytes(&uuid.bytes);

        // Set version to 4
        uuid.bytes[6] = (uuid.bytes[6] & 0x0F) | 0x40;

        // Set variant to RFC 4122
        uuid.bytes[8] = (uuid.bytes[8] & 0x3F) | 0x80;

        return uuid;
    }

    pub fn toString(self: UUID) [36]u8 {
        var buffer: [36]u8 = undefined;
        _ = std.fmt.bufPrint(&buffer, "{x:0>2}{x:0>2}{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}", .{
            self.bytes[0],
            self.bytes[1],
            self.bytes[2],
            self.bytes[3],
            self.bytes[4],
            self.bytes[5],
            self.bytes[6],
            self.bytes[7],
            self.bytes[8],
            self.bytes[9],
            self.bytes[10],
            self.bytes[11],
            self.bytes[12],
            self.bytes[13],
            self.bytes[14],
            self.bytes[15],
        }) catch unreachable;
        return buffer;
    }
};

// Tests
test "Random.getRandomU64" {
    const r1 = try Random.getRandomU64();
    const r2 = try Random.getRandomU64();

    // Extremely unlikely to be equal
    try std.testing.expect(r1 != r2);
}

test "Random.intRange" {
    for (0..100) |_| {
        const val = try Random.intRange(u32, 10, 20);
        try std.testing.expect(val >= 10 and val < 20);
    }
}

test "Random.float" {
    for (0..100) |_| {
        const val = try Random.float(f64);
        try std.testing.expect(val >= 0.0 and val < 1.0);
    }
}

test "InsecureRandom" {
    var rng = try InsecureRandom.initWithSystemSeed();

    const r1 = rng.getRandomU64();
    const r2 = rng.getRandomU64();

    try std.testing.expect(r1 != r2);
}

test "UUID.v4" {
    const uuid = try UUID.v4();

    // Check version bits
    try std.testing.expect((uuid.bytes[6] & 0xF0) == 0x40);

    // Check variant bits
    try std.testing.expect((uuid.bytes[8] & 0xC0) == 0x80);
}

test "Random.shuffle" {
    var arr = [_]u32{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
    const original = arr;

    try Random.shuffle(u32, &arr);

    // Extremely unlikely to be the same order
    var same_count: usize = 0;
    for (arr, original) |a, b| {
        if (a == b) same_count += 1;
    }

    try std.testing.expect(same_count < 10);
}
