const std = @import("std");
const Io = std.Io;

const Module = @import("module.zig");
const Value = @import("value.zig").Value;
const ValueType = @import("value.zig").Type;
const Runtime = @import("runtime.zig").Runtime;

// Error definitions for ESM loader
pub const ESMError = error{
    ModuleNotFound,
    ModuleNotLoaded,
    ExportNotFound,
    ImportResolutionFailed,
    InvalidModuleSpecifier,
    ModuleAlreadyLoaded,
    ComponentNotLoaded,
};

// WebAssembly Component Model Implementation
// Based on https://github.com/WebAssembly/component-model

// Component Types (Interface Types)
pub const ComponentType = struct {
    tag: ComponentTypeTag,
    payload: Payload,

    const Self = @This();

    pub const Record = struct {
        fields: []Field,

        pub const Field = struct {
            name: []u8,
            ty_idx: u32, // Index into component.types
        };
    };

    pub const Variant = struct {
        cases: []Case,

        pub const Case = struct {
            name: []u8,
            ty_idx: ?u32, // Index into component.types, null if no type
        };
    };

    pub const Result = struct {
        ok: ?u32, // Index into component.types, null if no type
        err: ?u32, // Index into component.types, null if no type
    };

    pub const Payload = union(enum) {
        // Primitive types
        bool: void,
        s8: void,
        u8: void,
        s16: void,
        u16: void,
        s32: void,
        u32: void,
        s64: void,
        u64: void,
        float32: void,
        float64: void,
        char: void,
        string: void,

        // Composite types (simplified for now)
        record: Record,
        variant: Variant,
        list: void,
        tuple: void,
        flags: []u8, // Field names as UTF-8
        @"enum": []u8, // Variant names as UTF-8
        @"union": void,
        option: void,
        result: Result,
        own: u32, // Resource type index
        borrow: u32, // Resource type index
    };

    pub const ComponentTypeTag = enum {
        // Primitive types
        bool,
        s8,
        u8,
        s16,
        u16,
        s32,
        u32,
        s64,
        u64,
        float32,
        float64,
        char,
        string,

        // Composite types
        record,
        variant,
        list,
        tuple,
        flags,
        @"enum",
        @"union",
        option,
        result,
        own,
        borrow,
    };

    pub fn deinit(self: *ComponentType, allocator: std.mem.Allocator) void {
        switch (self.payload) {
            .record => |r| {
                for (r.fields) |*f| {
                    allocator.free(f.name);
                }
                allocator.free(r.fields);
            },
            .variant => |v| {
                for (v.cases) |*c| {
                    allocator.free(c.name);
                }
                allocator.free(v.cases);
            },
            .flags => |f| allocator.free(f),
            .@"enum" => |e| allocator.free(e),
            .result => |r| {
                // Types are stored by index, no deinit needed here
                _ = r;
            },
            // Primitive types have no allocated data
            .bool, .s8, .u8, .s16, .u16, .s32, .u32, .s64, .u64, .float32, .float64, .char, .string => {},
            .list, .tuple, .@"union", .option => {},
            .own, .borrow => {},
        }
    }
};

// Core module support types
pub const FunctionType = struct {
    params: []ValueType,
    results: []ValueType,

    pub fn deinit(self: *FunctionType, allocator: std.mem.Allocator) void {
        allocator.free(self.params);
        allocator.free(self.results);
    }
};

pub const CoreInstance = struct {
    module_idx: u32,
    exports: std.StringHashMap(ComponentValue),
};

pub const CoreAlias = union(enum) {
    type: u32,
    module: u32,
    instance: u32,
    function: u32,
    table: u32,
    memory: u32,
    global: u32,
};

// WASI Resource Management
pub const ResourceTable = struct {
    const Self = @This();

    io: std.Io,
    allocator: std.mem.Allocator,
    handles: std.ArrayList(u32), // WASI handles
    resource_types: std.ArrayList(ResourceType),

    pub const ResourceType = enum {
        file,
        directory,
        socket,
        stream,
        // Add more WASI resource types as needed
    };

    pub fn init(allocator: std.mem.Allocator, io: std.Io) !Self {
        return Self{
            .io = io,
            .allocator = allocator,
            .handles = try std.ArrayList(u32).initCapacity(allocator, 0),
            .resource_types = try std.ArrayList(ResourceType).initCapacity(allocator, 0),
        };
    }

    pub fn deinit(self: *Self) void {
        self.handles.deinit(self.allocator);
        self.resource_types.deinit(self.allocator);
    }

    pub fn addResource(self: *Self, resource_type: ResourceType, handle: u32) !u32 {
        try self.handles.append(self.allocator, handle);
        try self.resource_types.append(self.allocator, resource_type);
        return @intCast(self.handles.items.len - 1);
    }

    pub fn getHandle(self: *Self, index: u32) ?u32 {
        if (index >= self.handles.items.len) return null;
        return self.handles.items[index];
    }

    pub fn getResourceType(self: *Self, index: u32) ?ResourceType {
        if (index >= self.resource_types.items.len) return null;
        return self.resource_types.items[index];
    }

    pub fn removeResource(self: *Self, index: u32) !void {
        if (index >= self.handles.items.len) return error.InvalidIndex;

        const handle = self.handles.items[index];
        const resource_type = self.resource_types.items[index];

        // Call appropriate WASI.close(io) function
        switch (resource_type) {
            .file => {
                // WASI fd_close(.{.userdata=null, .vtable=undefined})
                _ = handle; // Would call WASI fd_close(.{.userdata=null, .vtable=undefined})
            },
            .directory => {
                // Directory handles don't need explicit closing in WASI
            },
            .socket => {
                // WASI sock.close(io)
                _ = handle; // Would call WASI sock.close(io)
            },
            .stream => {
                // Stream closing
                _ = handle; // Would call appropriate.close(io)
            },
        }

        // Remove from arrays
        _ = self.handles.orderedRemove(index);
        _ = self.resource_types.orderedRemove(index);
    }

    // WASI syscall implementations
    pub fn wasiPathOpen(self: *Self, dirfd: u32, dirflags: u32, path: []const u8, oflags: u32, fs_rights_base: u64, fs_rights_inheriting: u64, fdflags: u32) !u32 {
        // Simplified WASI path_open implementation
        _ = dirfd;
        _ = dirflags;
        _ = oflags;
        _ = fs_rights_base;
        _ = fs_rights_inheriting;
        _ = fdflags;

        const io = self.io;
        // For now, just try to open the file with read access
        const file = try std.Io.Dir.cwd().openFile(io, path, .{ .mode = .read_only });

        const handle = @as(u32, @intCast(file.handle));

        // Store in resource table
        try self.addResource(.file, handle);
        return @intCast(self.handles.items.len - 1);
    }

    pub fn wasiFdRead(self: *Self, fd: u32, iovs: []std.os.iovec_const, num_read: *usize) !void {
        // Implement WASI fd_read
        const handle = self.getHandle(fd) orelse return error.InvalidHandle;
        const file = std.Io.File{ .handle = @intCast(handle), .flags = .{ .nonblocking = false } };
        const io = self.io;

        // Read into iovs
        var total: usize = 0;
        for (iovs) |iov| {
            if (iov.iov_base == null) continue;
            const buf = @as([*]u8, @ptrCast(@constCast(iov.iov_base.?)))[0..iov.iov_len];
            const bytes = try file.readStreaming(io, &[_][]u8{buf});
            total += bytes;
            if (bytes < buf.len) break;
        }
        num_read.* = total;
    }

    pub fn wasiFdWrite(self: *Self, fd: u32, iovs: []std.os.iovec_const, num_written: *usize) !void {
        // Implement WASI fd_write
        const handle = self.getHandle(fd) orelse return error.InvalidHandle;
        const file = std.Io.File{ .handle = @intCast(handle), .flags = .{ .nonblocking = false } };
        const io = self.io;

        // Write from iovs
        var total: usize = 0;
        for (iovs) |iov| {
            if (iov.iov_base == null) continue;
            const buf = @as([*]const u8, @ptrCast(iov.iov_base.?))[0..iov.iov_len];
            try file.writeStreamingAll(io, buf);
            total += buf.len;
        }
        num_written.* = total;
    }

    pub fn wasiFdClose(self: *Self, fd: u32) !void {
        // Implement WASI fd_close(.{.userdata=null, .vtable=undefined})
        const handle = self.getHandle(fd) orelse return error.InvalidHandle;
        const file = std.Io.File{ .handle = @intCast(handle), .flags = .{ .nonblocking = false } };
        file.close(self.io);

        // Remove from resource table
        try self.removeResource(fd);
    }

    // Additional WASI Preview 2 syscalls
    pub fn wasiFdSeek(self: *Self, fd: u32, offset: i64, whence: u32) !u64 {
        // Implement WASI fd_seek
        const handle = self.getHandle(fd) orelse return error.InvalidHandle;
        const file = std.Io.File{ .handle = @intCast(handle), .flags = .{ .nonblocking = false } };

        const io = self.io;
        const new_pos: u64 = switch (whence) {
            0 => @intCast(offset),
            2 => (try io.vtable.fileLength(io.userdata, file)) + @as(u64, @intCast(offset)),
            else => return error.InvalidWhence,
        };
        try io.vtable.fileSeekTo(io.userdata, file, new_pos);
        return new_pos;
    }

    pub fn wasiFdTell(self: *Self, fd: u32) !u64 {
        const handle = self.getHandle(fd) orelse return error.InvalidType;
        const file = std.Io.File{ .handle = @intCast(handle), .flags = .{ .nonblocking = false } };
        const tell = try file.tell(self.io);
        return tell;
    }

    pub fn wasiFdFdstatGet(self: *Self, fd: u32) !FdStat {
        // Implement WASI fd_fdstat_get
        const handle = self.getHandle(fd) orelse return error.InvalidHandle;
        const file = std.Io.File{ .handle = @intCast(handle), .flags = .{ .nonblocking = false } };

        // Get file type and rights
        const stat = try file.stat(self.io);
        const file_type = switch (stat.kind) {
            .file => FileType.regular_file,
            .directory => FileType.directory,
            .character_device => FileType.character_device,
            .block_device => FileType.block_device,
            .named_pipe => FileType.fifo,
            .unix_domain_socket => FileType.socket_stream,
            .sym_link => FileType.symbolic_link,
            else => FileType.unknown,
        };

        return FdStat{
            .file_type = file_type,
            .flags = 0, // TODO: Get actual flags
            .rights_base = 0xFFFFFFFFFFFFFFFF, // TODO: Proper rights
            .rights_inheriting = 0xFFFFFFFFFFFFFFFF,
        };
    }

    pub fn wasiPathOpenResult(self: *Self, dirfd: u32, dirflags: u32, path: []const u8, oflags: u32, fs_rights_base: u64, fs_rights_inheriting: u64, fdflags: u32, result_fd: *u32) !void {
        // Enhanced path_open with result_fd parameter
        const fd = try self.wasiPathOpen(dirfd, dirflags, path, oflags, fs_rights_base, fs_rights_inheriting, fdflags);
        result_fd.* = fd;
    }

    pub fn wasiFdReadResult(self: *Self, fd: u32, iovs: []std.os.iovec, result_num_read: *usize) !void {
        // Enhanced fd_read with result parameter
        result_num_read.* = try self.wasiFdRead(fd, iovs, result_num_read);
    }

    pub fn wasiFdWriteResult(self: *Self, fd: u32, iovs: []std.os.iovec_const, result_num_written: *usize) !void {
        // Enhanced fd_write with result parameter
        result_num_written.* = try self.wasiFdWrite(fd, iovs, result_num_written);
    }

    pub fn wasiRandomGet(_: *Self, buf: []u8) !void {
        // Implement WASI random_get
        std.crypto.random.bytes(buf);
    }

    pub fn wasiClockTimeGet(_: *Self, clock_id: u32, precision: u64) !u64 {
        // Implement WASI clock_time_get
        _ = precision;
        const now = @import("../util/time.zig").nanoTimestamp();
        return switch (clock_id) {
            0 => @intCast(now), // CLOCK_REALTIME
            1 => @intCast(now), // CLOCK_MONOTONIC (simplified)
            else => return error.InvalidClockId,
        };
    }

    pub fn wasiEnvironGet(self: *Self, environ: *[*][*:0]u8, environ_buf: [*]u8) !void {
        // Implement WASI environ_get
        _ = self;
        _ = environ;
        _ = environ_buf;
        // TODO: Implement environment variable access
    }

    pub fn wasiEnvironSizesGet(self: *Self, environ_count: *usize, environ_buf_size: *usize) !void {
        // Implement WASI environ_sizes_get
        _ = self;
        environ_count.* = 0;
        environ_buf_size.* = 0;
        // TODO: Return actual environment sizes
    }

    pub fn wasiArgsGet(self: *Self, argv: *[*][*:0]u8, argv_buf: [*]u8) !void {
        // Implement WASI args_get
        _ = self;
        _ = argv;
        _ = argv_buf;
        // TODO: Implement command line argument access
    }

    pub fn wasiArgsSizesGet(self: *Self, argc: *usize, argv_buf_size: *usize) !void {
        // Implement WASI args_sizes_get
        _ = self;
        argc.* = 0;
        argv_buf_size.* = 0;
        // TODO: Return actual argument sizes
    }

    pub const FileType = enum(u8) {
        unknown = 0,
        block_device = 1,
        character_device = 2,
        directory = 3,
        fifo = 4,
        socket_stream = 5,
        socket_dgram = 6,
        file = 7,
        symbolic_link = 8,
        regular_file = 9,
    };

    pub const FdStat = struct {
        file_type: FileType,
        flags: u16,
        rights_base: u64,
        rights_inheriting: u64,
    };
};

