/// WebAssembly Multi-Memory Support (WASM 3.0)
///
/// Implements the Multi-Memory proposal which allows WebAssembly modules to:
/// - Define and use multiple linear memories
/// - Reference memories by index in memory instructions
/// - Import and export multiple memories
///
/// Reference: https://github.com/WebAssembly/multi-memory
const std = @import("std");
const Allocator = std.mem.Allocator;
const Value = @import("value.zig").Value;

/// Memory instance
pub const Memory = struct {
    /// Memory data
    data: []u8,
    /// Minimum size in pages (64KB each)
    min_pages: u32,
    /// Maximum size in pages (optional)
    max_pages: ?u32,
    /// Whether this is shared memory
    shared: bool = false,
    /// Memory index
    index: u32,
    /// Import info if imported
    import: ?ImportInfo = null,

    pub const ImportInfo = struct {
        module_name: []const u8,
        field_name: []const u8,
    };

    const PAGE_SIZE: usize = 65536; // 64KB

    pub fn init(allocator: Allocator, min_pages: u32, max_pages: ?u32, index: u32) !Memory {
        const mem_size = @as(usize, min_pages) * PAGE_SIZE;
        const data = try allocator.alloc(u8, mem_size);
        @memset(data, 0);

        return Memory{
            .data = data,
            .min_pages = min_pages,
            .max_pages = max_pages,
            .index = index,
        };
    }

    pub fn deinit(self: *Memory, allocator: Allocator) void {
        if (self.import == null) {
            allocator.free(self.data);
        }
    }

    /// Get current size in pages
    pub fn size(self: *const Memory) u32 {
        return @intCast(self.data.len / PAGE_SIZE);
    }

    /// Grow memory by delta pages
    /// Returns previous size in pages on success, -1 on failure
    pub fn grow(self: *Memory, allocator: Allocator, delta: u32) i32 {
        const current_pages = self.size();
        const new_pages = current_pages + delta;

        // Check maximum limit
        if (self.max_pages) |max| {
            if (new_pages > max) return -1;
        }

        // Check implementation limit (4GB = 65536 pages)
        if (new_pages > 65536) return -1;

        const new_size = @as(usize, new_pages) * PAGE_SIZE;

        // Try to resize
        if (allocator.resize(self.data, new_size)) {
            @memset(self.data[self.data.len..new_size], 0);
            self.data = self.data.ptr[0..new_size];
            return @intCast(current_pages);
        }

        const new_data = allocator.realloc(self.data, new_size) catch return -1;
        @memset(new_data[self.data.len..new_size], 0);
        self.data = new_data;
        return @intCast(current_pages);
    }

    /// Read from memory with bounds checking
    pub inline fn read(self: *const Memory, comptime T: type, addr: u32) !T {
        const size_t = @sizeOf(T);
        if (@as(usize, addr) + size_t > self.data.len) {
            return error.OutOfBoundsMemoryAccess;
        }
        return std.mem.readInt(T, self.data[addr..][0..size_t], .little);
    }

    /// Write to memory with bounds checking
    pub inline fn write(self: *Memory, comptime T: type, addr: u32, value: T) !void {
        const size_t = @sizeOf(T);
        if (@as(usize, addr) + size_t > self.data.len) {
            return error.OutOfBoundsMemoryAccess;
        }
        std.mem.writeInt(T, self.data[addr..][0..size_t], value, .little);
    }

    /// Get slice with bounds checking
    pub inline fn slice(self: *Memory, addr: u32, len: u32) ![]u8 {
        if (@as(usize, addr) + len > self.data.len) {
            return error.OutOfBoundsMemoryAccess;
        }
        return self.data[addr..][0..len];
    }

    /// Copy within same memory
    pub fn copy(self: *Memory, dst: u32, src: u32, len: u32) !void {
        const d: usize = dst;
        const s: usize = src;
        const n: usize = len;

        if (d + n > self.data.len or s + n > self.data.len) {
            return error.OutOfBoundsMemoryAccess;
        }

        // Handle overlapping regions
        if (d < s) {
            std.mem.copyForwards(u8, self.data[d .. d + n], self.data[s .. s + n]);
        } else if (d > s) {
            std.mem.copyBackwards(u8, self.data[d .. d + n], self.data[s .. s + n]);
        }
    }

    /// Fill memory region
    pub fn fill(self: *Memory, dst: u32, val: u8, len: u32) !void {
        const d: usize = dst;
        const n: usize = len;

        if (d + n > self.data.len) {
            return error.OutOfBoundsMemoryAccess;
        }

        @memset(self.data[d .. d + n], val);
    }
};

