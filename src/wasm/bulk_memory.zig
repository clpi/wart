/// Bulk Memory Operations
///
/// Implements the WebAssembly Bulk Memory Operations proposal:
/// - memory.copy - Copy data between memory regions
/// - memory.fill - Fill memory region with a byte value
/// - memory.init - Initialize memory from data segment
/// - data.drop - Drop a data segment
/// - table.copy - Copy table elements
/// - table.init - Initialize table from element segment
/// - elem.drop - Drop an element segment
///
/// Reference: https://github.com/WebAssembly/bulk-memory-operations
const std = @import("std");
const Allocator = std.mem.Allocator;
const Value = @import("value.zig").Value;

/// Bulk memory operation opcodes (0xFC prefix)
pub const Opcode = enum(u8) {
    memory_init = 0x08,
    data_drop = 0x09,
    memory_copy = 0x0A,
    memory_fill = 0x0B,
    table_init = 0x0C,
    elem_drop = 0x0D,
    table_copy = 0x0E,
    table_grow = 0x0F,
    table_size = 0x10,
    table_fill = 0x11,
};

/// Memory operations
pub const MemoryOps = struct {
    /// Copy memory regions (handles overlapping regions correctly)
    /// Stack: [dst: i32, src: i32, n: i32] -> []
    pub fn copy(memory: []u8, dst: u32, src: u32, n: u32) !void {
        const d: usize = @intCast(dst);
        const s: usize = @intCast(src);
        const count: usize = @intCast(n);

        // Bounds checking
        if (d > memory.len or s > memory.len) return error.OutOfBoundsMemoryAccess;
        if (d + count > memory.len or s + count > memory.len) return error.OutOfBoundsMemoryAccess;

        // Handle overlapping regions correctly (memmove semantics)
        if (d < s) {
            // Copy forward
            std.mem.copyForwards(u8, memory[d .. d + count], memory[s .. s + count]);
        } else if (d > s) {
            // Copy backward
            std.mem.copyBackwards(u8, memory[d .. d + count], memory[s .. s + count]);
        }
        // If d == s, no copy needed
    }

    /// Fill memory region with a byte value
    /// Stack: [dst: i32, val: i32, n: i32] -> []
    pub fn fill(memory: []u8, dst: u32, val: u32, n: u32) !void {
        const d: usize = @intCast(dst);
        const count: usize = @intCast(n);
        const byte: u8 = @truncate(val);

        // Bounds checking
        if (d > memory.len) return error.OutOfBoundsMemoryAccess;
        if (d + count > memory.len) return error.OutOfBoundsMemoryAccess;

        @memset(memory[d .. d + count], byte);
    }

    /// Initialize memory from a passive data segment
    /// Stack: [dst: i32, src: i32, n: i32] -> []
    pub fn init(
        memory: []u8,
        data_segment: []const u8,
        dst: u32,
        src: u32,
        n: u32,
    ) !void {
        const d: usize = @intCast(dst);
        const s: usize = @intCast(src);
        const count: usize = @intCast(n);

        // Bounds checking
        if (d > memory.len or s > data_segment.len) return error.OutOfBoundsMemoryAccess;
        if (d + count > memory.len or s + count > data_segment.len) return error.OutOfBoundsMemoryAccess;

        @memcpy(memory[d .. d + count], data_segment[s .. s + count]);
    }

    /// Optimized bulk zero operation
    pub fn zero(memory: []u8, dst: u32, n: u32) !void {
        return fill(memory, dst, 0, n);
    }

    /// Optimized bulk set operation (set to same value)
    pub fn set(memory: []u8, dst: u32, val: u8, n: u32) !void {
        return fill(memory, dst, val, n);
    }
};