pub const Component = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    types: std.ArrayList(ComponentType),
    imports: std.ArrayList(ComponentImport),
    exports: std.ArrayList(ComponentExport),
    instances: std.ArrayList(ComponentInstance),
    functions: std.ArrayList(u32),
    function_bodies: std.ArrayList(ComponentFunctionBody),
    start: ?u32,

    // Core module support
    core_types: std.ArrayList(FunctionType),
    core_modules: std.ArrayList(*Module),
    core_instances: std.ArrayList(CoreInstance),
    core_aliases: std.ArrayList(CoreAlias),
    core_start: ?u32,

    pub fn init(allocator: std.mem.Allocator) !Self {
        return Self{
            .allocator = allocator,
            .types = try std.ArrayList(ComponentType).initCapacity(allocator, 0),
            .imports = try std.ArrayList(ComponentImport).initCapacity(allocator, 0),
            .exports = try std.ArrayList(ComponentExport).initCapacity(allocator, 0),
            .instances = try std.ArrayList(ComponentInstance).initCapacity(allocator, 0),
            .functions = try std.ArrayList(u32).initCapacity(allocator, 0),
            .function_bodies = try std.ArrayList(ComponentFunctionBody).initCapacity(allocator, 0),
            .start = null,
            .core_types = try std.ArrayList(FunctionType).initCapacity(allocator, 0),
            .core_modules = try std.ArrayList(*Module).initCapacity(allocator, 0),
            .core_instances = try std.ArrayList(CoreInstance).initCapacity(allocator, 0),
            .core_aliases = try std.ArrayList(CoreAlias).initCapacity(allocator, 0),
            .core_start = null,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.types.items) |*t| t.deinit(self.allocator);
        self.types.deinit(self.allocator);

        for (self.imports.items) |*i| i.deinit(self.allocator);
        self.imports.deinit(self.allocator);

        for (self.exports.items) |*e| e.deinit(self.allocator);
        self.exports.deinit(self.allocator);

        for (self.instances.items) |*i| i.deinit();
        self.instances.deinit(self.allocator);

        self.functions.deinit(self.allocator);

        for (self.function_bodies.items) |*body| {
            body.deinit(self.allocator);
        }
        self.function_bodies.deinit(self.allocator);

        // Deinit core fields
        for (self.core_types.items) |*t| t.deinit(self.allocator);
        self.core_types.deinit(self.allocator);
        for (self.core_modules.items) |module| {
            module.deinit();
            self.allocator.destroy(module);
        }
        self.core_modules.deinit(self.allocator);
        for (self.core_instances.items) |*inst| {
            inst.exports.deinit();
        }
        self.core_instances.deinit(self.allocator);
        self.core_aliases.deinit(self.allocator);
    }

    // Validate that the component is well-formed
    pub fn validate(self: *const Self) !void {
        // Check that all type indices are valid
        for (self.imports.items) |import| {
            if (import.ty_idx >= self.types.items.len) return error.InvalidTypeIndex;
        }

        for (self.exports.items) |export_item| {
            if (export_item.ty_idx >= self.types.items.len) return error.InvalidTypeIndex;
        }

        for (self.functions.items) |ty_idx| {
            if (ty_idx >= self.types.items.len) return error.InvalidTypeIndex;
        }

        // Check start function index if present
        if (self.start) |start_idx| {
            if (start_idx >= self.functions.items.len) {
                return error.InvalidStartFunctionIndex;
            }
        }
    }
};

// Component Functions
pub const ComponentFunction = struct {
    name: []u8,
    params: []Param,
    result: ?u32, // Index into component.types, null if no result

    pub const Param = struct {
        name: []u8,
        ty_idx: u32, // Index into component.types
    };

    pub fn deinit(self: *ComponentFunction, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        for (self.params) |*p| {
            allocator.free(p.name);
        }
        allocator.free(self.params);
    }
};

// Component Imports/Exports
pub const ComponentImport = struct {
    name: []u8,
    ty_idx: u32, // Index into component.types

    pub fn deinit(self: *ComponentImport, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
    }
};

pub const ComponentExport = struct {
    name: []u8,
    ty_idx: u32, // Index into component.types

    pub fn deinit(self: *ComponentExport, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
    }
};

// Component Instances
pub const ComponentInstance = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    io: std.Io,
    component: *const Component,
    exports: std.StringHashMap(ComponentValue),
    imports: std.StringHashMap(ComponentValue),
    resource_table: ResourceTable,
    nested_instances: std.ArrayList(*ComponentInstance),

    pub fn init(allocator: std.mem.Allocator, io: std.Io, component: *const Component) !Self {
        return Self{
            .allocator = allocator,
            .component = component,
            .exports = std.StringHashMap(ComponentValue).init(allocator),
            .imports = std.StringHashMap(ComponentValue).init(allocator),
            .resource_table = try ResourceTable.init(allocator, io),
            .io = io,
            .nested_instances = try std.ArrayList(*ComponentInstance).initCapacity(allocator, 0),
        };
    }

    pub fn deinit(self: *Self) void {
        {
            var it = self.exports.iterator();
            while (it.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
                entry.value_ptr.deinit(self.allocator);
            }
            self.exports.deinit();
        }
        {
            var it = self.imports.iterator();
            while (it.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
                entry.value_ptr.deinit(self.allocator);
            }
            self.imports.deinit();
        }
        self.resource_table.deinit();
        for (self.nested_instances.items) |instance| {
            instance.deinit();
            self.allocator.destroy(instance);
        }
        self.nested_instances.deinit(self.allocator);
    }

    pub fn callStart(self: *Self) !void {
        _ = self;
        std.log.info("Component start function called", .{});
    }

    // Instantiate the component with the given imports
    pub fn instantiate(self: *Self, imports: std.StringHashMap(ComponentValue)) !void {
        // Link imports
        var import_it = imports.iterator();
        while (import_it.next()) |entry| {
            const key = try self.allocator.dupe(u8, entry.key_ptr.*);
            try self.imports.put(key, entry.value_ptr.*);
        }

        // TODO: Initialize exports based on component definition
        // For now, create empty exports
        for (self.component.exports.items) |export_item| {
            const key = try self.allocator.dupe(u8, export_item.name);
            // TODO: Create actual export values
            try self.exports.put(key, ComponentValue{ .bool = false }); // Placeholder
        }
    }

    pub fn call(self: *Self, func_idx: u32, args: []ComponentValue) !ComponentValue {
        _ = self;
        _ = func_idx;
        _ = args;
        // TODO: Implement component function calling
        return ComponentValue{ .bool = false }; // Placeholder
    }
};

// Component Values (for runtime)
pub const ComponentValue = union(ComponentValueTag) {
    const Self = @This();

    bool: bool,
    s8: i8,
    u8: u8,
    s16: i16,
    u16: u16,
    s32: i32,
    u32: u32,
    s64: i64,
    u64: u64,
    float32: f32,
    float64: f64,
    char: u32, // Unicode scalar value
    string: []u8,
    record: std.StringHashMap(Self),
    variant: VariantValue,
    list: []Self,
    tuple: []Self,
    flags: std.StringHashMap(bool),
    @"enum": []u8,
    @"union": UnionValue,
    option: ?*Self,
    result: ResultValue,
    own: u32, // Resource handle
    borrow: u32, // Resource handle
    func: u32, // Function index

    pub const ComponentValueTag = enum {
        bool,
        s8,
        u8,
        s16,
        u16,
        s32,
        u32,
        s64,
        u64,
        float32,
        float64,
        char,
        string,
        record,
        variant,
        list,
        tuple,
        flags,
        @"enum",
        @"union",
        option,
        result,
        own,
        borrow,
        func,
    };

    pub const VariantValue = struct {
        case: []u8,
        value: ?*Self,
    };

    pub const UnionValue = struct {
        case: u32,
        value: *Self,
    };

    pub const ResultValue = union(enum) {
        ok: *Self,
        err: *Self,
    };

    pub fn deinit(self: *ComponentValue, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .string => |s| allocator.free(s),
            .record => |*r| {
                var it = r.iterator();
                while (it.next()) |entry| {
                    allocator.free(entry.key_ptr.*);
                    entry.value_ptr.deinit(allocator);
                }
                r.deinit();
            },
            .variant => |v| {
                allocator.free(v.case);
                if (v.value) |val| {
                    val.deinit(allocator);
                    allocator.destroy(val);
                }
            },
            .list => |l| {
                for (l) |*item| item.deinit(allocator);
                allocator.free(l);
            },
            .tuple => |t| {
                for (t) |*item| item.deinit(allocator);
                allocator.free(t);
            },
            .flags => |*f| {
                var it = f.iterator();
                while (it.next()) |entry| {
                    allocator.free(entry.key_ptr.*);
                }
                f.deinit();
            },
            .@"enum" => |e| allocator.free(e),
            .@"union" => |u| {
                u.value.deinit(allocator);
                allocator.destroy(u.value);
            },
            .option => |o| {
                if (o) |val| {
                    val.deinit(allocator);
                    allocator.destroy(val);
                }
            },
            .result => |r| {
                switch (r) {
                    .ok => |val| {
                        val.deinit(allocator);
                        allocator.destroy(val);
                    },
                    .err => |val| {
                        val.deinit(allocator);
                        allocator.destroy(val);
                    },
                }
            },
            else => {},
        }
    }

    // Dereference a borrowed resource handle to get the underlying value
    // This is used in the Component Model to access resources through borrow handles
    pub fn derefBorrow(self: *const ComponentValue, resource_table: *const ResourceTable) !?ComponentValue {
        switch (self.*) {
            .borrow => |handle| {
                // Get the resource type from the table
                const resource_type = resource_table.getResourceType(handle) orelse return error.InvalidResourceHandle;

                // For now, return a simple representation based on type
                // In a full implementation, this would return the actual resource data
                return switch (resource_type) {
                    .file => ComponentValue{ .u32 = handle },
                    .directory => ComponentValue{ .u32 = handle },
                    .socket => ComponentValue{ .u32 = handle },
                    .stream => ComponentValue{ .u32 = handle },
                };
            },
            else => return error.NotABorrowHandle,
        }
    }

    // Dereference an owned resource handle
    // This transfers ownership and invalidates the handle
    pub fn derefOwn(self: *ComponentValue, resource_table: *ResourceTable) !ComponentValue {
        switch (self.*) {
            .own => |handle| {
                // Get the resource type
                const resource_type = resource_table.getResourceType(handle) orelse return error.InvalidResourceHandle;

                // Get the underlying handle value
                const underlying_handle = resource_table.getHandle(handle) orelse return error.InvalidResourceHandle;

                // Remove from resource table (transfers ownership)
                try resource_table.removeResource(handle);

                // Return the value
                return switch (resource_type) {
                    .file => ComponentValue{ .u32 = underlying_handle },
                    .directory => ComponentValue{ .u32 = underlying_handle },
                    .socket => ComponentValue{ .u32 = underlying_handle },
                    .stream => ComponentValue{ .u32 = underlying_handle },
                };
            },
            else => return error.NotAnOwnHandle,
        }
    }

    // Create a borrow from an owned resource
    pub fn createBorrow(owned: *const ComponentValue, allocator: std.mem.Allocator, resource_table: *ResourceTable) !ComponentValue {
        _ = allocator; // May be used for future allocations

        switch (owned.*) {
            .own => |handle| {
                // Verify the handle is valid
                _ = resource_table.getHandle(handle) orelse return error.InvalidResourceHandle;

                // Create a borrow (same handle, different type)
                return ComponentValue{ .borrow = handle };
            },
            else => return error.NotAnOwnHandle,
        }
    }

    // Drop an owned resource, calling its destructor
    pub fn dropOwn(self: *ComponentValue, resource_table: *ResourceTable) !void {
        switch (self.*) {
            .own => |handle| {
                // Remove and.close(io) the resource
                try resource_table.removeResource(handle);

                // Invalidate the handle by setting it to max value
                self.own = std.math.maxInt(u32);
            },
            else => return error.NotAnOwnHandle,
        }
    }

    // Clone a component value (deep copy)
    pub fn clone(self: *const ComponentValue, allocator: std.mem.Allocator) !ComponentValue {
        return switch (self.*) {
            .bool => |v| ComponentValue{ .bool = v },
            .s8 => |v| ComponentValue{ .s8 = v },
            .u8 => |v| ComponentValue{ .u8 = v },
            .s16 => |v| ComponentValue{ .s16 = v },
            .u16 => |v| ComponentValue{ .u16 = v },
            .s32 => |v| ComponentValue{ .s32 = v },
            .u32 => |v| ComponentValue{ .u32 = v },
            .s64 => |v| ComponentValue{ .s64 = v },
            .u64 => |v| ComponentValue{ .u64 = v },
            .float32 => |v| ComponentValue{ .float32 = v },
            .float64 => |v| ComponentValue{ .float64 = v },
            .char => |v| ComponentValue{ .char = v },
            .string => |s| ComponentValue{ .string = try allocator.dupe(u8, s) },
            .record => |r| {
                var new_record = std.StringHashMap(ComponentValue).init(allocator);
                var it = r.iterator();
                while (it.next()) |entry| {
                    const key = try allocator.dupe(u8, entry.key_ptr.*);
                    const value = try entry.value_ptr.clone(allocator);
                    try new_record.put(key, value);
                }
                return ComponentValue{ .record = new_record };
            },
            .variant => |v| {
                const case = try allocator.dupe(u8, v.case);
                const value = if (v.value) |val| blk: {
                    const cloned = try allocator.create(ComponentValue);
                    cloned.* = try val.clone(allocator);
                    break :blk cloned;
                } else null;
                return ComponentValue{ .variant = .{ .case = case, .value = value } };
            },
            .list => |l| {
                const new_list = try allocator.alloc(ComponentValue, l.len);
                for (l, 0..) |*item, i| {
                    new_list[i] = try item.clone(allocator);
                }
                return ComponentValue{ .list = new_list };
            },
            .tuple => |t| {
                const new_tuple = try allocator.alloc(ComponentValue, t.len);
                for (t, 0..) |*item, i| {
                    new_tuple[i] = try item.clone(allocator);
                }
                return ComponentValue{ .tuple = new_tuple };
            },
            .flags => |f| {
                var new_flags = std.StringHashMap(bool).init(allocator);
                var it = f.iterator();
                while (it.next()) |entry| {
                    const key = try allocator.dupe(u8, entry.key_ptr.*);
                    try new_flags.put(key, entry.value_ptr.*);
                }
                return ComponentValue{ .flags = new_flags };
            },
            .@"enum" => |e| ComponentValue{ .@"enum" = try allocator.dupe(u8, e) },
            .@"union" => |u| {
                const new_value = try allocator.create(ComponentValue);
                new_value.* = try u.value.clone(allocator);
                return ComponentValue{ .@"union" = .{ .case = u.case, .value = new_value } };
            },
            .option => |o| {
                if (o) |val| {
                    const new_val = try allocator.create(ComponentValue);
                    new_val.* = try val.clone(allocator);
                    return ComponentValue{ .option = new_val };
                }
                return ComponentValue{ .option = null };
            },
            .result => |r| {
                return switch (r) {
                    .ok => |val| blk: {
                        const new_val = try allocator.create(ComponentValue);
                        new_val.* = try val.clone(allocator);
                        break :blk ComponentValue{ .result = .{ .ok = new_val } };
                    },
                    .err => |val| blk: {
                        const new_val = try allocator.create(ComponentValue);
                        new_val.* = try val.clone(allocator);
                        break :blk ComponentValue{ .result = .{ .err = new_val } };
                    },
                };
            },
            .own => |h| ComponentValue{ .own = h }, // Ownership is transferred, not cloned
            .borrow => |h| ComponentValue{ .borrow = h },
            .func => |f| ComponentValue{ .func = f },
        };
    }
};

