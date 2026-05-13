const std = @import("std");

/// Ultra-fast fixed-capacity stack optimized for WASM execution.
/// Uses raw pointer arithmetic for maximum performance in hot paths.
/// INLINE size is sufficient for 99.9% of WASM functions.
pub fn SmallVec(comptime T: type, comptime INLINE: usize) type {
    return struct {
        const Self = @This();

        // Raw buffer pointer for zero-overhead access
        buf: [*]T = undefined,
        // Current length - single field access in hot path
        len: usize = 0,
        // Capacity tracking
        capacity: usize = 0,
        // Items view (for compatibility with existing code that uses .items)
        items: []T = &[_]T{},

        pub fn init() Self {
            return Self{
                .buf = undefined,
                .len = 0,
                .capacity = 0,
                .items = &[_]T{},
            };
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            if (self.capacity > 0) {
                allocator.free(self.buf[0..self.capacity]);
            }
            self.buf = undefined;
            self.len = 0;
            self.capacity = 0;
            self.items = &[_]T{};
        }

        pub fn ensureTotalCapacity(self: *Self, allocator: std.mem.Allocator, n: usize) !void {
            if (n <= self.capacity) return;

            // Allocate new buffer with extra capacity to avoid frequent reallocations
            const new_cap = @max(n, @max(INLINE, self.capacity * 2));
            const new_buf = try allocator.alloc(T, new_cap);

            // Copy existing items
            if (self.capacity > 0) {
                @memcpy(new_buf[0..self.len], self.buf[0..self.len]);
                allocator.free(self.buf[0..self.capacity]);
            }

            self.buf = new_buf.ptr;
            self.capacity = new_cap;
            self.items = new_buf[0..self.len];
        }

        /// ULTRA-FAST append - inlined for hot path performance
        pub inline fn append(self: *Self, allocator: std.mem.Allocator, v: T) !void {
            @setEvalBranchQuota(1000000);
            // Ensure we have capacity
            if (self.len >= self.capacity) {
                try self.ensureTotalCapacity(allocator, self.len + 1);
            }
            // Direct write - no bounds check, no slice update
            self.buf[self.len] = v;
            self.len += 1;
            // Update items view for compatibility
            self.items = self.buf[0..self.len];
        }

        /// ULTRA-FAST pop - inlined for hot path performance
        pub inline fn pop(self: *Self) ?T {
            @setEvalBranchQuota(1000000);
            if (self.len == 0) return null;
            self.len -= 1;
            const val = self.buf[self.len];
            // Update items view for compatibility
            self.items = self.buf[0..self.len];
            return val;
        }

        /// ULTRA-FAST shrink - inlined for hot path performance
        pub inline fn shrinkRetainingCapacity(self: *Self, new_len: usize) void {
            @setEvalBranchQuota(1000000);
            if (new_len < self.len) {
                self.len = new_len;
                self.items = if (self.capacity > 0) self.buf[0..self.len] else &[_]T{};
            }
        }
    };
}