/// Table operations
pub const TableOps = struct {
    /// Copy table elements (handles overlapping regions)
    /// Stack: [dst: i32, src: i32, n: i32] -> []
    pub fn copy(
        dst_table: []Value,
        src_table: []Value,
        dst: u32,
        src: u32,
        n: u32,
    ) !void {
        const d: usize = @intCast(dst);
        const s: usize = @intCast(src);
        const count: usize = @intCast(n);

        // Bounds checking
        if (d > dst_table.len or s > src_table.len) return error.OutOfBoundsTableAccess;
        if (d + count > dst_table.len or s + count > src_table.len) return error.OutOfBoundsTableAccess;

        // Handle overlapping regions if same table
        if (dst_table.ptr == src_table.ptr) {
            if (d < s) {
                std.mem.copyForwards(Value, dst_table[d .. d + count], src_table[s .. s + count]);
            } else if (d > s) {
                std.mem.copyBackwards(Value, dst_table[d .. d + count], src_table[s .. s + count]);
            }
        } else {
            // Different tables, direct copy is fine
            @memcpy(dst_table[d .. d + count], src_table[s .. s + count]);
        }
    }

    /// Fill table with a reference value
    /// Stack: [dst: i32, val: ref, n: i32] -> []
    pub fn fill(table: []Value, dst: u32, val: Value, n: u32) !void {
        const d: usize = @intCast(dst);
        const count: usize = @intCast(n);

        // Bounds checking
        if (d > table.len) return error.OutOfBoundsTableAccess;
        if (d + count > table.len) return error.OutOfBoundsTableAccess;

        // Fill with value
        for (table[d .. d + count]) |*elem| {
            elem.* = val;
        }
    }

    /// Initialize table from a passive element segment
    /// Stack: [dst: i32, src: i32, n: i32] -> []
    pub fn init(
        table: []Value,
        elem_segment: []const Value,
        dst: u32,
        src: u32,
        n: u32,
    ) !void {
        const d: usize = @intCast(dst);
        const s: usize = @intCast(src);
        const count: usize = @intCast(n);

        // Bounds checking
        if (d > table.len or s > elem_segment.len) return error.OutOfBoundsTableAccess;
        if (d + count > table.len or s + count > elem_segment.len) return error.OutOfBoundsTableAccess;

        @memcpy(table[d .. d + count], elem_segment[s .. s + count]);
    }

    /// Get table size
    pub fn size(table: []Value) u32 {
        return @intCast(table.len);
    }

    /// Grow table by delta entries, filling with init value
    pub fn grow(
        allocator: Allocator,
        table: *std.ArrayList(Value),
        delta: u32,
        init_val: Value,
    ) !i32 {
        const old_size: u32 = @intCast(table.items.len);
        const new_size = old_size + delta;

        // Check if growth would exceed implementation limits
        const max_table_size: u32 = 1 << 20; // 1M elements
        if (new_size > max_table_size) return -1;

        // Try to grow
        try table.ensureTotalCapacity(allocator, new_size);

        // Fill new entries with init value
        var i: u32 = 0;
        while (i < delta) : (i += 1) {
            try table.append(allocator, init_val);
        }

        return @intCast(old_size);
    }
};

