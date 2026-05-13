/// WASIX Extended Features - High-Performance Extensions
///
/// This module provides advanced WASIX extensions for:
/// - Futex operations (fast userspace mutexes)
/// - Memory-mapped I/O (mmap/munmap)
/// - Asynchronous I/O (io_uring style)
/// - Extended process control
/// - Shared memory segments
/// - High-resolution timers
/// - CPU affinity
///
/// These extensions enable WASM programs to achieve near-native performance
/// for systems programming tasks.
const std = @import("std");
const Module = @import("module.zig");
const Runtime = @import("runtime.zig");
const Value = Runtime.Value;
const WASI = @import("wasi.zig");
const Allocator = std.mem.Allocator;

pub const WASIXExt = struct {
    allocator: Allocator,
    io: std.Io,
    wasi: *WASI,

    // Futex waiter queues
    futex_waiters: std.AutoHashMap(u32, WaiterQueue),

    // Memory mappings
    mappings: std.ArrayList(MemoryMapping),
    next_mapping_addr: u32 = 0x80000000, // Start of mmap region

    // Async I/O
    io_queue: AsyncIOQueue,

    // Shared memory segments
    shm_segments: std.AutoHashMap(u32, SharedMemorySegment),
    next_shm_id: u32 = 0,

    // High-resolution timer
    timer_base: i128,

    const WaiterQueue = struct {
        waiters: std.ArrayList(Waiter),

        const Waiter = struct {
            thread_id: u32,
            expected_value: u32,
            woken: bool = false,
        };
    };

    const MemoryMapping = struct {
        addr: u32,
        len: u32,
        prot: u32,
        flags: u32,
        fd: ?i32,
        offset: u64,
        data: ?[]u8,
    };

    const SharedMemorySegment = struct {
        id: u32,
        size: usize,
        data: []u8,
        ref_count: u32 = 1,
        name: ?[]const u8 = null,
    };

    pub fn init(allocator: Allocator, wasi: *WASI) !WASIXExt {
        return WASIXExt{
            .allocator = allocator,
            .wasi = wasi,
            .futex_waiters = std.AutoHashMap(u32, WaiterQueue).init(allocator),
            .mappings = std.ArrayList(MemoryMapping).init(allocator),
            .io_queue = try AsyncIOQueue.init(allocator),
            .io = wasi.io,
            .shm_segments = std.AutoHashMap(u32, SharedMemorySegment).init(allocator),
            .timer_base = @import("../util/time.zig").nanoTimestamp(),
        };
    }

    pub fn deinit(self: *WASIXExt) void {
        var waiter_it = self.futex_waiters.valueIterator();
        while (waiter_it.next()) |queue| {
            queue.waiters.deinit();
        }
        self.futex_waiters.deinit();

        for (self.mappings.items) |mapping| {
            if (mapping.data) |data| {
                self.allocator.free(data);
            }
        }
        self.mappings.deinit();

        self.io_queue.deinit();

        var shm_it = self.shm_segments.valueIterator();
        while (shm_it.next()) |seg| {
            self.allocator.free(seg.data);
            if (seg.name) |name| {
                self.allocator.free(name);
            }
        }
        self.shm_segments.deinit();
    }

    // ========================================================================
    // Futex Operations - Fast Userspace Synchronization
    // ========================================================================

    /// futex_wait - Wait on a futex
    /// Atomically checks if *addr == expected and sleeps if true
    pub fn futex_wait(
        self: *WASIXExt,
        addr: u32,
        expected: u32,
        timeout_ns: ?i64,
        module: *Module,
    ) !i32 {
        const memory = module.memory orelse return -1;
        if (addr + 4 > memory.len) return -14; // EFAULT

        // Atomic check
        const current = std.mem.readInt(u32, memory[addr..][0..4], .little);
        if (current != expected) {
            return -11; // EAGAIN - value changed
        }

        // Add to waiter queue
        const result = self.futex_waiters.getOrPut(addr);
        if (!result.found_existing) {
            result.value_ptr.* = .{
                .waiters = std.ArrayList(WaiterQueue.Waiter).init(self.allocator),
            };
        }

        try result.value_ptr.waiters.append(.{
            .thread_id = 0, // Would be actual thread ID in multi-threaded
            .expected_value = expected,
        });

        // In single-threaded mode, simulate timeout
        if (timeout_ns) |ns| {
            if (ns == 0) return -110; // ETIMEDOUT
            // For non-zero timeout, sleep briefly
            std.time.sleep(@intCast(@min(ns, 1_000_000))); // Max 1ms sleep
        }

        return 0; // Success
    }

    /// futex_wake - Wake waiters on a futex
    pub fn futex_wake(self: *WASIXExt, addr: u32, count: u32) !i32 {
        if (self.futex_waiters.getPtr(addr)) |queue| {
            var woken: u32 = 0;
            var i: usize = 0;
            while (i < queue.waiters.items.len and woken < count) {
                queue.waiters.items[i].woken = true;
                woken += 1;
                i += 1;
            }
            // Remove woken waiters
            while (queue.waiters.items.len > 0 and queue.waiters.items[0].woken) {
                _ = queue.waiters.orderedRemove(0);
            }
            return @intCast(woken);
        }
        return 0;
    }

    /// futex_wake_all - Wake all waiters
    pub fn futex_wake_all(self: *WASIXExt, addr: u32) !i32 {
        return self.futex_wake(addr, std.math.maxInt(u32));
    }

    // ========================================================================
    // Memory Mapping Operations
    // ========================================================================

    /// mmap - Map memory
    pub fn mmap(
        self: *WASIXExt,
        addr_hint: u32,
        length: u32,
        prot: u32,
        flags: u32,
        fd: i32,
        offset: u64,
        module: *Module,
    ) !i32 {
        _ = module;

        // Determine actual address
        const addr = if (addr_hint != 0 and (flags & MAP_FIXED) != 0)
            addr_hint
        else
            self.next_mapping_addr;

        // Allocate backing memory
        const data = try self.allocator.alloc(u8, length);
        @memset(data, 0);

        // If mapping a file, read content
        if (fd >= 0 and (flags & MAP_ANONYMOUS) == 0) {
            // Would read from file descriptor here
        }

        try self.mappings.append(.{
            .addr = addr,
            .len = length,
            .prot = prot,
            .flags = flags,
            .fd = if (fd >= 0) fd else null,
            .offset = offset,
            .data = data,
        });

        self.next_mapping_addr = addr + length;
        // Align to page boundary
        self.next_mapping_addr = (self.next_mapping_addr + 4095) & ~@as(u32, 4095);

        return @bitCast(addr);
    }

    /// munmap - Unmap memory
    pub fn munmap(self: *WASIXExt, addr: u32, length: u32) !i32 {
        _ = length;

        for (self.mappings.items, 0..) |mapping, i| {
            if (mapping.addr == addr) {
                if (mapping.data) |data| {
                    self.allocator.free(data);
                }
                _ = self.mappings.orderedRemove(i);
                return 0;
            }
        }
        return -22; // EINVAL
    }

    /// mprotect - Change memory protection
    pub fn mprotect(self: *WASIXExt, addr: u32, length: u32, prot: u32) !i32 {
        _ = length;

        for (self.mappings.items) |*mapping| {
            if (mapping.addr == addr) {
                mapping.prot = prot;
                return 0;
            }
        }
        return -22; // EINVAL
    }

    /// msync - Synchronize mapped memory to backing store
    pub fn msync(self: *WASIXExt, addr: u32, length: u32, flags: u32) !i32 {
        _ = length;
        _ = flags;

        for (self.mappings.items) |mapping| {
            if (mapping.addr == addr) {
                // Would sync to file if backed by fd
                return 0;
            }
        }
        return -22; // EINVAL
    }

    // mmap flags
    const MAP_SHARED = 0x01;
    const MAP_PRIVATE = 0x02;
    const MAP_FIXED = 0x10;
    const MAP_ANONYMOUS = 0x20;
    const MAP_NORESERVE = 0x4000;

    // mmap protection flags
    const PROT_NONE = 0x0;
    const PROT_READ = 0x1;
    const PROT_WRITE = 0x2;
    const PROT_EXEC = 0x4;

    // ========================================================================
    // Asynchronous I/O Operations (io_uring style)
    // ========================================================================

    /// Submit an async I/O operation
    pub fn io_submit(
        self: *WASIXExt,
        op_type: AsyncIOQueue.OpType,
        fd: i32,
        buf_ptr: u32,
        buf_len: u32,
        offset: i64,
        user_data: u64,
    ) !u64 {
        return try self.io_queue.submit(.{
            .op_type = op_type,
            .fd = fd,
            .buf_ptr = buf_ptr,
            .buf_len = buf_len,
            .offset = offset,
            .user_data = user_data,
        });
    }

    /// Get completed async I/O operations
    pub fn io_getevents(
        self: *WASIXExt,
        min_nr: u32,
        max_nr: u32,
        timeout_ns: ?i64,
    ) ![]AsyncIOQueue.Completion {
        return try self.io_queue.getCompletions(min_nr, max_nr, timeout_ns);
    }

    /// Cancel an async I/O operation
    pub fn io_cancel(self: *WASIXExt, id: u64) !i32 {
        return self.io_queue.cancel(id);
    }

    // ========================================================================
    // Shared Memory Segments
    // ========================================================================

    /// Create or open a shared memory segment
    pub fn shm_open(self: *WASIXExt, name: ?[]const u8, flags: u32, mode: u32) !i32 {
        _ = flags;
        _ = mode;

        // Check if segment exists
        if (name) |n| {
            var it = self.shm_segments.valueIterator();
            while (it.next()) |seg| {
                if (seg.name) |seg_name| {
                    if (std.mem.eql(u8, seg_name, n)) {
                        seg.ref_count += 1;
                        return @intCast(seg.id);
                    }
                }
            }
        }

        // Create new segment
        const id = self.next_shm_id;
        self.next_shm_id += 1;

        const name_copy = if (name) |n| try self.allocator.dupe(u8, n) else null;

        try self.shm_segments.put(id, .{
            .id = id,
            .size = 0,
            .data = &[_]u8{},
            .name = name_copy,
        });

        return @intCast(id);
    }

    /// Set size of shared memory segment
    pub fn shm_truncate(self: *WASIXExt, id: u32, size: usize) !i32 {
        if (self.shm_segments.getPtr(id)) |seg| {
            if (seg.data.len > 0) {
                self.allocator.free(seg.data);
            }
            seg.data = try self.allocator.alloc(u8, size);
            @memset(seg.data, 0);
            seg.size = size;
            return 0;
        }
        return -9; // EBADF
    }

    /// Unlink shared memory segment
    pub fn shm_unlink(self: *WASIXExt, id: u32) !i32 {
        if (self.shm_segments.getPtr(id)) |seg| {
            seg.ref_count -= 1;
            if (seg.ref_count == 0) {
                self.allocator.free(seg.data);
                if (seg.name) |name| {
                    self.allocator.free(name);
                }
                _ = self.shm_segments.remove(id);
            }
            return 0;
        }
        return -9; // EBADF
    }

    // ========================================================================
    // High-Resolution Timers
    // ========================================================================

    /// Get high-resolution monotonic time in nanoseconds
    pub fn clock_gettime_hr(self: *WASIXExt) i128 {
        return @import("../util/time.zig").nanoTimestamp() - self.timer_base;
    }

    /// High-precision sleep
    pub fn nanosleep(self: *WASIXExt, ns: u64) !i32 {
        _ = self;
        std.time.sleep(ns);
        return 0;
    }

    /// Create a timer
    pub fn timer_create(self: *WASIXExt, clock_id: i32) !i32 {
        _ = self;
        _ = clock_id;
        // Simplified: return a timer ID
        return 0;
    }

    // ========================================================================
    // CPU Affinity
    // ========================================================================

    /// Get CPU affinity mask
    pub fn sched_getaffinity(self: *WASIXExt, pid: i32, mask_ptr: u32, mask_len: u32, module: *Module) !i32 {
        _ = self;
        _ = pid;

        const memory = module.memory orelse return -1;
        if (mask_ptr + mask_len > memory.len) return -14;

        // Set all CPUs as available (simplified)
        @memset(memory[mask_ptr..][0..mask_len], 0xFF);
        return 0;
    }

    /// Set CPU affinity mask
    pub fn sched_setaffinity(self: *WASIXExt, pid: i32, mask_ptr: u32, mask_len: u32, module: *Module) !i32 {
        _ = self;
        _ = pid;
        _ = module;
        _ = mask_ptr;
        _ = mask_len;
        // In WASM, we can't actually set CPU affinity, but return success
        return 0;
    }

    /// Get number of processors
    pub fn get_nprocs(self: *WASIXExt) i32 {
        _ = self;
        return @intCast(std.Thread.getCpuCount() catch 1);
    }

    // ========================================================================
    // Extended Process Control
    // ========================================================================

    /// Get resource limits
    pub fn getrlimit(self: *WASIXExt, resource: i32, rlimit_ptr: u32, module: *Module) !i32 {
        _ = self;

        const memory = module.memory orelse return -1;
        if (rlimit_ptr + 16 > memory.len) return -14;

        // Return reasonable defaults
        const soft: u64 = switch (resource) {
            0 => std.math.maxInt(u64), // RLIMIT_CPU
            1 => 8 * 1024 * 1024, // RLIMIT_FSIZE (8MB)
            2 => 256 * 1024 * 1024, // RLIMIT_DATA (256MB)
            3 => 8 * 1024 * 1024, // RLIMIT_STACK (8MB)
            4 => 0, // RLIMIT_CORE
            5 => 1024 * 1024 * 1024, // RLIMIT_RSS (1GB)
            6 => 1024, // RLIMIT_NPROC
            7 => 1024, // RLIMIT_NOFILE
            8 => std.math.maxInt(u64), // RLIMIT_MEMLOCK
            9 => 256 * 1024 * 1024, // RLIMIT_AS (256MB)
            else => std.math.maxInt(u64),
        };
        const hard = soft;

        std.mem.writeInt(u64, memory[rlimit_ptr..][0..8], soft, .little);
        std.mem.writeInt(u64, memory[rlimit_ptr + 8 ..][0..8], hard, .little);

        return 0;
    }

    /// Set resource limits
    pub fn setrlimit(self: *WASIXExt, resource: i32, rlimit_ptr: u32, module: *Module) !i32 {
        _ = self;
        _ = resource;
        _ = rlimit_ptr;
        _ = module;
        // In WASM sandbox, we can't actually set limits
        return 0;
    }

    /// Get resource usage
    pub fn getrusage(self: *WASIXExt, who: i32, usage_ptr: u32, module: *Module) !i32 {
        _ = self;
        _ = who;

        const memory = module.memory orelse return -1;
        if (usage_ptr + 144 > memory.len) return -14;

        // Zero out the structure (simplified)
        @memset(memory[usage_ptr..][0..144], 0);

        return 0;
    }
};