/// Multi-memory manager
pub const MultiMemoryManager = struct {
    allocator: Allocator,
    memories: std.ArrayList(Memory),
    /// Default memory index (for backwards compatibility)
    default_memory: u32 = 0,

    pub fn init(allocator: Allocator) MultiMemoryManager {
        return MultiMemoryManager{
            .allocator = allocator,
            .memories = .{},
        };
    }

    pub fn deinit(self: *MultiMemoryManager) void {
        for (self.memories.items) |*mem| {
            mem.deinit(self.allocator);
        }
        self.memories.deinit(self.allocator);
    }

    /// Add a new memory instance
    pub fn addMemory(self: *MultiMemoryManager, min_pages: u32, max_pages: ?u32) !u32 {
        const index: u32 = @intCast(self.memories.items.len);
        const memory = try Memory.init(self.allocator, min_pages, max_pages, index);
        try self.memories.append(self.allocator, memory);
        return index;
    }

    /// Add imported memory
    pub fn addImportedMemory(
        self: *MultiMemoryManager,
        data: []u8,
        module_name: []const u8,
        field_name: []const u8,
    ) !u32 {
        const index: u32 = @intCast(self.memories.items.len);

        try self.memories.append(self.allocator, .{
            .data = data,
            .min_pages = @intCast(data.len / Memory.PAGE_SIZE),
            .max_pages = null,
            .index = index,
            .import = .{
                .module_name = module_name,
                .field_name = field_name,
            },
        });

        return index;
    }

    /// Get memory by index
    pub fn getMemory(self: *MultiMemoryManager, index: u32) ?*Memory {
        if (index >= self.memories.items.len) return null;
        return &self.memories.items[index];
    }

    /// Get default memory (for backwards compatibility)
    pub fn getDefaultMemory(self: *MultiMemoryManager) ?*Memory {
        return self.getMemory(self.default_memory);
    }

    /// Get raw data pointer for default memory
    pub fn getDefaultData(self: *MultiMemoryManager) ?[]u8 {
        if (self.getDefaultMemory()) |mem| {
            return mem.data;
        }
        return null;
    }

    /// Memory size for specific index
    pub fn memorySize(self: *MultiMemoryManager, index: u32) i32 {
        if (self.getMemory(index)) |mem| {
            return @intCast(mem.size());
        }
        return -1;
    }

    /// Memory grow for specific index
    pub fn memoryGrow(self: *MultiMemoryManager, index: u32, delta: u32) i32 {
        if (self.getMemory(index)) |mem| {
            return mem.grow(self.allocator, delta);
        }
        return -1;
    }

    /// Copy between two memories
    pub fn memoryCopy(
        self: *MultiMemoryManager,
        dst_mem: u32,
        dst_addr: u32,
        src_mem: u32,
        src_addr: u32,
        len: u32,
    ) !void {
        const dst = self.getMemory(dst_mem) orelse return error.InvalidMemoryIndex;
        const src = self.getMemory(src_mem) orelse return error.InvalidMemoryIndex;

        // Check bounds
        if (@as(usize, dst_addr) + len > dst.data.len or
            @as(usize, src_addr) + len > src.data.len)
        {
            return error.OutOfBoundsMemoryAccess;
        }

        // Perform copy
        @memcpy(dst.data[dst_addr..][0..len], src.data[src_addr..][0..len]);
    }

    /// Initialize memory from data segment
    pub fn memoryInit(
        self: *MultiMemoryManager,
        mem_index: u32,
        data: []const u8,
        dst: u32,
        src: u32,
        len: u32,
    ) !void {
        const mem = self.getMemory(mem_index) orelse return error.InvalidMemoryIndex;

        // Check bounds
        if (@as(usize, dst) + len > mem.data.len or
            @as(usize, src) + len > data.len)
        {
            return error.OutOfBoundsMemoryAccess;
        }

        @memcpy(mem.data[dst..][0..len], data[src..][0..len]);
    }

    /// Fill memory region
    pub fn memoryFill(
        self: *MultiMemoryManager,
        mem_index: u32,
        dst: u32,
        val: u8,
        len: u32,
    ) !void {
        const mem = self.getMemory(mem_index) orelse return error.InvalidMemoryIndex;
        try mem.fill(dst, val, len);
    }
};

/// Memory operation with index (multi-memory aware)
pub const MemoryOp = struct {
    /// Memory index (0 for single-memory modules)
    mem_idx: u32,
    /// Alignment (log2)
    align_log2: u32,
    /// Offset
    offset: u32,

    /// Parse memory operand from instruction stream
    pub fn parse(reader: anytype, multi_memory: bool) !MemoryOp {
        if (multi_memory) {
            const mem_idx = try reader.readLEB128();
            const align_log2 = try reader.readLEB128();
            const offset = try reader.readLEB128();
            return .{
                .mem_idx = @intCast(mem_idx),
                .align_log2 = @intCast(align_log2),
                .offset = @intCast(offset),
            };
        } else {
            const align_log2 = try reader.readLEB128();
            const offset = try reader.readLEB128();
            return .{
                .mem_idx = 0,
                .align_log2 = @intCast(align_log2),
                .offset = @intCast(offset),
            };
        }
    }

    /// Compute effective address
    pub inline fn effectiveAddress(self: MemoryOp, base: u32) u32 {
        return base +% self.offset;
    }
};