// Canonical ABI - Core lifting/lowering functions
pub const CanonicalABI = struct {
    // Type conversion cache for optimization
    type_cache: std.AutoHashMap(u64, ConversionInfo),

    const ConversionInfo = struct {
        lift_fn: ?*const fn (*anyopaque, Value, ComponentType, *const Component) anyerror!ComponentValue,
        lower_fn: ?*const fn (*anyopaque, ComponentValue, *const Component) anyerror!Value,
        context: *anyopaque,
    };

    pub fn init(allocator: std.mem.Allocator) CanonicalABI {
        return CanonicalABI{
            .type_cache = std.AutoHashMap(u64, ConversionInfo).init(allocator),
        };
    }

    pub fn deinit(self: *CanonicalABI) void {
        self.type_cache.deinit();
    }

    // Fast path for primitive types
    inline fn liftPrimitive(wasm_value: Value, tag: ComponentValue.ComponentValueTag) ComponentValue {
        return switch (tag) {
            .bool => ComponentValue{ .bool = wasm_value.i32 != 0 },
            .s32 => ComponentValue{ .s32 = wasm_value.i32 },
            .u32 => ComponentValue{ .u32 = @bitCast(wasm_value.i32) },
            .s64 => ComponentValue{ .s64 = wasm_value.i64 },
            .u64 => ComponentValue{ .u64 = @bitCast(wasm_value.i64) },
            .float32 => ComponentValue{ .float32 = wasm_value.f32 },
            .float64 => ComponentValue{ .float64 = wasm_value.f64 },
            else => unreachable, // Should not be called for non-primitives
        };
    }

    inline fn lowerPrimitive(component_value: ComponentValue) Value {
        return switch (component_value) {
            .bool => |b| Value{ .i32 = if (b) 1 else 0 },
            .s32 => |v| Value{ .i32 = v },
            .u32 => |v| Value{ .i32 = @bitCast(v) },
            .s64 => |v| Value{ .i64 = v },
            .u64 => |v| Value{ .i64 = @bitCast(v) },
            .float32 => |v| Value{ .f32 = v },
            .float64 => |v| Value{ .f64 = v },
            else => Value{ .i32 = 0 }, // Placeholder
        };
    }
    // Lift a WebAssembly value to a component value
    pub fn lift(self: *CanonicalABI, allocator: std.mem.Allocator, wasm_value: Value, component_type: ComponentType, memory: ?[]u8) !ComponentValue {

        // Fast path for common primitive types
        switch (component_type.tag) {
            .bool, .s32, .u32, .s64, .u64, .float32, .float64 => {
                return self.liftPrimitive(wasm_value, component_type.tag);
            },
            .s8 => return ComponentValue{ .s8 = @intCast(wasm_value.i32) },
            .u8 => return ComponentValue{ .u8 = @intCast(wasm_value.i32) },
            .s16 => return ComponentValue{ .s16 = @intCast(wasm_value.i32) },
            .u16 => return ComponentValue{ .u16 = @intCast(wasm_value.i32) },
            .char => return ComponentValue{ .char = @intCast(wasm_value.i32) },
            .string => {
                // Strings are represented as (pointer, length) pairs in WASM
                // For component model, strings are passed as i32 values containing pointers
                if (memory) |mem| {
                    const ptr = @as(usize, @intCast(wasm_value.i32));
                    if (ptr + 8 > mem.len) return error.InvalidMemoryAccess;

                    // Read pointer and length (both i32, little endian)
                    const str_ptr = std.mem.readInt(u32, mem[ptr..][0..4], .little);
                    const str_len = std.mem.readInt(u32, mem[ptr + 4 ..][0..4], .little);

                    const str_start = @as(usize, str_ptr);
                    if (str_start + str_len > mem.len) return error.InvalidMemoryAccess;

                    const str_bytes = mem[str_start .. str_start + str_len];
                    return ComponentValue{ .string = try allocator.dupe(u8, str_bytes) };
                } else {
                    return error.MemoryRequired;
                }
            },
            .record => |record| {
                // Records are passed as multiple values - this needs stack access
                // Placeholder implementation
                _ = record;
                var fields = std.StringHashMap(ComponentValue).init(allocator);
                errdefer fields.deinit();
                // Would need to pop values from stack for each field
                return ComponentValue{ .record = fields };
            },
            .variant => |variant| {
                // Variants are discriminant + payload
                // Placeholder implementation
                _ = variant;
                return ComponentValue{ .variant = .{ .case = try allocator.dupe(u8, "placeholder"), .payload = null } };
            },
            .list => {
                // Lists are pointer + length
                // Placeholder implementation
                return ComponentValue{ .list = try allocator.dupe(ComponentValue, &[_]ComponentValue{}) };
            },
            .tuple => {
                // Tuples are multiple values
                // Placeholder implementation
                return ComponentValue{ .tuple = try allocator.dupe(ComponentValue, &[_]ComponentValue{}) };
            },
            .flags => |flag_names| {
                // Flags are bitfields
                var flags = std.StringHashMap(bool).init(allocator);
                errdefer flags.deinit();
                for (flag_names) |name| {
                    try flags.put(try allocator.dupe(u8, name), false);
                }
                return ComponentValue{ .flags = flags };
            },
            .@"enum" => |enum_names| {
                // Enums are represented as indices
                return ComponentValue{ .@"enum" = try allocator.dupe(u8, if (enum_names.len > 0) enum_names[0] else "unknown") };
            },
            .option => {
                // Options are nullable types
                return ComponentValue{ .option = null };
            },
            .result => |result| {
                // Results are ok/err unions
                _ = result;
                return ComponentValue{ .result = .{ .ok = null, .err = null } };
            },
            .own => return ComponentValue{ .own = 0 }, // Placeholder resource handle
            .borrow => return ComponentValue{ .borrow = 0 }, // Placeholder resource handle
            else => return error.UnsupportedType,
        }
    }

    // Lower a component value to a WebAssembly value
    pub fn lower(self: *CanonicalABI, component_value: ComponentValue, memory: ?[]u8, allocator: std.mem.Allocator) !Value {
        _ = allocator; // May be used for allocations

        // Fast path for common primitive types
        switch (component_value) {
            .bool, .s8, .u8, .s16, .u16, .s32, .u32, .s64, .u64, .float32, .float64 => {
                return self.lowerPrimitive(component_value);
            },
            .char => |v| return Value{ .i32 = @intCast(v) },
            .string => |str| {
                if (memory) |mem| {
                    // Allocate space for string: 8 bytes for (ptr, len) + string data
                    const total_size = 8 + str.len;
                    // Find free memory (simplified - would need proper allocator)
                    // For now, assume we can allocate at the end
                    const base_ptr = mem.len - total_size;
                    if (base_ptr < 0) return error.OutOfMemory;

                    // Write string data
                    @memcpy(mem[base_ptr + 8 .. base_ptr + 8 + str.len], str);

                    // Write pointer and length
                    std.mem.writeInt(u32, mem[base_ptr..][0..4], @intCast(base_ptr + 8), .little);
                    std.mem.writeInt(u32, mem[base_ptr + 4 ..][0..4], @intCast(str.len), .little);

                    return Value{ .i32 = @intCast(base_ptr) };
                } else {
                    return error.MemoryRequired;
                }
            },
            .record => return Value{ .i32 = 0 }, // Placeholder
            .variant => return Value{ .i32 = 0 }, // Placeholder
            .list => return Value{ .i32 = 0 }, // Placeholder
            .tuple => return Value{ .i32 = 0 }, // Placeholder
            .flags => return Value{ .i32 = 0 }, // Placeholder
            .@"enum" => return Value{ .i32 = 0 }, // Placeholder
            .@"union" => return Value{ .i32 = 0 }, // Placeholder
            .option => return Value{ .i32 = 0 }, // Placeholder
            .result => return Value{ .i32 = 0 }, // Placeholder
            .own => return Value{ .i32 = 0 }, // Placeholder
            .borrow => return Value{ .i32 = 0 }, // Placeholder
            .func => return Value{ .i32 = 0 }, // Placeholder
        }
    }
};

// Component Instructions
pub const ComponentInstruction = union(enum) {
    // Control instructions
    @"unreachable",
    nop,
    block: BlockType,
    loop: BlockType,
    @"if": BlockType,
    @"else",
    end,
    br: u32,
    br_if: u32,
    br_table: BrTable,
    @"return",
    call: u32,
    call_indirect: CallIndirect,
    drop,
    select,

    // Variable instructions
    local_get: u32,
    local_set: u32,
    local_tee: u32,
    global_get: u32,
    global_set: u32,

    // Memory instructions
    load: MemArg,
    load8_s: MemArg,
    load8_u: MemArg,
    load16_s: MemArg,
    load16_u: MemArg,
    load32_s: MemArg,
    load32_u: MemArg,
    store: MemArg,
    store8: MemArg,
    store16: MemArg,
    store32: MemArg,
    memory_size,
    memory_grow,

    // Numeric instructions
    @"const": ComponentValue,
    eq,
    ne,
    lt,
    gt,
    le,
    ge,
    clz,
    ctz,
    popcnt,
    add,
    sub,
    mul,
    div_s,
    div_u,
    rem_s,
    rem_u,
    @"and",
    @"or",
    xor,
    shl,
    shr_s,
    shr_u,
    rotl,
    rotr,
    abs,
    neg,
    ceil,
    floor,
    trunc,
    nearest,
    sqrt,
    min,
    max,
    copysign,

    // Conversion instructions
    wrap_i64,
    trunc_f32_s,
    trunc_f32_u,
    trunc_f64_s,
    trunc_f64_u,
    extend_i32_s,
    extend_i32_u,
    trunc_f32_s_i64,
    trunc_f32_u_i64,
    trunc_f64_s_i64,
    trunc_f64_u_i64,
    convert_i32_s,
    convert_i32_u,
    convert_i64_s,
    convert_i64_u,
    demote_f64,
    convert_i32_s_f64,
    convert_i32_u_f64,
    convert_i64_s_f64,
    convert_i64_u_f64,
    promote_f32,
    reinterpret_i32,
    reinterpret_i64,
    reinterpret_f32,
    reinterpret_f64,

    // Component-specific instructions
    canonical_lift: CanonicalLift,
    canonical_lower: CanonicalLower,
    call_core: CallCore,
    ref_null: u32,
    ref_is_null,
    ref_func: u32,
    ref_eq,
    ref_as_non_null,
    br_on_null: u32,
    br_on_non_null: u32,

    pub const BlockType = struct {
        ty_idx: ?u32, // null for no result type
    };

    pub const BrTable = struct {
        targets: []u32,
        default: u32,
    };

    pub const CallIndirect = struct {
        table_idx: u32,
        ty_idx: u32,
    };

    pub const MemArg = struct {
        alignment: u32,
        offset: u32,
    };

    pub const CanonicalLift = struct {
        core_func_ty_idx: u32,
        options: []LiftOption,
    };

    pub const CanonicalLower = struct {
        func_ty_idx: u32,
        options: []LowerOption,
    };

    pub const CallCore = struct {
        core_func_idx: u32,
    };

    pub const LiftOption = union(enum) {
        memory: u32,
        realloc: u32,
        post_return: u32,
    };

    pub const LowerOption = union(enum) {
        memory: u32,
        realloc: u32,
        post_return: u32,
    };
};

// Component Function Body
pub const ComponentFunctionBody = struct {
    locals: []ComponentValue,
    instructions: []ComponentInstruction,

    pub fn deinit(self: *ComponentFunctionBody, allocator: std.mem.Allocator) void {
        for (self.locals) |*local| {
            local.deinit(allocator);
        }
        allocator.free(self.locals);
        allocator.free(self.instructions);
    }
};