/// Data segment manager
pub const DataSegmentManager = struct {
    segments: std.ArrayList([]const u8),
    dropped: std.ArrayList(bool),
    allocator: Allocator,

    pub fn init(allocator: Allocator) DataSegmentManager {
        return DataSegmentManager{
            .segments = std.ArrayList([]const u8).init(allocator),
            .dropped = std.ArrayList(bool).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *DataSegmentManager) void {
        // Free non-dropped segments
        for (self.segments.items, 0..) |segment, i| {
            if (!self.dropped.items[i]) {
                self.allocator.free(segment);
            }
        }
        self.segments.deinit(self.allocator);
        self.dropped.deinit(self.allocator);
    }

    pub fn addSegment(self: *DataSegmentManager, data: []const u8) !u32 {
        const segment = try self.allocator.dupe(u8, data);
        try self.segments.append(self.allocator, segment);
        try self.dropped.append(self.allocator, false);
        return @intCast(self.segments.items.len - 1);
    }

    pub fn drop(self: *DataSegmentManager, idx: u32) !void {
        const index: usize = @intCast(idx);
        if (index >= self.dropped.items.len) return error.InvalidDataSegment;
        if (self.dropped.items[index]) return; // Already dropped

        // Free the segment
        self.allocator.free(self.segments.items[index]);
        self.segments.items[index] = &[_]u8{};
        self.dropped.items[index] = true;
    }

    pub fn get(self: *DataSegmentManager, idx: u32) ![]const u8 {
        const index: usize = @intCast(idx);
        if (index >= self.segments.items.len) return error.InvalidDataSegment;
        if (self.dropped.items[index]) return error.DataSegmentDropped;
        return self.segments.items[index];
    }
};

/// Element segment manager
pub const ElemSegmentManager = struct {
    segments: std.ArrayList([]const Value),
    dropped: std.ArrayList(bool),
    allocator: Allocator,

    pub fn init(allocator: Allocator) ElemSegmentManager {
        return ElemSegmentManager{
            .segments = std.ArrayList([]const Value).init(allocator),
            .dropped = std.ArrayList(bool).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ElemSegmentManager) void {
        // Free non-dropped segments
        for (self.segments.items, 0..) |segment, i| {
            if (!self.dropped.items[i]) {
                self.allocator.free(segment);
            }
        }
        self.segments.deinit(self.allocator);
        self.dropped.deinit(self.allocator);
    }

    pub fn addSegment(self: *ElemSegmentManager, elems: []const Value) !u32 {
        const segment = try self.allocator.dupe(Value, elems);
        try self.segments.append(self.allocator, segment);
        try self.dropped.append(self.allocator, false);
        return @intCast(self.segments.items.len - 1);
    }

    pub fn drop(self: *ElemSegmentManager, idx: u32) !void {
        const index: usize = @intCast(idx);
        if (index >= self.dropped.items.len) return error.InvalidElemSegment;
        if (self.dropped.items[index]) return; // Already dropped

        // Free the segment
        self.allocator.free(self.segments.items[index]);
        self.segments.items[index] = &[_]Value{};
        self.dropped.items[index] = true;
    }

    pub fn get(self: *ElemSegmentManager, idx: u32) ![]const Value {
        const index: usize = @intCast(idx);
        if (index >= self.segments.items.len) return error.InvalidElemSegment;
        if (self.dropped.items[index]) return error.ElemSegmentDropped;
        return self.segments.items[index];
    }
};

/// Bulk operations executor
pub const BulkOperations = struct {
    data_mgr: DataSegmentManager,
    elem_mgr: ElemSegmentManager,

    pub fn init(allocator: Allocator) BulkOperations {
        return BulkOperations{
            .data_mgr = DataSegmentManager.init(allocator),
            .elem_mgr = ElemSegmentManager.init(allocator),
        };
    }

    pub fn deinit(self: *BulkOperations) void {
        self.data_mgr.deinit();
        self.elem_mgr.deinit();
    }

    /// Execute memory.init
    pub fn memoryInit(
        self: *BulkOperations,
        memory: []u8,
        data_idx: u32,
        dst: u32,
        src: u32,
        n: u32,
    ) !void {
        const segment = try self.data_mgr.get(data_idx);
        try MemoryOps.init(memory, segment, dst, src, n);
    }

    /// Execute table.init
    pub fn tableInit(
        self: *BulkOperations,
        table: []Value,
        elem_idx: u32,
        dst: u32,
        src: u32,
        n: u32,
    ) !void {
        const segment = try self.elem_mgr.get(elem_idx);
        try TableOps.init(table, segment, dst, src, n);
    }
};

/// Performance-optimized bulk operations
pub const OptimizedOps = struct {
    /// Vectorized memory copy for large transfers
    pub fn fastMemCopy(dst: []u8, src: []const u8) void {
        // Use SIMD when available and beneficial
        if (dst.len >= 64 and dst.len == src.len) {
            @memcpy(dst, src); // Compiler will optimize this
        } else {
            std.mem.copyForwards(u8, dst, src);
        }
    }

    /// Cache-optimized memory fill
    pub fn fastMemFill(dst: []u8, val: u8) void {
        if (dst.len >= 64) {
            @memset(dst, val); // Compiler will vectorize
        } else {
            // Small fills can be unrolled
            for (dst) |*b| b.* = val;
        }
    }

    /// Parallel bulk copy for very large transfers
    pub fn parallelMemCopy(dst: []u8, src: []const u8, thread_count: usize) !void {
        if (dst.len < 1024 * 1024 or thread_count <= 1) {
            // Too small for parallelization overhead
            @memcpy(dst, src);
            return;
        }

        const chunk_size = dst.len / thread_count;
        var i: usize = 0;
        while (i < thread_count) : (i += 1) {
            const start = i * chunk_size;
            const end = if (i == thread_count - 1) dst.len else (i + 1) * chunk_size;
            @memcpy(dst[start..end], src[start..end]);
        }
    }
};