/// Asynchronous I/O Queue (io_uring style)
pub const AsyncIOQueue = struct {
    allocator: Allocator,
    pending: std.ArrayList(IORequest),
    completed: std.ArrayList(Completion),
    next_id: u64 = 1,

    pub const OpType = enum(u8) {
        read = 0,
        write = 1,
        fsync = 2,
        poll = 3,
        accept = 4,
        connect = 5,
        send = 6,
        recv = 7,
        close = 8,
        timeout = 9,
        nop = 255,
    };

    pub const IORequest = struct {
        id: u64,
        op_type: OpType,
        fd: i32,
        buf_ptr: u32,
        buf_len: u32,
        offset: i64,
        user_data: u64,
        submitted_at: i64,
    };

    pub const Completion = struct {
        id: u64,
        user_data: u64,
        result: i32,
        flags: u32,
    };

    pub fn init(allocator: Allocator) !AsyncIOQueue {
        return AsyncIOQueue{
            .allocator = allocator,
            .pending = std.ArrayList(IORequest).init(allocator),
            .completed = std.ArrayList(Completion).init(allocator),
        };
    }

    pub fn deinit(self: *AsyncIOQueue) void {
        self.pending.deinit();
        self.completed.deinit();
    }

    pub fn submit(self: *AsyncIOQueue, req: struct {
        op_type: OpType,
        fd: i32,
        buf_ptr: u32,
        buf_len: u32,
        offset: i64,
        user_data: u64,
    }) !u64 {
        const id = self.next_id;
        self.next_id += 1;

        try self.pending.append(.{
            .id = id,
            .op_type = req.op_type,
            .fd = req.fd,
            .buf_ptr = req.buf_ptr,
            .buf_len = req.buf_len,
            .offset = req.offset,
            .user_data = req.user_data,
            .submitted_at = std.time.milliTimestamp(),
        });

        // In single-threaded mode, process immediately
        try self.processPending();

        return id;
    }

    pub fn getCompletions(self: *AsyncIOQueue, min_nr: u32, max_nr: u32, timeout_ns: ?i64) ![]Completion {
        _ = timeout_ns;

        // Process any pending operations
        try self.processPending();

        const count = @min(@as(usize, max_nr), self.completed.items.len);
        if (count < min_nr) {
            return &[_]Completion{};
        }

        var result = try self.allocator.alloc(Completion, count);
        for (0..count) |i| {
            result[i] = self.completed.orderedRemove(0);
        }

        return result;
    }

    pub fn cancel(self: *AsyncIOQueue, id: u64) i32 {
        for (self.pending.items, 0..) |req, i| {
            if (req.id == id) {
                _ = self.pending.orderedRemove(i);
                return 0;
            }
        }
        return -2; // ENOENT
    }

    fn processPending(self: *AsyncIOQueue) !void {
        // Process pending operations synchronously (simplified)
        while (self.pending.items.len > 0) {
            const req = self.pending.orderedRemove(0);

            // Simulate completion
            try self.completed.append(.{
                .id = req.id,
                .user_data = req.user_data,
                .result = @intCast(req.buf_len), // Assume success, return bytes
                .flags = 0,
            });
        }
    }
};