// Component Interpreter
pub const ComponentInterpreter = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    instance: *ComponentInstance,
    stack: std.ArrayList(ComponentValue),
    call_stack: std.ArrayList(Frame),
    memory: ?[]u8, // Reference to core module memory
    runtime: ?*Runtime, // Runtime for executing core functions

    // Control flow state
    control_stack: std.ArrayList(ControlFrame),

    const Frame = struct {
        locals: []ComponentValue,
        return_arity: u32,
    };

    const ControlFrame = struct {
        label: []const u8,
        return_arity: u32,
        stack_height: usize,
        instruction_ptr: usize,
        is_loop: bool,
    };

    pub fn init(allocator: std.mem.Allocator, instance: *ComponentInstance, memory: ?[]u8, runtime: ?*Runtime) !Self {
        return Self{
            .allocator = allocator,
            .instance = instance,
            .stack = try std.ArrayList(ComponentValue).initCapacity(allocator, 0),
            .call_stack = try std.ArrayList(Frame).initCapacity(allocator, 0),
            .control_stack = try std.ArrayList(ControlFrame).initCapacity(allocator, 0),
            .memory = memory,
            .runtime = runtime,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.stack.items) |*value| {
            value.deinit(self.allocator);
        }
        self.stack.deinit(self.allocator);

        for (self.call_stack.items) |*frame| {
            for (frame.locals) |*local| {
                local.deinit(self.allocator);
            }
            self.allocator.free(frame.locals);
        }
        self.call_stack.deinit(self.allocator);
        self.control_stack.deinit(self.allocator);
    }

    pub fn executeFunction(self: *Self, func_idx: u32, args: []ComponentValue) !ComponentValue {
        // Get function body from component
        if (func_idx >= self.instance.component.function_bodies.items.len) {
            return error.InvalidFunctionIndex;
        }
        const body = &self.instance.component.function_bodies.items[func_idx];

        // Create frame with locals (args + body locals)
        const total_locals = args.len + body.locals.len;
        const locals = try self.allocator.alloc(ComponentValue, total_locals);

        // Copy args
        for (args, 0..) |arg, i| {
            locals[i] = arg;
        }

        // Copy body locals
        for (body.locals, 0..) |local, i| {
            locals[args.len + i] = local;
        }

        const frame = Frame{
            .locals = locals,
            .return_arity = 1, // Assume single return for now
        };
        try self.call_stack.append(self.allocator, frame);

        // Execute instructions with control flow
        var ip: usize = 0;
        while (ip < body.instructions.len) {
            const instr = body.instructions[ip];
            const result = try self.executeInstruction(instr, &ip, body.instructions);
            if (result == .branch) {
                // Branch occurred, ip has been updated
                continue;
            } else if (result == .@"return") {
                // Return occurred
                break;
            }
            ip += 1;
        }

        // Return result
        const result = try self.pop();
        if (self.call_stack.pop()) |popped_frame| {
            for (popped_frame.locals) |*local| {
                local.deinit(self.allocator);
            }
            self.allocator.free(popped_frame.locals);
        }
        return result;
    }

    const ExecutionResult = enum {
        normal,
        branch,
        @"return",
    };

    fn executeInstruction(self: *Self, instr: ComponentInstruction, ip: *usize, instructions: []ComponentInstruction) !ExecutionResult {
        switch (instr) {
            .@"unreachable" => return error.Unreachable,
            .nop => {},
            .block => |bt| {
                // Push a new control frame for the block
                const label = try std.fmt.allocPrint(self.allocator, "block_{d}", .{ip.*});
                defer self.allocator.free(label);
                try self.control_stack.append(self.allocator, .{
                    .label = try self.allocator.dupe(u8, label),
                    .return_arity = if (bt.ty_idx) |_| 1 else 0,
                    .stack_height = self.stack.items.len,
                    .instruction_ptr = ip.*,
                    .is_loop = false,
                });
            },
            .loop => |bt| {
                // Push a new control frame for the loop
                const label = try std.fmt.allocPrint(self.allocator, "loop_{d}", .{ip.*});
                defer self.allocator.free(label);
                try self.control_stack.append(self.allocator, .{
                    .label = try self.allocator.dupe(u8, label),
                    .return_arity = if (bt.ty_idx) |_| 1 else 0,
                    .stack_height = self.stack.items.len,
                    .instruction_ptr = ip.*,
                    .is_loop = true,
                });
            },
            .@"if" => |bt| {
                // Pop condition
                const condition = try self.pop();
                const cond_bool = switch (condition) {
                    .bool => |b| b,
                    else => return error.InvalidConditionType,
                };

                if (!cond_bool) {
                    // Skip to else or end
                    var depth: usize = 1;
                    var skip_ip = ip.* + 1;
                    while (skip_ip < instructions.len and depth > 0) {
                        switch (instructions[skip_ip]) {
                            .@"if", .block, .loop => depth += 1,
                            .@"else" => if (depth == 1) {
                                ip.* = skip_ip;
                                return .normal;
                            },
                            .end => {
                                depth -= 1;
                                if (depth == 0) {
                                    ip.* = skip_ip;
                                    return .normal;
                                }
                            },
                            else => {},
                        }
                        skip_ip += 1;
                    }
                } else {
                    // Push control frame for if block
                    const label = try std.fmt.allocPrint(self.allocator, "if_{d}", .{ip.*});
                    defer self.allocator.free(label);
                    try self.control_stack.append(self.allocator, .{
                        .label = try self.allocator.dupe(u8, label),
                        .return_arity = if (bt.ty_idx) |_| 1 else 0,
                        .stack_height = self.stack.items.len,
                        .instruction_ptr = ip.*,
                        .is_loop = false,
                    });
                }
            },
            .@"else" => {
                // For else, we need to skip to the end of the if block
                var depth: usize = 1;
                var skip_ip = ip.* + 1;
                while (skip_ip < instructions.len and depth > 0) {
                    switch (instructions[skip_ip]) {
                        .@"if", .block, .loop => depth += 1,
                        .end => {
                            depth -= 1;
                            if (depth == 0) {
                                ip.* = skip_ip;
                                return .normal;
                            }
                        },
                        else => {},
                    }
                    skip_ip += 1;
                }
            },
            .end => {
                // Pop control frame
                if (self.control_stack.pop()) |frame| {
                    self.allocator.free(frame.label);
                    // Unwind stack if necessary
                    while (self.stack.items.len > frame.stack_height) {
                        const value_ptr = &self.stack.items[self.stack.items.len - 1];
                        _ = self.stack.orderedRemove(self.stack.items.len - 1);
                        value_ptr.deinit(self.allocator);
                    }
                }
            },
            .br => |label_idx| {
                try self.branchToLabel(label_idx, ip);
                return .branch;
            },
            .br_if => |label_idx| {
                const condition = try self.pop();
                const cond_bool = switch (condition) {
                    .bool => |b| b,
                    else => return error.InvalidConditionType,
                };
                if (cond_bool) {
                    try self.branchToLabel(label_idx, ip);
                    return .branch;
                }
            },
            .br_table => |br_table| {
                const index_val = try self.pop();
                const index = switch (index_val) {
                    .u32 => |i| i,
                    else => return error.InvalidTableIndexType,
                };

                const target_idx = if (index < br_table.targets.len)
                    br_table.targets[index]
                else
                    br_table.default;

                try self.branchToLabel(target_idx, ip);
                return .branch;
            },
            .@"return" => {
                return .@"return";
            },
            .call => |func_idx| {
                // Component function call
                const result = try self.instance.call(func_idx, &[_]ComponentValue{});
                try self.push(result);
            },
            .call_indirect => |ci| _ = ci,
            .drop => {
                var value = try self.pop();
                value.deinit(self.allocator);
            },
            .select => {},
            .local_get => |idx| {
                const frame = &self.call_stack.items[self.call_stack.items.len - 1];
                try self.push(frame.locals[idx]);
            },
            .local_set => |idx| {
                const frame = &self.call_stack.items[self.call_stack.items.len - 1];
                frame.locals[idx].deinit(self.allocator);
                frame.locals[idx] = try self.pop();
            },
            .local_tee => |idx| {
                const frame = &self.call_stack.items[self.call_stack.items.len - 1];
                const value = try self.pop();
                frame.locals[idx].deinit(self.allocator);
                frame.locals[idx] = value;
                try self.push(value);
            },
            .global_get => |idx| _ = idx,
            .global_set => |idx| _ = idx,
            .load => |ma| try self.executeLoad(ma, 4, false),
            .load8_s => |ma| try self.executeLoad(ma, 1, true),
            .load8_u => |ma| try self.executeLoad(ma, 1, false),
            .load16_s => |ma| try self.executeLoad(ma, 2, true),
            .load16_u => |ma| try self.executeLoad(ma, 2, false),
            .load32_s => |ma| try self.executeLoad(ma, 4, true),
            .load32_u => |ma| try self.executeLoad(ma, 4, false),
            .store => |ma| try self.executeStore(ma, 4),
            .store8 => |ma| try self.executeStore(ma, 1),
            .store16 => |ma| try self.executeStore(ma, 2),
            .store32 => |ma| try self.executeStore(ma, 4),
            .memory_size => try self.executeMemorySize(),
            .memory_grow => try self.executeMemoryGrow(),
            .@"const" => |value| try self.push(value),
            .eq => try self.executeBinaryOp(.eq),
            .ne => try self.executeBinaryOp(.ne),
            .lt => try self.executeBinaryOp(.lt),
            .gt => try self.executeBinaryOp(.gt),
            .le => try self.executeBinaryOp(.le),
            .ge => try self.executeBinaryOp(.ge),
            .add => try self.executeBinaryOp(.add),
            .sub => try self.executeBinaryOp(.sub),
            .mul => try self.executeBinaryOp(.mul),
            .div_s => try self.executeBinaryOp(.div_s),
            .div_u => try self.executeBinaryOp(.div_u),
            .rem_s => try self.executeBinaryOp(.rem_s),
            .rem_u => try self.executeBinaryOp(.rem_u),
            .@"and" => try self.executeBinaryOp(.@"and"),
            .@"or" => try self.executeBinaryOp(.@"or"),
            .xor => try self.executeBinaryOp(.xor),
            .shl => try self.executeBinaryOp(.shl),
            .shr_s => try self.executeBinaryOp(.shr_s),
            .shr_u => try self.executeBinaryOp(.shr_u),
            .rotl => try self.executeBinaryOp(.rotl),
            .rotr => try self.executeBinaryOp(.rotr),
            .clz => try self.executeUnaryOp(.clz),
            .ctz => try self.executeUnaryOp(.ctz),
            .popcnt => try self.executeUnaryOp(.popcnt),
            .abs => try self.executeUnaryOp(.abs),
            .neg => try self.executeUnaryOp(.neg),
            .ceil => try self.executeUnaryOp(.ceil),
            .floor => try self.executeUnaryOp(.floor),
            .trunc => try self.executeUnaryOp(.trunc),
            .nearest => try self.executeUnaryOp(.nearest),
            .sqrt => try self.executeUnaryOp(.sqrt),
            .min => try self.executeBinaryOp(.min),
            .max => try self.executeBinaryOp(.max),
            .copysign => try self.executeBinaryOp(.copysign),
            .wrap_i64 => try self.executeUnaryOp(.wrap_i64),
            .trunc_f32_s => try self.executeUnaryOp(.trunc_f32_s),
            .trunc_f32_u => try self.executeUnaryOp(.trunc_f32_u),
            .trunc_f64_s => try self.executeUnaryOp(.trunc_f64_s),
            .trunc_f64_u => try self.executeUnaryOp(.trunc_f64_u),
            .extend_i32_s => try self.executeUnaryOp(.extend_i32_s),
            .extend_i32_u => try self.executeUnaryOp(.extend_i32_u),
            .trunc_f32_s_i64 => try self.executeUnaryOp(.trunc_f32_s_i64),
            .trunc_f32_u_i64 => try self.executeUnaryOp(.trunc_f32_u_i64),
            .trunc_f64_s_i64 => try self.executeUnaryOp(.trunc_f64_s_i64),
            .trunc_f64_u_i64 => try self.executeUnaryOp(.trunc_f64_u_i64),
            .convert_i32_s => try self.executeUnaryOp(.convert_i32_s),
            .convert_i32_u => try self.executeUnaryOp(.convert_i32_u),
            .convert_i64_s => try self.executeUnaryOp(.convert_i64_s),
            .convert_i64_u => try self.executeUnaryOp(.convert_i64_u),
            .demote_f64 => try self.executeUnaryOp(.demote_f64),
            .convert_i32_s_f64 => try self.executeUnaryOp(.convert_i32_s_f64),
            .convert_i32_u_f64 => try self.executeUnaryOp(.convert_i32_u_f64),
            .convert_i64_s_f64 => try self.executeUnaryOp(.convert_i64_s_f64),
            .convert_i64_u_f64 => try self.executeUnaryOp(.convert_i64_u_f64),
            .promote_f32 => try self.executeUnaryOp(.promote_f32),
            .reinterpret_i32 => try self.executeUnaryOp(.reinterpret_i32),
            .reinterpret_i64 => try self.executeUnaryOp(.reinterpret_i64),
            .reinterpret_f32 => try self.executeUnaryOp(.reinterpret_f32),
            .reinterpret_f64 => try self.executeUnaryOp(.reinterpret_f64),
            .canonical_lift => |lift| {
                // Lift core function to component function
                const core_func_idx = lift.core_func_ty_idx;
                // Create a component function that calls the core function
                const component_func = ComponentValue{ .func = core_func_idx };
                try self.push(component_func);
            },
            .canonical_lower => |lower| {
                // Lower component function to core function
                const func_value = try self.pop();
                // Would create core function wrapper
                _ = lower;
                try self.push(func_value);
            },
            .call_core => |call| {
                // Call core module function
                if (self.runtime) |rt| {
                    const core_func_idx = call.core_func_idx;
                    // Execute the core function
                    const result = try rt.executeFunction(core_func_idx, &[_]Value{});
                    // Convert result back to component value
                    // For now, assume single i32 result
                    try self.push(ComponentValue{ .u32 = @bitCast(result.i32) });
                } else {
                    try self.push(ComponentValue{ .bool = false }); // No runtime available
                }
            },
            .ref_null => |ty| _ = ty,
            .ref_is_null => {},
            .ref_func => |func| _ = func,
            .ref_eq => {},
            .ref_as_non_null => {},
            .br_on_null => |label| _ = label,
            .br_on_non_null => |label| _ = label,
        }
        return .normal;
    }

    fn push(self: *Self, value: ComponentValue) !void {
        try self.stack.append(self.allocator, value);
    }

    fn pop(self: *Self) !ComponentValue {
        return self.stack.pop() orelse error.StackUnderflow;
    }

    fn executeLoad(self: *Self, mem_arg: ComponentInstruction.MemArg, size: u32, signed: bool) !void {
        if (self.memory) |mem| {
            const addr_val = try self.pop();
            if (addr_val != .u32) return error.InvalidAddressType;

            const addr = addr_val.u32;
            const effective_addr = addr + mem_arg.offset;

            if (effective_addr + size > mem.len) return error.MemoryAccessOutOfBounds;

            const bytes = mem[effective_addr .. effective_addr + size];
            const value = switch (size) {
                1 => if (signed) ComponentValue{ .s8 = @intCast(bytes[0]) } else ComponentValue{ .u8 = bytes[0] },
                2 => if (signed) ComponentValue{ .s16 = std.mem.readInt(i16, bytes[0..2], .little) } else ComponentValue{ .u16 = std.mem.readInt(u16, bytes[0..2], .little) },
                4 => if (signed) ComponentValue{ .s32 = std.mem.readInt(i32, bytes[0..4], .little) } else ComponentValue{ .u32 = std.mem.readInt(u32, bytes[0..4], .little) },
                else => return error.UnsupportedLoadSize,
            };

            try self.push(value);
        } else {
            return error.NoMemoryAvailable;
        }
    }

    fn executeStore(self: *Self, mem_arg: ComponentInstruction.MemArg, size: u32) !void {
        if (self.memory) |mem| {
            const value = try self.pop();
            const addr_val = try self.pop();
            if (addr_val != .u32) return error.InvalidAddressType;

            const addr = addr_val.u32;
            const effective_addr = addr + mem_arg.offset;

            if (effective_addr + size > mem.len) return error.MemoryAccessOutOfBounds;

            const bytes = mem[effective_addr .. effective_addr + size];
            switch (size) {
                1 => {
                    if (value == .u8) {
                        bytes[0] = value.u8;
                    } else if (value == .s8) {
                        bytes[0] = @as(u8, @bitCast(value.s8));
                    } else return error.InvalidStoreValueType;
                },
                2 => {
                    const val = if (value == .u16) value.u16 else if (value == .s16) @as(u16, @bitCast(value.s16)) else return error.InvalidStoreValueType;
                    std.mem.writeInt(u16, bytes[0..2], val, .little);
                },
                4 => {
                    const val = if (value == .u32) value.u32 else if (value == .s32) @as(u32, @bitCast(value.s32)) else return error.InvalidStoreValueType;
                    std.mem.writeInt(u32, bytes[0..4], val, .little);
                },
                else => return error.UnsupportedStoreSize,
            }
        } else {
            return error.NoMemoryAvailable;
        }
    }

    fn executeMemorySize(self: *Self) !void {
        if (self.memory) |mem| {
            const size_in_pages = mem.len / (64 * 1024); // WASM page size is 64KB
            try self.push(ComponentValue{ .u32 = @intCast(size_in_pages) });
        } else {
            try self.push(ComponentValue{ .u32 = 0 });
        }
    }

    fn executeMemoryGrow(self: *Self) !void {
        // For now, memory grow is not implemented - would need to resize the memory buffer
        // Return the current size (meaning grow failed)
        try self.executeMemorySize();
    }

    fn executeUnaryOp(self: *Self, op: ComponentInstruction) !void {
        const operand = try self.pop();
        const result = try performUnaryOp(operand, op);
        try self.push(result);
    }

    fn executeBinaryOp(self: *Self, op: ComponentInstruction) !void {
        const right = try self.pop();
        const left = try self.pop();
        const result = try performBinaryOp(left, right, op);
        try self.push(result);
    }

    fn performUnaryOp(operand: ComponentValue, op: ComponentInstruction) !ComponentValue {
        return switch (op) {
            .clz => switch (operand) {
                .u32 => |v| ComponentValue{ .u32 = @clz(v) },
                .u64 => |v| ComponentValue{ .u32 = @clz(v) },
                else => error.InvalidOperandType,
            },
            .ctz => switch (operand) {
                .u32 => |v| ComponentValue{ .u32 = @ctz(v) },
                .u64 => |v| ComponentValue{ .u32 = @ctz(v) },
                else => error.InvalidOperandType,
            },
            .popcnt => switch (operand) {
                .u32 => |v| ComponentValue{ .u32 = @popCount(v) },
                .u64 => |v| ComponentValue{ .u32 = @popCount(v) },
                else => error.InvalidOperandType,
            },
            .abs => switch (operand) {
                .float32 => |v| ComponentValue{ .float32 = @abs(v) },
                .float64 => |v| ComponentValue{ .float64 = @abs(v) },
                else => error.InvalidOperandType,
            },
            .neg => switch (operand) {
                .float32 => |v| ComponentValue{ .float32 = -v },
                .float64 => |v| ComponentValue{ .float64 = -v },
                else => error.InvalidOperandType,
            },
            .ceil => switch (operand) {
                .float32 => |v| ComponentValue{ .float32 = @ceil(v) },
                .float64 => |v| ComponentValue{ .float64 = @ceil(v) },
                else => error.InvalidOperandType,
            },
            .floor => switch (operand) {
                .float32 => |v| ComponentValue{ .float32 = @floor(v) },
                .float64 => |v| ComponentValue{ .float64 = @floor(v) },
                else => error.InvalidOperandType,
            },
            .trunc => switch (operand) {
                .float32 => |v| ComponentValue{ .float32 = @trunc(v) },
                .float64 => |v| ComponentValue{ .float64 = @trunc(v) },
                else => error.InvalidOperandType,
            },
            .nearest => switch (operand) {
                .float32 => |v| ComponentValue{ .float32 = @round(v) },
                .float64 => |v| ComponentValue{ .float64 = @round(v) },
                else => error.InvalidOperandType,
            },
            .sqrt => switch (operand) {
                .float32 => |v| ComponentValue{ .float32 = @sqrt(v) },
                .float64 => |v| ComponentValue{ .float64 = @sqrt(v) },
                else => error.InvalidOperandType,
            },
            .wrap_i64 => switch (operand) {
                .u64 => |v| ComponentValue{ .u32 = @truncate(v) },
                else => error.InvalidOperandType,
            },
            .trunc_f32_s => switch (operand) {
                .float32 => |v| ComponentValue{ .s32 = @intFromFloat(@trunc(v)) },
                else => error.InvalidOperandType,
            },
            .trunc_f32_u => switch (operand) {
                .float32 => |v| ComponentValue{ .u32 = @intFromFloat(@trunc(v)) },
                else => error.InvalidOperandType,
            },
            .trunc_f64_s => switch (operand) {
                .float64 => |v| ComponentValue{ .s32 = @intFromFloat(@trunc(v)) },
                else => error.InvalidOperandType,
            },
            .trunc_f64_u => switch (operand) {
                .float64 => |v| ComponentValue{ .u32 = @intFromFloat(@trunc(v)) },
                else => error.InvalidOperandType,
            },
            .extend_i32_s => switch (operand) {
                .s32 => |v| ComponentValue{ .s64 = v },
                else => error.InvalidOperandType,
            },
            .extend_i32_u => switch (operand) {
                .u32 => |v| ComponentValue{ .u64 = v },
                else => error.InvalidOperandType,
            },
            .trunc_f32_s_i64 => switch (operand) {
                .float32 => |v| ComponentValue{ .s64 = @intFromFloat(@trunc(v)) },
                else => error.InvalidOperandType,
            },
            .trunc_f32_u_i64 => switch (operand) {
                .float32 => |v| ComponentValue{ .u64 = @intFromFloat(@trunc(v)) },
                else => error.InvalidOperandType,
            },
            .trunc_f64_s_i64 => switch (operand) {
                .float64 => |v| ComponentValue{ .s64 = @intFromFloat(@trunc(v)) },
                else => error.InvalidOperandType,
            },
            .trunc_f64_u_i64 => switch (operand) {
                .float64 => |v| ComponentValue{ .u64 = @intFromFloat(@trunc(v)) },
                else => error.InvalidOperandType,
            },
            .convert_i32_s => switch (operand) {
                .s32 => |v| ComponentValue{ .float32 = @floatFromInt(v) },
                else => error.InvalidOperandType,
            },
            .convert_i32_u => switch (operand) {
                .u32 => |v| ComponentValue{ .float32 = @floatFromInt(v) },
                else => error.InvalidOperandType,
            },
            .convert_i64_s => switch (operand) {
                .s64 => |v| ComponentValue{ .float32 = @floatFromInt(v) },
                else => error.InvalidOperandType,
            },
            .convert_i64_u => switch (operand) {
                .u64 => |v| ComponentValue{ .float32 = @floatFromInt(v) },
                else => error.InvalidOperandType,
            },
            .demote_f64 => switch (operand) {
                .float64 => |v| ComponentValue{ .float32 = @floatCast(v) },
                else => error.InvalidOperandType,
            },
            .convert_i32_s_f64 => switch (operand) {
                .s32 => |v| ComponentValue{ .float64 = @floatFromInt(v) },
                else => error.InvalidOperandType,
            },
            .convert_i32_u_f64 => switch (operand) {
                .u32 => |v| ComponentValue{ .float64 = @floatFromInt(v) },
                else => error.InvalidOperandType,
            },
            .convert_i64_s_f64 => switch (operand) {
                .s64 => |v| ComponentValue{ .float64 = @floatFromInt(v) },
                else => error.InvalidOperandType,
            },
            .convert_i64_u_f64 => switch (operand) {
                .u64 => |v| ComponentValue{ .float64 = @floatFromInt(v) },
                else => error.InvalidOperandType,
            },
            .promote_f32 => switch (operand) {
                .float32 => |v| ComponentValue{ .float64 = v },
                else => error.InvalidOperandType,
            },
            .reinterpret_i32 => switch (operand) {
                .u32 => |v| ComponentValue{ .float32 = @bitCast(v) },
                else => error.InvalidOperandType,
            },
            .reinterpret_i64 => switch (operand) {
                .u64 => |v| ComponentValue{ .float64 = @bitCast(v) },
                else => error.InvalidOperandType,
            },
            .reinterpret_f32 => switch (operand) {
                .float32 => |v| ComponentValue{ .u32 = @bitCast(v) },
                else => error.InvalidOperandType,
            },
            .reinterpret_f64 => switch (operand) {
                .float64 => |v| ComponentValue{ .u64 = @bitCast(v) },
                else => error.InvalidOperandType,
            },
            else => error.UnsupportedUnaryOp,
        };
    }

    fn performBinaryOp(left: ComponentValue, right: ComponentValue, op: ComponentInstruction) !ComponentValue {
        return switch (op) {
            .eq => ComponentValue{ .bool = valuesEqual(left, right) },
            .ne => ComponentValue{ .bool = !valuesEqual(left, right) },
            .lt => ComponentValue{ .bool = try valueLessThan(left, right) },
            .gt => ComponentValue{ .bool = try valueLessThan(right, left) },
            .le => ComponentValue{ .bool = !(try valueLessThan(right, left)) },
            .ge => ComponentValue{ .bool = !(try valueLessThan(left, right)) },
            .add => try performArithmeticOp(left, right, .add),
            .sub => try performArithmeticOp(left, right, .sub),
            .mul => try performArithmeticOp(left, right, .mul),
            .div_s => try performArithmeticOp(left, right, .div_s),
            .div_u => try performArithmeticOp(left, right, .div_u),
            .rem_s => try performArithmeticOp(left, right, .rem_s),
            .rem_u => try performArithmeticOp(left, right, .rem_u),
            .@"and" => try performBitwiseOp(left, right, .@"and"),
            .@"or" => try performBitwiseOp(left, right, .@"or"),
            .xor => try performBitwiseOp(left, right, .xor),
            .shl => try performBitwiseOp(left, right, .shl),
            .shr_s => try performBitwiseOp(left, right, .shr_s),
            .shr_u => try performBitwiseOp(left, right, .shr_u),
            .rotl => try performBitwiseOp(left, right, .rotl),
            .rotr => try performBitwiseOp(left, right, .rotr),
            .min => try performFloatOp(left, right, .min),
            .max => try performFloatOp(left, right, .max),
            .copysign => try performFloatOp(left, right, .copysign),
            else => error.UnsupportedBinaryOp,
        };
    }

    fn valuesEqual(a: ComponentValue, b: ComponentValue) bool {
        if (@as(ComponentValue.ComponentValueTag, a) != @as(ComponentValue.ComponentValueTag, b)) return false;
        return switch (a) {
            .bool => |v| v == b.bool,
            .s8 => |v| v == b.s8,
            .u8 => |v| v == b.u8,
            .s16 => |v| v == b.s16,
            .u16 => |v| v == b.u16,
            .s32 => |v| v == b.s32,
            .u32 => |v| v == b.u32,
            .s64 => |v| v == b.s64,
            .u64 => |v| v == b.u64,
            .float32 => |v| v == b.float32,
            .float64 => |v| v == b.float64,
            .char => |v| v == b.char,
            .string => |v| std.mem.eql(u8, v, b.string),
            else => false, // Complex types not compared for equality here
        };
    }

    fn valueLessThan(a: ComponentValue, b: ComponentValue) !bool {
        if (@as(ComponentValue.ComponentValueTag, a) != @as(ComponentValue.ComponentValueTag, b)) return error.IncompatibleTypes;
        return switch (a) {
            .s8 => |v| v < b.s8,
            .u8 => |v| v < b.u8,
            .s16 => |v| v < b.s16,
            .u16 => |v| v < b.u16,
            .s32 => |v| v < b.s32,
            .u32 => |v| v < b.u32,
            .s64 => |v| v < b.s64,
            .u64 => |v| v < b.u64,
            .float32 => |v| v < b.float32,
            .float64 => |v| v < b.float64,
            else => error.UnsupportedComparison,
        };
    }

    fn performArithmeticOp(left: ComponentValue, right: ComponentValue, op: ComponentInstruction) !ComponentValue {
        if (@as(ComponentValue.ComponentValueTag, left) != @as(ComponentValue.ComponentValueTag, right)) return error.IncompatibleTypes;
        return switch (left) {
            .s32 => switch (op) {
                .add => ComponentValue{ .s32 = left.s32 + right.s32 },
                .sub => ComponentValue{ .s32 = left.s32 - right.s32 },
                .mul => ComponentValue{ .s32 = left.s32 * right.s32 },
                .div_s => ComponentValue{ .s32 = @divTrunc(left.s32, right.s32) },
                .rem_s => ComponentValue{ .s32 = @rem(left.s32, right.s32) },
                else => error.UnsupportedArithmeticOp,
            },
            .u32 => switch (op) {
                .add => ComponentValue{ .u32 = left.u32 + right.u32 },
                .sub => ComponentValue{ .u32 = left.u32 - right.u32 },
                .mul => ComponentValue{ .u32 = left.u32 * right.u32 },
                .div_u => ComponentValue{ .u32 = left.u32 / right.u32 },
                .rem_u => ComponentValue{ .u32 = left.u32 % right.u32 },
                else => error.UnsupportedArithmeticOp,
            },
            .s64 => switch (op) {
                .add => ComponentValue{ .s64 = left.s64 + right.s64 },
                .sub => ComponentValue{ .s64 = left.s64 - right.s64 },
                .mul => ComponentValue{ .s64 = left.s64 * right.s64 },
                .div_s => ComponentValue{ .s64 = @divTrunc(left.s64, right.s64) },
                .rem_s => ComponentValue{ .s64 = @rem(left.s64, right.s64) },
                else => error.UnsupportedArithmeticOp,
            },
            .u64 => switch (op) {
                .add => ComponentValue{ .u64 = left.u64 + right.u64 },
                .sub => ComponentValue{ .u64 = left.u64 - right.u64 },
                .mul => ComponentValue{ .u64 = left.u64 * right.u64 },
                .div_u => ComponentValue{ .u64 = left.u64 / right.u64 },
                .rem_u => ComponentValue{ .u64 = left.u64 % right.u64 },
                else => error.UnsupportedArithmeticOp,
            },
            .float32 => switch (op) {
                .add => ComponentValue{ .float32 = left.float32 + right.float32 },
                .sub => ComponentValue{ .float32 = left.float32 - right.float32 },
                .mul => ComponentValue{ .float32 = left.float32 * right.float32 },
                .div_s => ComponentValue{ .float32 = left.float32 / right.float32 },
                else => error.UnsupportedArithmeticOp,
            },
            .float64 => switch (op) {
                .add => ComponentValue{ .float64 = left.float64 + right.float64 },
                .sub => ComponentValue{ .float64 = left.float64 - right.float64 },
                .mul => ComponentValue{ .float64 = left.float64 * right.float64 },
                .div_s => ComponentValue{ .float64 = left.float64 / right.float64 },
                else => error.UnsupportedArithmeticOp,
            },
            else => error.UnsupportedArithmeticType,
        };
    }

    fn performBitwiseOp(left: ComponentValue, right: ComponentValue, op: ComponentInstruction) !ComponentValue {
        if (@as(ComponentValue.ComponentValueTag, left) != @as(ComponentValue.ComponentValueTag, right)) return error.IncompatibleTypes;
        return switch (left) {
            .u32 => switch (op) {
                .@"and" => ComponentValue{ .u32 = left.u32 & right.u32 },
                .@"or" => ComponentValue{ .u32 = left.u32 | right.u32 },
                .xor => ComponentValue{ .u32 = left.u32 ^ right.u32 },
                .shl => ComponentValue{ .u32 = left.u32 << @truncate(right.u32) },
                .shr_u => ComponentValue{ .u32 = left.u32 >> @truncate(right.u32) },
                .shr_s => ComponentValue{ .u32 = @bitCast(@as(i32, @bitCast(left.u32)) >> @truncate(right.u32)) },
                .rotl => ComponentValue{ .u32 = std.math.rotl(u32, left.u32, right.u32) },
                .rotr => ComponentValue{ .u32 = std.math.rotr(u32, left.u32, right.u32) },
                else => error.UnsupportedBitwiseOp,
            },
            .u64 => switch (op) {
                .@"and" => ComponentValue{ .u64 = left.u64 & right.u64 },
                .@"or" => ComponentValue{ .u64 = left.u64 | right.u64 },
                .xor => ComponentValue{ .u64 = left.u64 ^ right.u64 },
                .shl => ComponentValue{ .u64 = left.u64 << @truncate(right.u64) },
                .shr_u => ComponentValue{ .u64 = left.u64 >> @truncate(right.u64) },
                .shr_s => ComponentValue{ .u64 = @bitCast(@as(i64, @bitCast(left.u64)) >> @truncate(right.u64)) },
                .rotl => ComponentValue{ .u64 = std.math.rotl(u64, left.u64, right.u64) },
                .rotr => ComponentValue{ .u64 = std.math.rotr(u64, left.u64, right.u64) },
                else => error.UnsupportedBitwiseOp,
            },
            else => error.UnsupportedBitwiseType,
        };
    }

    fn performFloatOp(left: ComponentValue, right: ComponentValue, op: ComponentInstruction) !ComponentValue {
        if (@as(ComponentValue.ComponentValueTag, left) != @as(ComponentValue.ComponentValueTag, right)) return error.IncompatibleTypes;
        return switch (left) {
            .float32 => switch (op) {
                .min => ComponentValue{ .float32 = @min(left.float32, right.float32) },
                .max => ComponentValue{ .float32 = @max(left.float32, right.float32) },
                .copysign => ComponentValue{ .float32 = std.math.copysign(left.float32, right.float32) },
                else => error.UnsupportedFloatOp,
            },
            .float64 => switch (op) {
                .min => ComponentValue{ .float64 = @min(left.float64, right.float64) },
                .max => ComponentValue{ .float64 = @max(left.float64, right.float64) },
                .copysign => ComponentValue{ .float64 = std.math.copysign(left.float64, right.float64) },
                else => error.UnsupportedFloatOp,
            },
            else => error.UnsupportedFloatType,
        };
    }

    fn branchToLabel(self: *Self, label_idx: u32, ip: *usize) !void {
        if (label_idx >= self.control_stack.items.len) return error.InvalidLabelIndex;

        const target_frame_idx = self.control_stack.items.len - 1 - label_idx;
        const target_frame = &self.control_stack.items[target_frame_idx];

        // Unwind control stack
        while (self.control_stack.items.len > target_frame_idx + 1) {
            if (self.control_stack.pop()) |frame| {
                self.allocator.free(frame.label);
            }
        }

        // Unwind value stack to target height
        while (self.stack.items.len > target_frame.stack_height) {
            const value_ptr = &self.stack.items[self.stack.items.len - 1];
            _ = self.stack.orderedRemove(self.stack.items.len - 1);
            value_ptr.deinit(self.allocator);
        }

        // Set instruction pointer
        if (target_frame.is_loop) {
            // For loops, branch to the beginning
            ip.* = target_frame.instruction_ptr;
        } else {
            // For blocks, find the corresponding end
            var depth: usize = 1;
            var search_ip = target_frame.instruction_ptr + 1;
            while (search_ip < ip.* and depth > 0) {
                const frame = self.control_stack.items[target_frame_idx + depth - 1];
                // Check if this frame is an end by checking if we're at the end of a block
                // This is a simplified check - in practice, we'd need to track the instruction types
                _ = frame; // Use frame to avoid unused variable warning
                depth -= 1; // Simplified for now - assumes we're always ending a block
                search_ip += 1;
            }
            ip.* = search_ip - 1; // Point to the end instruction
        }
    }
};