// ============================================================================
// Optimized Memory Access Routines
// ============================================================================

/// Ultra-fast memory load operations
pub const FastMemLoad = struct {
    /// Load i32 without bounds checking (use only when safe)
    pub inline fn loadI32Unsafe(data: [*]const u8, addr: usize) i32 {
        return @bitCast(@as(*align(1) const u32, @ptrCast(data + addr)).*);
    }

    /// Load i64 without bounds checking
    pub inline fn loadI64Unsafe(data: [*]const u8, addr: usize) i64 {
        return @bitCast(@as(*align(1) const u64, @ptrCast(data + addr)).*);
    }

    /// Load f32 without bounds checking
    pub inline fn loadF32Unsafe(data: [*]const u8, addr: usize) f32 {
        return @bitCast(@as(*align(1) const u32, @ptrCast(data + addr)).*);
    }

    /// Load f64 without bounds checking
    pub inline fn loadF64Unsafe(data: [*]const u8, addr: usize) f64 {
        return @bitCast(@as(*align(1) const u64, @ptrCast(data + addr)).*);
    }

    /// Bounds-checked load with fast path
    pub inline fn loadI32(data: []const u8, addr: u32, offset: u32) !i32 {
        const eff_addr = @as(usize, addr) +% offset;
        if (eff_addr + 4 > data.len) return error.OutOfBoundsMemoryAccess;
        return loadI32Unsafe(data.ptr, eff_addr);
    }

    pub inline fn loadI64(data: []const u8, addr: u32, offset: u32) !i64 {
        const eff_addr = @as(usize, addr) +% offset;
        if (eff_addr + 8 > data.len) return error.OutOfBoundsMemoryAccess;
        return loadI64Unsafe(data.ptr, eff_addr);
    }
};

/// Ultra-fast memory store operations
pub const FastMemStore = struct {
    /// Store i32 without bounds checking
    pub inline fn storeI32Unsafe(data: [*]u8, addr: usize, value: i32) void {
        @as(*align(1) u32, @ptrCast(data + addr)).* = @bitCast(value);
    }

    /// Store i64 without bounds checking
    pub inline fn storeI64Unsafe(data: [*]u8, addr: usize, value: i64) void {
        @as(*align(1) u64, @ptrCast(data + addr)).* = @bitCast(value);
    }

    /// Bounds-checked store with fast path
    pub inline fn storeI32(data: []u8, addr: u32, offset: u32, value: i32) !void {
        const eff_addr = @as(usize, addr) +% offset;
        if (eff_addr + 4 > data.len) return error.OutOfBoundsMemoryAccess;
        storeI32Unsafe(data.ptr, eff_addr, value);
    }

    pub inline fn storeI64(data: []u8, addr: u32, offset: u32, value: i64) !void {
        const eff_addr = @as(usize, addr) +% offset;
        if (eff_addr + 8 > data.len) return error.OutOfBoundsMemoryAccess;
        storeI64Unsafe(data.ptr, eff_addr, value);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "memory basic operations" {
    const allocator = std.testing.allocator;
    var mem = try Memory.init(allocator, 1, 10, 0);
    defer mem.deinit(allocator);

    // Test size
    try std.testing.expectEqual(@as(u32, 1), mem.size());

    // Test write/read
    try mem.write(u32, 0, 0xDEADBEEF);
    const val = try mem.read(u32, 0);
    try std.testing.expectEqual(@as(u32, 0xDEADBEEF), val);

    // Test grow
    const old_size = mem.grow(allocator, 2);
    try std.testing.expectEqual(@as(i32, 1), old_size);
    try std.testing.expectEqual(@as(u32, 3), mem.size());
}

test "multi-memory manager" {
    const allocator = std.testing.allocator;
    var mgr = MultiMemoryManager.init(allocator);
    defer mgr.deinit();

    // Add memories
    const idx0 = try mgr.addMemory(1, null);
    const idx1 = try mgr.addMemory(2, 10);

    try std.testing.expectEqual(@as(u32, 0), idx0);
    try std.testing.expectEqual(@as(u32, 1), idx1);

    // Test memory operations
    const mem0 = mgr.getMemory(0).?;
    const mem1 = mgr.getMemory(1).?;

    try mem0.write(u32, 0, 42);
    try mem1.write(u32, 0, 100);

    try std.testing.expectEqual(@as(u32, 42), try mem0.read(u32, 0));
    try std.testing.expectEqual(@as(u32, 100), try mem1.read(u32, 0));

    // Test cross-memory copy
    try mem0.fill(100, 0xAA, 16);
    try mgr.memoryCopy(1, 0, 0, 100, 16);

    const slice0 = try mem0.slice(100, 16);
    const slice1 = try mem1.slice(0, 16);
    try std.testing.expectEqualSlices(u8, slice0, slice1);
}