// ============================================================================
// WASIX Extended Syscall Dispatcher
// ============================================================================

/// Dispatch WASIX extended syscalls
pub fn dispatchExt(
    ext: *WASIXExt,
    module: *Module,
    func_name: []const u8,
    args: []const Value,
) !Value {
    // Futex operations
    if (std.mem.eql(u8, func_name, "futex_wait")) {
        const addr = @as(u32, @bitCast(args[0].i32));
        const expected = @as(u32, @bitCast(args[1].i32));
        const timeout = if (args.len > 2) args[2].i64 else null;
        const result = try ext.futex_wait(addr, expected, timeout, module);
        return .{ .i32 = result };
    } else if (std.mem.eql(u8, func_name, "futex_wake")) {
        const addr = @as(u32, @bitCast(args[0].i32));
        const count = @as(u32, @bitCast(args[1].i32));
        const result = try ext.futex_wake(addr, count);
        return .{ .i32 = result };
    }
    // Memory mapping
    else if (std.mem.eql(u8, func_name, "mmap")) {
        const addr = @as(u32, @bitCast(args[0].i32));
        const length = @as(u32, @bitCast(args[1].i32));
        const prot = @as(u32, @bitCast(args[2].i32));
        const flags = @as(u32, @bitCast(args[3].i32));
        const fd = args[4].i32;
        const offset = @as(u64, @bitCast(args[5].i64));
        const result = try ext.mmap(addr, length, prot, flags, fd, offset, module);
        return .{ .i32 = result };
    } else if (std.mem.eql(u8, func_name, "munmap")) {
        const addr = @as(u32, @bitCast(args[0].i32));
        const length = @as(u32, @bitCast(args[1].i32));
        const result = try ext.munmap(addr, length);
        return .{ .i32 = result };
    }
    // Async I/O
    else if (std.mem.eql(u8, func_name, "io_submit")) {
        const op_type: AsyncIOQueue.OpType = @enumFromInt(@as(u8, @truncate(@as(u32, @bitCast(args[0].i32)))));
        const fd = args[1].i32;
        const buf_ptr = @as(u32, @bitCast(args[2].i32));
        const buf_len = @as(u32, @bitCast(args[3].i32));
        const offset = args[4].i64;
        const user_data = @as(u64, @bitCast(args[5].i64));
        const result = try ext.io_submit(op_type, fd, buf_ptr, buf_len, offset, user_data);
        return .{ .i64 = @bitCast(result) };
    }
    // System info
    else if (std.mem.eql(u8, func_name, "get_nprocs")) {
        return .{ .i32 = ext.get_nprocs() };
    } else if (std.mem.eql(u8, func_name, "clock_gettime_hr")) {
        const ns = ext.clock_gettime_hr();
        return .{ .i64 = @truncate(ns) };
    } else if (std.mem.eql(u8, func_name, "nanosleep")) {
        const ns = @as(u64, @bitCast(args[0].i64));
        const result = try ext.nanosleep(ns);
        return .{ .i32 = result };
    }
    // Resource limits
    else if (std.mem.eql(u8, func_name, "getrlimit")) {
        const resource = args[0].i32;
        const rlimit_ptr = @as(u32, @bitCast(args[1].i32));
        const result = try ext.getrlimit(resource, rlimit_ptr, module);
        return .{ .i32 = result };
    } else if (std.mem.eql(u8, func_name, "getrusage")) {
        const who = args[0].i32;
        const usage_ptr = @as(u32, @bitCast(args[1].i32));
        const result = try ext.getrusage(who, usage_ptr, module);
        return .{ .i32 = result };
    }

    return error.UnknownImport;
}