// Component Parser
pub const ComponentParser = struct {
    const Self = @This();

    reader: Module.Reader,
    allocator: std.mem.Allocator,
    io: std.Io,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, data: []const u8) Self {
        return Self{
            .reader = Module.Reader.init(data),
            .allocator = allocator,
            .io = io,
        };
    }

    pub fn parseComponent(self: *Self, allocator: std.mem.Allocator) !Component {
        var component = try Component.init(allocator);
        errdefer component.deinit();

        // Parse component header
        const magic = try self.reader.readBytes(4);
        if (!std.mem.eql(u8, magic, "\x00asm")) return error.InvalidMagic;

        const version = try self.reader.readBytes(4);
        // Accept Component Model version 0x0d with either Layer 0 (0x00) or Layer 1 (0x01)
        const is_valid_version = (version[0] == 0x0d and version[1] == 0x00) and
            (version[2] <= 0x01 and version[3] == 0x00);
        if (!is_valid_version) return error.InvalidVersion;

        // Check if this is Layer 1 (canonical ABI with WIT imports)
        const is_layer1 = version[2] == 0x01;

        if (is_layer1) {
            // Layer 1 components have a different encoding format
            // Parse layer 1 sections
            return try self.parseLayer1Component(allocator, component);
        }

        // Parse Layer 0 sections (core module-like structure)
        while (self.reader.pos < self.reader.bytes.len) {
            const section_id = try self.reader.readByte();
            const section_size = @as(usize, @intCast(try self.reader.readLEB128()));

            switch (section_id) {
                0x01 => try self.parseTypeSection(&component, section_size),
                0x02 => try self.parseImportSection(&component, section_size),
                0x03 => try self.parseFunctionSection(&component, section_size),
                0x04 => try self.parseTableSection(&component, section_size),
                0x05 => try self.parseMemorySection(&component, section_size),
                0x06 => try self.parseGlobalSection(&component, section_size),
                0x07 => try self.parseExportSection(&component, section_size),
                0x08 => try self.parseStartSection(&component, section_size),
                0x09 => try self.parseElementSection(&component, section_size),
                0x0A => try self.parseCodeSection(&component, section_size),
                0x0B => try self.parseDataSection(&component, section_size),
                0x0C => try self.parseDataCountSection(&component, section_size),
                0x0E => try self.parseCoreTypeSection(&component, section_size),
                0x0F => try self.parseCoreModuleSection(&component, section_size),
                0x10 => try self.parseCoreInstanceSection(&component, section_size),
                0x11 => try self.parseCoreAliasSection(&component, section_size),
                0x12 => try self.parseCoreStartSection(&component, section_size),
                else => {
                    // Skip unknown sections
                    var i: usize = 0;
                    while (i < section_size) : (i += 1) {
                        _ = try self.reader.readByte();
                    }
                },
            }
        }

        return component;
    }

    fn parseLayer1Component(self: *Self, allocator: std.mem.Allocator, component: Component) !Component {
        // Layer 1 components can contain embedded core modules
        // Search for core module magic bytes: 00 61 73 6d 01 00 00 00
        const core_magic = "\x00asm\x01\x00\x00\x00";

        // Search through the remaining bytes for a core module
        var search_pos: usize = self.reader.pos;
        while (search_pos + 8 <= self.reader.bytes.len) {
            // Check if we found core module magic
            if (std.mem.eql(u8, self.reader.bytes[search_pos..][0..8], core_magic)) {
                // Found an embedded core module!
                // Parse it as a regular module
                const core_module_bytes = self.reader.bytes[search_pos..];

                // Create a new reader for the core module
                var core_reader = Module.Reader.init(core_module_bytes);

                // Skip magic and version (already validated)
                _ = try core_reader.readBytes(8);

                // Create a temporary component with the core module
                var result = component;

                // Parse core module sections
                while (core_reader.pos < core_module_bytes.len) {
                    const section_id = core_reader.readByte() catch break;
                    const section_size = @as(usize, @intCast(core_reader.readLEB128() catch break));

                    if (section_size > core_module_bytes.len or
                        core_reader.pos + section_size > core_module_bytes.len)
                    {
                        break;
                    }

                    // Save position before parsing section
                    const section_start = core_reader.pos;

                    // Create a temporary parser for this section
                    var temp_parser = ComponentParser{
                        .reader = core_reader,
                        .allocator = self.allocator,
                        .io = self.io,
                    };

                    // Parse the section
                    switch (section_id) {
                        0x01 => temp_parser.parseTypeSection(&result, section_size) catch {},
                        0x02 => temp_parser.parseImportSection(&result, section_size) catch {},
                        0x03 => temp_parser.parseFunctionSection(&result, section_size) catch {},
                        0x04 => temp_parser.parseTableSection(&result, section_size) catch {},
                        0x05 => temp_parser.parseMemorySection(&result, section_size) catch {},
                        0x06 => temp_parser.parseGlobalSection(&result, section_size) catch {},
                        0x07 => temp_parser.parseExportSection(&result, section_size) catch {},
                        0x08 => temp_parser.parseStartSection(&result, section_size) catch {},
                        0x09 => temp_parser.parseElementSection(&result, section_size) catch {},
                        0x0A => temp_parser.parseCodeSection(&result, section_size) catch {},
                        0x0B => temp_parser.parseDataSection(&result, section_size) catch {},
                        0x0C => temp_parser.parseDataCountSection(&result, section_size) catch {},
                        else => {},
                    }

                    // Move to next section
                    core_reader.pos = section_start + section_size;
                }

                return result;
            }
            search_pos += 1;
        }

        // No core module found, return empty component
        _ = allocator;
        return component;
    }

    fn skipComponentType(self: *Self) !void {
        // TODO: Implement proper skipping
        // For now, just skip a byte to avoid infinite recursion
        _ = try self.reader.readByte();
    }

    fn skipRecord(self: *Self) !void {
        const field_count = try self.reader.readLEB128();
        var i: usize = 0;
        while (i < field_count) : (i += 1) {
            const name_len = try self.reader.readLEB128();
            _ = try self.reader.readBytes(name_len);
            try self.skipComponentType();
        }
    }

    fn skipVariant(self: *Self) !void {
        const case_count = try self.reader.readLEB128();
        var i: usize = 0;
        while (i < case_count) : (i += 1) {
            const name_len = try self.reader.readLEB128();
            _ = try self.reader.readBytes(name_len);
            const has_type = try self.reader.readByte();
            if (has_type != 0) try self.skipComponentType();
        }
    }

    fn skipFlags(self: *Self) !void {
        const name_count = try self.reader.readLEB128();
        var total_len: usize = 0;
        var i: usize = 0;
        while (i < name_count) : (i += 1) {
            const name_len = try self.reader.readLEB128();
            total_len += name_len;
        }
        _ = try self.reader.readBytes(total_len);
    }

    fn skipEnum(self: *Self) !void {
        const name_count = try self.reader.readLEB128();
        var total_len: usize = 0;
        var i: usize = 0;
        while (i < name_count) : (i += 1) {
            const name_len = try self.reader.readLEB128();
            total_len += name_len;
        }
        _ = try self.reader.readBytes(total_len);
    }

    fn skipResult(self: *Self) !void {
        const ok_type = try self.reader.readByte();
        const err_type = try self.reader.readByte();
        if (ok_type != 0) try self.skipComponentType();
        if (err_type != 0) try self.skipComponentType();
    }

    fn parseTypeSection(self: *Self, component: *Component, size: usize) !void {
        _ = size; // TODO: Use size for bounds checking
        const count = try self.reader.readLEB128();

        try component.types.ensureTotalCapacity(component.allocator, count);

        var i: usize = 0;
        while (i < count) : (i += 1) {
            const ty = try self.parseComponentType(component.allocator);
            try component.types.append(component.allocator, ty);
        }
    }

    fn parseComponentType(self: *Self, allocator: std.mem.Allocator) !ComponentType {
        const tag = try self.reader.readByte();

        // Type indices are encoded as 0x00-0x3f directly, or as LEB128 with high bit for larger indices
        if (tag < 0x40) {
            // This is a type index reference
            return ComponentType{ .tag = .string, .payload = .{ .string = {} } }; // Placeholder for type ref
        }

        return switch (tag) {
            0x40 => { // func type
                _ = try self.reader.readLEB128(); // Skip function type details for now
                return ComponentType{ .tag = .string, .payload = .{ .string = {} } };
            },
            0x70 => ComponentType{ .tag = .char, .payload = .{ .char = {} } },
            0x71 => ComponentType{ .tag = .string, .payload = .{ .string = {} } },
            0x72 => ComponentType{ .tag = .record, .payload = .{ .record = try self.parseRecord(allocator) } },
            0x73 => ComponentType{ .tag = .variant, .payload = .{ .variant = try self.parseVariant(allocator) } },
            0x74 => { // tuple
                try self.skipComponentType(); // For now, skip tuple parsing
                return ComponentType{ .tag = .string, .payload = .{ .string = {} } }; // Placeholder
            },
            0x75 => { // list
                try self.skipComponentType(); // Skip element type
                return ComponentType{ .tag = .string, .payload = .{ .string = {} } }; // Placeholder
            },
            0x76 => ComponentType{ .tag = .flags, .payload = .{ .flags = try self.parseFlags(allocator) } },
            0x77 => ComponentType{ .tag = .@"enum", .payload = .{ .@"enum" = try self.parseEnum(allocator) } },
            0x78 => { // option
                try self.skipComponentType(); // Skip inner type
                return ComponentType{ .tag = .string, .payload = .{ .string = {} } }; // Placeholder
            },
            0x7a => ComponentType{ .tag = .result, .payload = .{ .result = try self.parseResult() } },
            0x7b => ComponentType{ .tag = .own, .payload = .{ .own = try self.reader.readLEB128() } },
            0x7c => ComponentType{ .tag = .borrow, .payload = .{ .borrow = try self.reader.readLEB128() } },
            0x7d => ComponentType{ .tag = .s8, .payload = .{ .s8 = {} } },
            0x7e => ComponentType{ .tag = .u8, .payload = .{ .u8 = {} } },
            0x7f => ComponentType{ .tag = .s16, .payload = .{ .s16 = {} } },
            0x80 => ComponentType{ .tag = .u16, .payload = .{ .u16 = {} } },
            0x81 => ComponentType{ .tag = .s32, .payload = .{ .s32 = {} } },
            0x82 => ComponentType{ .tag = .u32, .payload = .{ .u32 = {} } },
            0x83 => ComponentType{ .tag = .s64, .payload = .{ .s64 = {} } },
            0x84 => ComponentType{ .tag = .u64, .payload = .{ .u64 = {} } },
            0x85 => ComponentType{ .tag = .float32, .payload = .{ .float32 = {} } },
            0x86 => ComponentType{ .tag = .float64, .payload = .{ .float64 = {} } },
            0x87 => ComponentType{ .tag = .bool, .payload = .{ .bool = {} } },
            else => {
                std.debug.print("Unknown component type tag: 0x{x}\n", .{tag});
                return error.InvalidComponentType;
            },
        };
    }

    fn parseRecord(self: *Self, allocator: std.mem.Allocator) !ComponentType.Record {
        const field_count = try self.reader.readLEB128();
        const fields = try allocator.alloc(ComponentType.Record.Field, field_count);

        for (fields) |*field| {
            const name_len = try self.reader.readLEB128();
            const name_bytes = try self.reader.readBytes(name_len);
            field.name = try allocator.dupe(u8, name_bytes);

            // TODO: proper type indexing
            field.ty_idx = 0;
            try self.skipComponentType();
        }

        return ComponentType.Record{ .fields = fields };
    }

    fn parseVariant(self: *Self, allocator: std.mem.Allocator) !ComponentType.Variant {
        const case_count = try self.reader.readLEB128();
        const cases = try allocator.alloc(ComponentType.Variant.Case, case_count);

        for (cases) |*case| {
            const name_len = try self.reader.readLEB128();
            const name_bytes = try self.reader.readBytes(name_len);
            case.name = try allocator.dupe(u8, name_bytes);

            const has_type = try self.reader.readByte();
            case.ty_idx = if (has_type != 0) blk: {
                // TODO: proper type indexing
                try self.skipComponentType();
                break :blk 0;
            } else null;
        }

        return ComponentType.Variant{ .cases = cases };
    }

    fn parseListType(self: *Self, allocator: std.mem.Allocator) !*ComponentType {
        const ty = try allocator.create(ComponentType);
        ty.* = try self.parseComponentType(allocator);
        return ty;
    }

    fn parseTuple(self: *Self, allocator: std.mem.Allocator) ![]ComponentType {
        const type_count = try self.reader.readLEB128();
        const types = try allocator.alloc(ComponentType, type_count);

        for (types) |*ty| {
            ty.* = try self.parseComponentType(allocator);
        }

        return types;
    }

    fn parseFlags(self: *Self, allocator: std.mem.Allocator) ![]u8 {
        const name_count = try self.reader.readLEB128();
        const names = try allocator.alloc(u8, name_count);

        // Simplified: just read the concatenated names
        const names_bytes = try self.reader.readBytes(names.len);
        @memcpy(names, names_bytes);

        return names;
    }

    fn parseEnum(self: *Self, allocator: std.mem.Allocator) ![]u8 {
        const name_count = try self.reader.readLEB128();
        const names = try allocator.alloc(u8, name_count);

        const names_bytes = try self.reader.readBytes(names.len);
        @memcpy(names, names_bytes);

        return names;
    }

    fn parseUnion(self: *Self, allocator: std.mem.Allocator) ![]ComponentType {
        const type_count = try self.reader.readLEB128();
        const types = try allocator.alloc(ComponentType, type_count);

        for (types) |*ty| {
            ty.* = try self.parseComponentType(allocator);
        }

        return types;
    }

    fn parseOptionType(self: *Self, allocator: std.mem.Allocator) !*ComponentType {
        const ty = try allocator.create(ComponentType);
        ty.* = try self.parseComponentType(allocator);
        return ty;
    }

    fn parseResult(self: *Self) !ComponentType.Result {
        const ok_type = try self.reader.readByte();
        const err_type = try self.reader.readByte();

        return ComponentType.Result{
            .ok = if (ok_type != 0) blk: {
                // TODO: proper type indexing
                try self.skipComponentType();
                break :blk 0;
            } else null,
            .err = if (err_type != 0) blk: {
                // TODO: proper type indexing
                try self.skipComponentType();
                break :blk 0;
            } else null,
        };
    }

    fn parseImportSection(self: *Self, component: *Component, size: usize) !void {
        _ = size;
        const count = try self.reader.readLEB128();
        try component.imports.ensureTotalCapacity(component.allocator, count);
        var i: usize = 0;
        while (i < count) : (i += 1) {
            const name = try self.reader.readName(component.allocator);
            const ty_idx = try self.reader.readLEB128();
            try component.imports.append(component.allocator, .{
                .name = name,
                .ty_idx = @as(u32, @intCast(ty_idx)),
            });
        }
    }

    fn parseComponentImport(self: *Self, allocator: std.mem.Allocator) !ComponentImport {
        const name_len = try self.reader.readLEB128();
        const name_bytes = try self.reader.readBytes(name_len);
        const name = try allocator.dupe(u8, name_bytes);

        // TODO: proper type indexing
        const ty_idx = 0;
        try self.skipComponentType(); // Skip the type for now

        return ComponentImport{
            .name = name,
            .ty_idx = ty_idx,
        };
    }

    fn parseFunctionSection(self: *Self, component: *Component, size: usize) !void {
        _ = size;
        const count = try self.reader.readLEB128();
        try component.functions.ensureTotalCapacity(component.allocator, count);
        var i: usize = 0;
        while (i < count) : (i += 1) {
            const ty_idx = try self.reader.readLEB128();
            try component.functions.append(component.allocator, @as(u32, @intCast(ty_idx)));
        }
    }

    fn parseTableSection(self: *Self, component: *Component, size: usize) !void {
        _ = component;
        var i: usize = 0;
        while (i < size) : (i += 1) {
            _ = try self.reader.readByte();
        }
    }

    fn parseMemorySection(self: *Self, component: *Component, size: usize) !void {
        _ = component;
        var i: usize = 0;
        while (i < size) : (i += 1) {
            _ = try self.reader.readByte();
        }
    }

    fn parseGlobalSection(self: *Self, component: *Component, size: usize) !void {
        _ = component;
        var i: usize = 0;
        while (i < size) : (i += 1) {
            _ = try self.reader.readByte();
        }
    }

    fn parseExportSection(self: *Self, component: *Component, size: usize) !void {
        _ = size;
        const count = try self.reader.readLEB128();
        try component.exports.ensureTotalCapacity(component.allocator, count);
        var i: usize = 0;
        while (i < count) : (i += 1) {
            const name = try self.reader.readName(component.allocator);
            const ty_idx = try self.reader.readLEB128();
            try component.exports.append(component.allocator, .{
                .name = name,
                .ty_idx = @as(u32, @intCast(ty_idx)),
            });
        }
    }

    fn parseStartSection(self: *Self, component: *Component, size: usize) !void {
        _ = size;
        const func_idx = try self.reader.readLEB128();
        component.start = @as(u32, @intCast(func_idx));
    }

    fn parseElementSection(self: *Self, component: *Component, size: usize) !void {
        _ = component;
        var i: usize = 0;
        while (i < size) : (i += 1) {
            _ = try self.reader.readByte();
        }
    }

    fn parseCodeSection(self: *Self, component: *Component, size: usize) !void {
        _ = size; // TODO: Use for bounds checking
        const count = try self.reader.readLEB128();

        try component.function_bodies.ensureTotalCapacity(component.allocator, count);

        var i: usize = 0;
        while (i < count) : (i += 1) {
            const body = try self.parseComponentFunctionBody(component.allocator);
            try component.function_bodies.append(component.allocator, body);
        }
    }

    fn parseComponentFunctionBody(self: *Self, allocator: std.mem.Allocator) !ComponentFunctionBody {
        // Parse locals
        const local_count = try self.reader.readLEB128();
        const locals = try allocator.alloc(ComponentValue, local_count);

        for (locals) |*local| {
            // For now, initialize locals to default values
            local.* = ComponentValue{ .bool = false };
        }

        // Parse instructions until end
        var instructions = try std.ArrayList(ComponentInstruction).initCapacity(allocator, 0);
        defer instructions.deinit(allocator);

        while (true) {
            const opcode = try self.reader.readByte();
            const instr = try self.parseComponentInstruction(opcode, allocator);
            try instructions.append(allocator, instr);

            if (instr == .end) break;
        }

        return ComponentFunctionBody{
            .locals = locals,
            .instructions = try instructions.toOwnedSlice(allocator),
        };
    }

    fn parseComponentInstruction(self: *Self, opcode: u8, allocator: std.mem.Allocator) !ComponentInstruction {
        return switch (opcode) {
            0x00 => .@"unreachable",
            0x01 => .nop,
            0x02 => ComponentInstruction{ .block = .{ .ty_idx = try self.reader.readLEB128() } },
            0x03 => ComponentInstruction{ .loop = .{ .ty_idx = try self.reader.readLEB128() } },
            0x04 => ComponentInstruction{ .@"if" = .{ .ty_idx = try self.reader.readLEB128() } },
            0x05 => .@"else",
            0x0B => .end,
            0x0C => ComponentInstruction{ .br = try self.reader.readLEB128() },
            0x0D => ComponentInstruction{ .br_if = try self.reader.readLEB128() },
            0x0E => blk: {
                const target_count = try self.reader.readLEB128();
                const targets = try allocator.alloc(u32, target_count);
                for (targets) |*target| {
                    target.* = try self.reader.readLEB128();
                }
                const default_target = try self.reader.readLEB128();
                break :blk ComponentInstruction{ .br_table = .{ .targets = targets, .default = default_target } };
            },
            0x0F => .@"return",
            0x10 => ComponentInstruction{ .call = try self.reader.readLEB128() },
            0x11 => ComponentInstruction{ .call_indirect = .{ .table_idx = try self.reader.readLEB128(), .ty_idx = try self.reader.readLEB128() } },
            0x12 => .drop,
            0x13 => .select,
            0x15 => ComponentInstruction{ .local_get = try self.reader.readLEB128() },
            0x16 => ComponentInstruction{ .local_set = try self.reader.readLEB128() },
            0x17 => ComponentInstruction{ .local_tee = try self.reader.readLEB128() },
            0x18 => ComponentInstruction{ .global_get = try self.reader.readLEB128() },
            0x19 => ComponentInstruction{ .global_set = try self.reader.readLEB128() },
            0x1C => ComponentInstruction{ .load = .{ .alignment = try self.reader.readLEB128(), .offset = try self.reader.readLEB128() } },
            0x20 => ComponentInstruction{ .store = .{ .alignment = try self.reader.readLEB128(), .offset = try self.reader.readLEB128() } },
            0x24 => .memory_size,
            0x25 => .memory_grow,
            0x26 => blk: {
                // const instruction - need to parse the value type and value
                // This is complex, for now return a placeholder
                _ = try self.reader.readLEB128(); // Skip value type
                _ = try self.reader.readLEB128(); // Skip value
                break :blk ComponentInstruction{ .@"const" = ComponentValue{ .bool = false } };
            },
            0xFB => blk: {
                const sub_opcode = try self.reader.readLEB128();
                break :blk switch (sub_opcode) {
                    0x00 => ComponentInstruction{ .canonical_lift = try self.parseCanonicalLift(allocator) },
                    0x01 => ComponentInstruction{ .canonical_lower = try self.parseCanonicalLower(allocator) },
                    0x02 => ComponentInstruction{ .call_core = .{ .core_func_idx = try self.reader.readLEB128() } },
                    else => return error.UnsupportedComponentInstruction,
                };
            },
            else => return error.UnsupportedInstruction,
        };
    }

    fn parseCanonicalLift(self: *Self, allocator: std.mem.Allocator) !ComponentInstruction.CanonicalLift {
        const core_func_ty_idx = try self.reader.readLEB128();
        const options_count = try self.reader.readLEB128();
        const options = try allocator.alloc(ComponentInstruction.LiftOption, options_count);

        for (options) |*option| {
            const option_tag = try self.reader.readByte();
            const option_value = try self.reader.readLEB128();
            option.* = switch (option_tag) {
                0 => .{ .memory = option_value },
                1 => .{ .realloc = option_value },
                2 => .{ .post_return = option_value },
                else => return error.InvalidLiftOption,
            };
        }

        return ComponentInstruction.CanonicalLift{
            .core_func_ty_idx = core_func_ty_idx,
            .options = options,
        };
    }

    fn parseCanonicalLower(self: *Self, allocator: std.mem.Allocator) !ComponentInstruction.CanonicalLower {
        const func_ty_idx = try self.reader.readLEB128();
        const options_count = try self.reader.readLEB128();
        const options = try allocator.alloc(ComponentInstruction.LowerOption, options_count);

        for (options) |*option| {
            const option_tag = try self.reader.readByte();
            const option_value = try self.reader.readLEB128();
            option.* = switch (option_tag) {
                0 => .{ .memory = option_value },
                1 => .{ .realloc = option_value },
                2 => .{ .post_return = option_value },
                else => return error.InvalidLowerOption,
            };
        }

        return ComponentInstruction.CanonicalLower{
            .func_ty_idx = func_ty_idx,
            .options = options,
        };
    }

    fn parseDataSection(self: *Self, component: *Component, size: usize) !void {
        _ = component;
        var i: usize = 0;
        while (i < size) : (i += 1) {
            _ = try self.reader.readByte();
        }
    }

    fn parseDataCountSection(self: *Self, component: *Component, size: usize) !void {
        _ = component;
        var i: usize = 0;
        while (i < size) : (i += 1) {
            _ = try self.reader.readByte();
        }
    }

    fn parseCoreTypeSection(self: *Self, component: *Component, size: usize) !void {
        _ = size;
        const count = try self.reader.readLEB128();
        try component.core_types.ensureTotalCapacity(component.allocator, count);
        var i: usize = 0;
        while (i < count) : (i += 1) {
            // Parse WASM function type: 0x60 + params + results
            const type_byte = try self.reader.readByte();
            if (type_byte != 0x60) return error.InvalidType;

            // Parse params
            const param_count = try self.reader.readLEB128();
            const params = try component.allocator.alloc(ValueType, param_count);
            for (params) |*p| {
                const val_type_byte = try self.reader.readByte();
                p.* = switch (val_type_byte) {
                    0x7F => .i32,
                    0x7E => .i64,
                    0x7D => .f32,
                    0x7C => .f64,
                    else => return error.InvalidValueType,
                };
            }

            // Parse results
            const result_count = try self.reader.readLEB128();
            const results = try component.allocator.alloc(ValueType, result_count);
            for (results) |*r| {
                const val_type_byte = try self.reader.readByte();
                r.* = switch (val_type_byte) {
                    0x7F => .i32,
                    0x7E => .i64,
                    0x7D => .f32,
                    0x7C => .f64,
                    else => return error.InvalidValueType,
                };
            }

            try component.core_types.append(component.allocator, .{
                .params = params,
                .results = results,
            });
        }
    }

    fn parseCoreModuleSection(self: *Self, component: *Component, size: usize) !void {
        _ = size;
        const count = try self.reader.readLEB128();
        try component.core_modules.ensureTotalCapacity(component.allocator, count);
        var i: usize = 0;
        while (i < count) : (i += 1) {
            // Read module size
            const module_size = try self.reader.readLEB128();

            // Read the module bytes
            const module_bytes = try self.reader.readBytes(module_size);

            // Parse the embedded WASM module
            const module = try Module.parse(component.allocator, self.io, module_bytes);
            errdefer module.deinit();

            try component.core_modules.append(component.allocator, module);
        }
    }

    fn parseCoreInstanceSection(self: *Self, component: *Component, size: usize) !void {
        _ = component;
        var i: usize = 0;
        while (i < size) : (i += 1) {
            _ = try self.reader.readByte();
        }
    }

    fn parseCoreAliasSection(self: *Self, component: *Component, size: usize) !void {
        _ = component;
        var i: usize = 0;
        while (i < size) : (i += 1) {
            _ = try self.reader.readByte();
        }
    }

    fn parseCoreStartSection(self: *Self, component: *Component, size: usize) !void {
        _ = component;
        var i: usize = 0;
        while (i < size) : (i += 1) {
            _ = try self.reader.readByte();
        }
    }
};

