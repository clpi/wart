const std = @import("std");
const posix = std.posix;
const builtin = @import("builtin");

/// WASIX Memory Mapping Support
/// Implements mmap, munmap, mprotect, madvise operations
pub const MmapError = error{
    PermissionDenied,
    InvalidAddress,
    InvalidLength,
    OutOfMemory,
    FileDescriptorInvalid,
    NotSupported,
    AddressInUse,
};

pub const ProtectionFlags = packed struct {
    read: bool = false,
    write: bool = false,
    exec: bool = false,
    _padding: u29 = 0,

    pub fn toNative(self: ProtectionFlags) u32 {
        var prot: u32 = 0;
        if (builtin.os.tag != .windows) {
            if (self.read) prot |= posix.PROT.READ;
            if (self.write) prot |= posix.PROT.WRITE;
            if (self.exec) prot |= posix.PROT.EXEC;
        }
        return prot;
    }

    pub fn none() ProtectionFlags {
        return .{};
    }

    pub fn readOnly() ProtectionFlags {
        return .{ .read = true };
    }

    pub fn readWrite() ProtectionFlags {
        return .{ .read = true, .write = true };
    }

    pub fn readExec() ProtectionFlags {
        return .{ .read = true, .exec = true };
    }
};

pub const MapFlags = packed struct {
    shared: bool = false,
    private: bool = true,
    fixed: bool = false,
    anonymous: bool = false,
    populate: bool = false,
    locked: bool = false,
    _padding: u26 = 0,

    pub fn toNative(self: MapFlags) u32 {
        var flags: u32 = 0;
        if (builtin.os.tag != .windows) {
            if (self.shared) flags |= posix.MAP.SHARED;
            if (self.private) flags |= posix.MAP.PRIVATE;
            if (self.fixed) flags |= posix.MAP.FIXED;
            if (self.anonymous) flags |= posix.MAP.ANONYMOUS;
            // populate and locked are Linux-specific
            if (builtin.os.tag == .linux) {
                if (self.populate) flags |= 0x008000; // MAP_POPULATE
                if (self.locked) flags |= 0x002000; // MAP_LOCKED
            }
        }
        return flags;
    }
};

pub const AdviceFlags = enum(u32) {
    normal = 0,
    random = 1,
    sequential = 2,
    willneed = 3,
    dontneed = 4,
    free = 5, // Linux only
    remove = 6, // Linux only
    dontfork = 7, // Linux only
    dofork = 8, // Linux only
    hwpoison = 9, // Linux only
    mergeable = 10, // Linux only
    unmergeable = 11, // Linux only

    pub fn toNative(self: AdviceFlags) i32 {
        if (builtin.os.tag == .linux) {
            return switch (self) {
                .normal => 0,
                .random => 1,
                .sequential => 2,
                .willneed => 3,
                .dontneed => 4,
                .free => 8,
                .remove => 9,
                .dontfork => 10,
                .dofork => 11,
                .hwpoison => 100,
                .mergeable => 12,
                .unmergeable => 13,
            };
        } else if (builtin.os.tag.isDarwin()) {
            return switch (self) {
                .normal => 0,
                .random => 1,
                .sequential => 2,
                .willneed => 3,
                .dontneed => 4,
                else => 0,
            };
        }
        return 0;
    }
};

pub const MmapRegion = struct {
    address: [*]u8,
    length: usize,
    protection: ProtectionFlags,

    pub fn asSlice(self: MmapRegion) []u8 {
        return self.address[0..self.length];
    }
};