// Component Linker for dynamic loading and linking
pub const ComponentLinker = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    io: std.Io,
    loaded_components: std.StringHashMap(*ComponentInstance),

    pub fn init(allocator: std.mem.Allocator, io: std.Io) Self {
        return Self{
            .allocator = allocator,
            .io = io,
            .loaded_components = std.StringHashMap(*ComponentInstance).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        var it = self.loaded_components.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
            self.allocator.free(entry.key_ptr.*);
        }
        self.loaded_components.deinit();
    }

    pub fn loadComponent(self: *Self, name: []const u8, data: []const u8) !*ComponentInstance {
        // Check if already loaded
        if (self.loaded_components.get(name)) |instance| {
            return instance;
        }

        // Parse component
        var parser = ComponentParser.init(self.allocator, self.io, data);
        var component = try parser.parseComponent(self.allocator);
        errdefer component.deinit();

        // Validate
        try component.validate();

        // Create instance
        var instance = try self.allocator.create(ComponentInstance);
        instance.* = try ComponentInstance.init(self.allocator, self.io, &component);
        errdefer instance.deinit();

        // Store in registry
        const key = try self.allocator.dupe(u8, name);
        try self.loaded_components.put(key, instance);

        return instance;
    }

    pub fn linkComponents(self: *Self, component_a: []const u8, component_b: []const u8, interface_name: []const u8) !void {
        // Load both components
        const inst_a = try self.loadComponent("component_a", component_a);
        const inst_b = try self.loadComponent("component_b", component_b);

        // Copy exports from component_b to component_a's imports
        var it = inst_b.exports.iterator();
        while (it.next()) |entry| {
            const key = try self.allocator.dupe(u8, entry.key_ptr.*);
            const value = try entry.value_ptr.clone(self.allocator);
            try inst_a.imports.put(key, value);
        }

        // Link them under the interface name if provided
        if (interface_name.len > 0) {
            try inst_a.imports.put(try self.allocator.dupe(u8, interface_name), ComponentValue{ .bool = true });
        }
    }

    // Link a specific export from one component to a specific import of another
    pub fn linkExportToImport(
        self: *Self,
        source_name: []const u8,
        source_export: []const u8,
        target_name: []const u8,
        target_import: []const u8,
    ) !void {
        const source = self.loaded_components.get(source_name) orelse return ESMError.ComponentNotLoaded;
        const target = self.loaded_components.get(target_name) orelse return ESMError.ComponentNotLoaded;

        // Get the export value from source
        const export_value = source.exports.get(source_export) orelse return ESMError.ExportNotFound;

        // Clone and add to target's imports
        const value = try export_value.clone(self.allocator);
        const key = try self.allocator.dupe(u8, target_import);
        try target.imports.put(key, value);
    }

    // Resolve all imports for a component by matching with available exports
    pub fn resolveImports(self: *Self, component_name: []const u8) !void {
        const instance = self.loaded_components.get(component_name) orelse return ESMError.ComponentNotLoaded;

        // Iterate through component's required imports
        for (instance.component.imports.items) |import| {
            // Try to find matching export in loaded components
            var resolved = false;
            var it = self.loaded_components.iterator();
            while (it.next()) |entry| {
                // Skip self
                if (std.mem.eql(u8, entry.key_ptr.*, component_name)) continue;

                // Check if this component exports what we need
                if (entry.value_ptr.*.exports.get(import.name)) |export_value| {
                    // Found a match - clone and add to imports
                    const value = try export_value.clone(self.allocator);
                    const key = try self.allocator.dupe(u8, import.name);
                    try instance.imports.put(key, value);
                    resolved = true;
                    break;
                }
            }

            if (!resolved) {
                std.log.warn("Could not resolve import: {s}", .{import.name});
                return ESMError.ImportResolutionFailed;
            }
        }
    }

    // Link all loaded components by resolving their imports/exports
    pub fn linkAll(self: *Self) !void {
        var it = self.loaded_components.iterator();
        while (it.next()) |entry| {
            try self.resolveImports(entry.key_ptr.*);
        }
    }

    // Get a component instance by name
    pub fn getComponent(self: *Self, name: []const u8) ?*ComponentInstance {
        return self.loaded_components.get(name);
    }

    // Unload a component and clean up its resources
    pub fn unloadComponent(self: *Self, name: []const u8) !void {
        if (self.loaded_components.fetchRemove(name)) |kv| {
            kv.value.deinit();
            self.allocator.destroy(kv.value);
            self.allocator.free(kv.key);
        } else {
            return error.ComponentNotLoaded;
        }
    }
};

/// ESM-style module loader that implements ECMAScript Modules semantics for WebAssembly Components
pub const ESMLoader = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    io: std.Io,
    linker: ComponentLinker,
    module_registry: std.StringHashMap(*ComponentInstance),
    import_map: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator, io: std.Io) Self {
        return Self{
            .allocator = allocator,
            .io = io,
            .linker = ComponentLinker.init(allocator, io),
            .module_registry = std.StringHashMap(*ComponentInstance).init(allocator),
            .import_map = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.linker.deinit();
        self.module_registry.deinit();
        self.import_map.deinit();
    }

    /// Load a WebAssembly component as an ESM module
    pub fn loadModule(self: *Self, module_name: []const u8, wasm_bytes: []const u8) !*ComponentInstance {
        // Check if module is already loaded
        if (self.module_registry.get(module_name)) |_| {
            return ESMError.ModuleAlreadyLoaded;
        }

        // Parse and validate the component
        var parser = ComponentParser.init(self.allocator, self.io, wasm_bytes);
        var component = try parser.parseComponent(self.allocator);
        errdefer component.deinit();

        try component.validate();

        // Create component instance
        const instance = try self.allocator.create(ComponentInstance);
        instance.* = try ComponentInstance.init(self.allocator, &component);
        errdefer self.allocator.destroy(instance);

        // Register in module registry
        const name_copy = try self.allocator.dupe(u8, module_name);
        errdefer self.allocator.free(name_copy);

        try self.module_registry.put(name_copy, instance);

        // Initialize default exports based on component definition
        try self.initializeExports(instance, &component);

        return instance;
    }

    /// Initialize exports for a component instance based on its definition
    fn initializeExports(self: *Self, instance: *ComponentInstance, component: *const Component) !void {
        // Initialize exports based on component definition
        for (component.exports.items) |export_item| {
            const key = try self.allocator.dupe(u8, export_item.name);
            // For now, use placeholder values - in a real implementation, these would be
            // properly initialized based on the component's export definitions
            try instance.exports.put(key, ComponentValue{ .bool = false });
        }
    }

    /// Import a module (similar to ES import statements)
    pub fn importModule(self: *Self, specifier: []const u8) !*ComponentInstance {
        // Check if module is already loaded
        if (self.module_registry.get(specifier)) |instance| {
            return instance;
        }

        // In a real implementation, this would fetch/load the module from the specifier
        // For now, we'll return an error indicating the module needs to be loaded first
        return ESMError.ModuleNotLoaded;
    }

    /// Link modules based on their import/export relationships (similar to ES module linking)
    pub fn linkModules(self: *Self) !void {
        // Resolve all import dependencies
        var it = self.module_registry.iterator();
        while (it.next()) |entry| {
            const module_name = entry.key_ptr.*;
            const instance = entry.value_ptr.*;

            // Resolve imports for this module
            try self.resolveModuleImports(module_name, instance);
        }
    }

    /// Execute a module's start function if it has one
    pub fn executeModule(self: *Self, module_name: []const u8) !void {
        const instance = self.module_registry.get(module_name) orelse return ESMError.ModuleNotFound;

        // If the component has a start function, execute it
        if (instance.component.start) |start_idx| {
            std.log.info("Executing start function {d} for module: {s}", .{ start_idx, module_name });
            // In a real implementation, this would actually execute the start function
            // _ = start_idx;
        }
    }

    pub fn getModule(self: *Self, module_name: []const u8) ?*ComponentInstance {
        return self.module_registry.get(module_name);
    }

    /// Unload a module and clean up its resources
    pub fn unloadModule(self: *Self, module_name: []const u8) !void {
        if (self.module_registry.fetchRemove(module_name)) |kv| {
            kv.value.deinit();
            self.allocator.destroy(kv.value);
            self.allocator.free(kv.key);
        } else {
            return ESMError.ModuleNotFound;
        }
    }
};