/// Memory mapping manager
pub const Mmap = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    regions: std.AutoHashMap(usize, MmapRegion),

    pub fn init(allocator: std.mem.Allocator) !Self {
        return Self{
            .allocator = allocator,
            .regions = std.AutoHashMap(usize, MmapRegion).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        // Unmap all remaining regions
        var it = self.regions.iterator();
        while (it.next()) |entry| {
            self.munmap(entry.value_ptr.address, entry.value_ptr.length) catch {};
        }
        self.regions.deinit();
    }

    /// Map memory region
    pub fn mmap(
        self: *Self,
        addr: ?[*]u8,
        length: usize,
        prot: ProtectionFlags,
        flags: MapFlags,
        fd: ?std.posix.fd_t,
        offset: i64,
    ) !MmapRegion {
        if (length == 0) return error.InvalidLength;

        if (builtin.os.tag == .windows) {
            // Windows VirtualAlloc implementation
            return error.NotSupported; // Simplified for now
        }

        const result = posix.mmap(
            addr,
            length,
            prot.toNative(),
            flags.toNative(),
            fd orelse -1,
            @intCast(offset),
        ) catch |err| {
            return switch (err) {
                error.MemoryMappingNotSupported => error.NotSupported,
                error.AccessDenied => error.PermissionDenied,
                error.OutOfMemory => error.OutOfMemory,
                else => error.InvalidAddress,
            };
        };

        const region = MmapRegion{
            .address = @ptrCast(result.ptr),
            .length = length,
            .protection = prot,
        };

        try self.regions.put(@intFromPtr(result.ptr), region);

        return region;
    }

    /// Unmap memory region
    pub fn munmap(self: *Self, addr: [*]u8, length: usize) !void {
        if (length == 0) return error.InvalidLength;

        if (builtin.os.tag == .windows) {
            return error.NotSupported;
        }

        posix.munmap(@alignCast(addr[0..length]));

        _ = self.regions.remove(@intFromPtr(addr));
    }

    /// Change protection on memory region
    pub fn mprotect(self: *Self, addr: [*]u8, length: usize, prot: ProtectionFlags) !void {
        if (length == 0) return error.InvalidLength;

        if (builtin.os.tag == .windows) {
            return error.NotSupported;
        }

        posix.mprotect(@alignCast(addr[0..length]), prot.toNative()) catch |err| {
            return switch (err) {
                error.OutOfMemory => error.OutOfMemory,
                error.AccessDenied => error.PermissionDenied,
                else => error.InvalidAddress,
            };
        };

        // Update region protection in tracking
        if (self.regions.getPtr(@intFromPtr(addr))) |region| {
            region.protection = prot;
        }
    }

    /// Give advice about memory usage patterns
    pub fn madvise(self: *Self, addr: [*]u8, length: usize, advice: AdviceFlags) !void {
        _ = self;
        if (length == 0) return error.InvalidLength;

        if (builtin.os.tag == .windows) {
            return error.NotSupported;
        }

        if (builtin.os.tag == .linux) {
            const rc = std.os.linux.madvise(@intFromPtr(addr), length, @intCast(advice.toNative()));
            if (rc != 0) {
                return error.InvalidAddress;
            }
        }
    }

    /// Synchronize mapped region to disk
    pub fn msync(self: *Self, addr: [*]u8, length: usize, async_sync: bool) !void {
        _ = self;
        if (length == 0) return error.InvalidLength;

        if (builtin.os.tag == .windows) {
            return error.NotSupported;
        }

        const flags: u32 = if (async_sync) posix.MSF.ASYNC else posix.MSF.SYNC;

        posix.msync(@alignCast(addr[0..length]), flags) catch {
            return error.InvalidAddress;
        };
    }

    /// Lock pages in memory (prevent swapping)
    pub fn mlock(self: *Self, addr: [*]u8, length: usize) !void {
        _ = self;
        if (length == 0) return error.InvalidLength;

        if (builtin.os.tag == .windows) {
            return error.NotSupported;
        }

        if (builtin.os.tag == .linux) {
            const rc = std.os.linux.mlock(@intFromPtr(addr), length);
            if (rc != 0) {
                return error.PermissionDenied;
            }
        }
    }

    /// Unlock pages from memory
    pub fn munlock(self: *Self, addr: [*]u8, length: usize) !void {
        _ = self;
        if (length == 0) return error.InvalidLength;

        if (builtin.os.tag == .windows) {
            return error.NotSupported;
        }

        if (builtin.os.tag == .linux) {
            const rc = std.os.linux.munlock(@intFromPtr(addr), length);
            if (rc != 0) {
                return error.InvalidAddress;
            }
        }
    }

    /// Create anonymous memory mapping (no file backing)
    pub fn mmapAnonymous(self: *Self, length: usize, prot: ProtectionFlags) !MmapRegion {
        return try self.mmap(
            null,
            length,
            prot,
            .{ .private = true, .anonymous = true },
            null,
            0,
        );
    }

    /// Create shared memory mapping
    pub fn mmapShared(self: *Self, fd: std.posix.fd_t, length: usize, prot: ProtectionFlags, offset: i64) !MmapRegion {
        return try self.mmap(
            null,
            length,
            prot,
            .{ .shared = true, .private = false },
            fd,
            offset,
        );
    }
};

/// Create memory file descriptor (Linux memfd_create)
pub fn memfdCreate(name: []const u8, flags: u32) !std.posix.fd_t {
    if (builtin.os.tag != .linux) {
        return error.NotSupported;
    }

    const rc = std.os.linux.memfd_create(name.ptr, flags);
    if (rc < 0) {
        return error.PermissionDenied;
    }

    return @intCast(rc);
}

// Tests
test "Mmap anonymous" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    var mmap = try Mmap.init(std.testing.allocator);
    defer mmap.deinit();

    const region = try mmap.mmapAnonymous(4096, .{ .read = true, .write = true });

    // Write to the region
    const slice = region.asSlice();
    @memset(slice, 42);

    // Verify
    try std.testing.expectEqual(@as(u8, 42), slice[0]);
    try std.testing.expectEqual(@as(u8, 42), slice[4095]);

    try mmap.munmap(region.address, region.length);
}

test "Mmap protection change" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    var mmap = try Mmap.init(std.testing.allocator);
    defer mmap.deinit();

    const region = try mmap.mmapAnonymous(4096, .{ .read = true, .write = true });
    defer mmap.munmap(region.address, region.length) catch {};

    // Change to read-only
    try mmap.mprotect(region.address, region.length, .{ .read = true });
}