// Test function for component execution
pub fn testComponentExecution(allocator: std.mem.Allocator) !void {
    // Create a minimal component with one function
    var component = try Component.init(allocator);
    defer component.deinit();

    // Add a function type (bool -> bool)
    // For now, just add a bool type as placeholder
    try component.types.append(allocator, ComponentType{
        .tag = .bool,
        .payload = .{ .bool = {} },
    });

    // Add function
    try component.functions.append(allocator, 0); // Type index 0

    // Create function body that returns true
    const instructions = try allocator.alloc(ComponentInstruction, 2);
    instructions[0] = ComponentInstruction{ .@"const" = ComponentValue{ .bool = true } };
    instructions[1] = .@"return";

    const body = ComponentFunctionBody{
        .locals = &[_]ComponentValue{},
        .instructions = instructions,
    };
    // Note: body is owned by component, don't deinit here

    try component.function_bodies.append(allocator, body);

    // Create instance
    var instance = try ComponentInstance.init(allocator, &component);
    defer instance.deinit();

    // Create interpreter
    var interpreter = try ComponentInterpreter.init(allocator, &instance, null, null);
    defer interpreter.deinit();

    // Execute function
    const result = try interpreter.executeFunction(0, &[_]ComponentValue{});

    // Check result
    if (result.bool) {
        std.log.info("Component execution test passed", .{});
    } else {
        return error.TestFailed;
    }
}
