/// WASI GC Interface - WebAssembly Garbage Collection API
/// Provides managed memory allocation and automatic garbage collection
const std = @import("std");
const Allocator = std.mem.Allocator;
const GC = @import("../gc.zig");

pub const GCError = error{
    OutOfMemory,
    InvalidReference,
    InvalidType,
    CollectionInProgress,
    FinalizerError,
};

pub const GCHandle = u32;
pub const WeakHandle = u32;

pub const GCObjectType = enum(u8) {
    struct_ref = 0,
    array_ref = 1,
    i31_ref = 2,
    eq_ref = 3,
    any_ref = 4,
    func_ref = 5,
    extern_ref = 6,
    null_ref = 7,
};

pub const StructField = struct {
    type: GCObjectType,
    mutable: bool,
    offset: u32,
};

pub const StructType = struct {
    fields: []const StructField,
    size: u32,
    alignment: u32,
};

pub const ArrayType = struct {
    element_type: GCObjectType,
    element_size: u32,
    mutable: bool,
};

pub const WasiGC = struct {
    allocator: Allocator,
    gc: *GC.GarbageCollector,
    handles: std.AutoHashMap(GCHandle, *GC.Object),
    weak_handles: std.AutoHashMap(WeakHandle, *GC.WeakRef),
    next_handle: GCHandle,
    next_weak_handle: WeakHandle,
    struct_types: std.ArrayList(StructType),
    array_types: std.ArrayList(ArrayType),

    pub fn init(allocator: Allocator) !*WasiGC {
        const wasi_gc = try allocator.create(WasiGC);
        wasi_gc.* = WasiGC{
            .allocator = allocator,
            .gc = try GC.GarbageCollector.init(allocator),
            .handles = std.AutoHashMap(GCHandle, *GC.Object).init(allocator),
            .weak_handles = std.AutoHashMap(WeakHandle, *GC.WeakRef).init(allocator),
            .next_handle = 1,
            .next_weak_handle = 1,
            .struct_types = std.ArrayList(StructType).init(allocator),
            .array_types = std.ArrayList(ArrayType).init(allocator),
        };
        return wasi_gc;
    }

    pub fn deinit(self: *WasiGC) void {
        self.handles.deinit();
        self.weak_handles.deinit();
        self.struct_types.deinit();
        self.array_types.deinit();
        self.gc.deinit();
        self.allocator.destroy(self);
    }

    /// Register a new struct type
    pub fn registerStructType(self: *WasiGC, fields: []const StructField) !u32 {
        var total_size: u32 = 0;
        var max_alignment: u32 = 1;

        for (fields) |field| {
            const field_size = switch (field.type) {
                .i31_ref => 4,
                .struct_ref, .array_ref, .any_ref, .func_ref, .extern_ref => 8,
                else => 8,
            };
            const field_alignment = field_size;

            // Align current size to field alignment
            total_size = std.mem.alignForward(u32, total_size, field_alignment);
            total_size += field_size;
            max_alignment = @max(max_alignment, field_alignment);
        }

        // Align total size to struct alignment
        total_size = std.mem.alignForward(u32, total_size, max_alignment);

        const struct_type = StructType{
            .fields = try self.allocator.dupe(StructField, fields),
            .size = total_size,
            .alignment = max_alignment,
        };

        try self.struct_types.append(struct_type);
        return @intCast(self.struct_types.items.len - 1);
    }

    /// Register a new array type
    pub fn registerArrayType(self: *WasiGC, element_type: GCObjectType, mutable: bool) !u32 {
        const element_size = switch (element_type) {
            .i31_ref => 4,
            .struct_ref, .array_ref, .any_ref, .func_ref, .extern_ref => 8,
            else => 8,
        };

        const array_type = ArrayType{
            .element_type = element_type,
            .element_size = element_size,
            .mutable = mutable,
        };

        try self.array_types.append(array_type);
        return @intCast(self.array_types.items.len - 1);
    }

    /// Allocate a new struct object
    pub fn structNew(self: *WasiGC, type_index: u32, field_values: []const u64) !GCHandle {
        if (type_index >= self.struct_types.items.len) {
            return GCError.InvalidType;
        }

        const struct_type = self.struct_types.items[type_index];
        if (field_values.len != struct_type.fields.len) {
            return GCError.InvalidType;
        }

        const obj = try self.gc.allocateStruct(struct_type.size, .structref);

        // Initialize fields
        var offset: u32 = 0;
        for (struct_type.fields, 0..) |field, i| {
            offset = std.mem.alignForward(u32, offset, switch (field.type) {
                .i31_ref => 4,
                else => 8,
            });

            const field_ptr = @as([*]u8, @ptrCast(obj.data.ptr)) + offset;
            switch (field.type) {
                .i31_ref => {
                    @as(*u32, @ptrCast(@alignCast(field_ptr))).* = @intCast(field_values[i]);
                },
                else => {
                    @as(*u64, @ptrCast(@alignCast(field_ptr))).* = field_values[i];
                },
            }

            offset += switch (field.type) {
                .i31_ref => 4,
                else => 8,
            };
        }

        const handle = self.next_handle;
        self.next_handle += 1;
        try self.handles.put(handle, obj);

        return handle;
    }

    /// Get a field value from a struct
    pub fn structGet(self: *WasiGC, handle: GCHandle, field_index: u32) !u64 {
        const obj = self.handles.get(handle) orelse return GCError.InvalidReference;

        if (obj.header.type != .structref) {
            return GCError.InvalidType;
        }

        // Find struct type (simplified - in real implementation would store type info in object)
        if (self.struct_types.items.len == 0) {
            return GCError.InvalidType;
        }

        const struct_type = self.struct_types.items[0]; // Simplified
        if (field_index >= struct_type.fields.len) {
            return GCError.InvalidType;
        }

        const field = struct_type.fields[field_index];
        var offset: u32 = 0;

        // Calculate field offset
        for (struct_type.fields[0..field_index]) |prev_field| {
            offset = std.mem.alignForward(u32, offset, switch (prev_field.type) {
                .i31_ref => 4,
                else => 8,
            });
            offset += switch (prev_field.type) {
                .i31_ref => 4,
                else => 8,
            };
        }

        offset = std.mem.alignForward(u32, offset, switch (field.type) {
            .i31_ref => 4,
            else => 8,
        });

        const field_ptr = @as([*]u8, @ptrCast(obj.data.ptr)) + offset;
        return switch (field.type) {
            .i31_ref => @as(*u32, @ptrCast(@alignCast(field_ptr))).*,
            else => @as(*u64, @ptrCast(@alignCast(field_ptr))).*,
        };
    }

    /// Set a field value in a struct
    pub fn structSet(self: *WasiGC, handle: GCHandle, field_index: u32, value: u64) !void {
        const obj = self.handles.get(handle) orelse return GCError.InvalidReference;

        if (obj.header.type != .structref) {
            return GCError.InvalidType;
        }

        // Similar to structGet but for setting values
        if (self.struct_types.items.len == 0) {
            return GCError.InvalidType;
        }

        const struct_type = self.struct_types.items[0]; // Simplified
        if (field_index >= struct_type.fields.len) {
            return GCError.InvalidType;
        }

        const field = struct_type.fields[field_index];
        if (!field.mutable) {
            return GCError.InvalidType;
        }

        var offset: u32 = 0;
        for (struct_type.fields[0..field_index]) |prev_field| {
            offset = std.mem.alignForward(u32, offset, switch (prev_field.type) {
                .i31_ref => 4,
                else => 8,
            });
            offset += switch (prev_field.type) {
                .i31_ref => 4,
                else => 8,
            };
        }

        offset = std.mem.alignForward(u32, offset, switch (field.type) {
            .i31_ref => 4,
            else => 8,
        });

        const field_ptr = @as([*]u8, @ptrCast(obj.data.ptr)) + offset;
        switch (field.type) {
            .i31_ref => {
                @as(*u32, @ptrCast(@alignCast(field_ptr))).* = @intCast(value);
            },
            else => {
                @as(*u64, @ptrCast(@alignCast(field_ptr))).* = value;
            },
        }
    }

    /// Allocate a new array object
    pub fn arrayNew(self: *WasiGC, type_index: u32, length: u32, init_value: u64) !GCHandle {
        if (type_index >= self.array_types.items.len) {
            return GCError.InvalidType;
        }

        const array_type = self.array_types.items[type_index];
        const total_size = array_type.element_size * length;

        const obj = try self.gc.allocateArray(total_size, .arrayref);

        // Initialize all elements
        var i: u32 = 0;
        while (i < length) : (i += 1) {
            const element_ptr = @as([*]u8, @ptrCast(obj.data.ptr)) + (i * array_type.element_size);
            switch (array_type.element_type) {
                .i31_ref => {
                    @as(*u32, @ptrCast(@alignCast(element_ptr))).* = @intCast(init_value);
                },
                else => {
                    @as(*u64, @ptrCast(@alignCast(element_ptr))).* = init_value;
                },
            }
        }

        const handle = self.next_handle;
        self.next_handle += 1;
        try self.handles.put(handle, obj);

        return handle;
    }

    /// Get array length
    pub fn arrayLen(self: *WasiGC, handle: GCHandle) !u32 {
        const obj = self.handles.get(handle) orelse return GCError.InvalidReference;

        if (obj.header.type != .arrayref) {
            return GCError.InvalidType;
        }

        // Array length is stored in the first 4 bytes (simplified)
        return @intCast(obj.data.len / 8); // Assuming 8-byte elements for simplicity
    }

    /// Get array element
    pub fn arrayGet(self: *WasiGC, handle: GCHandle, index: u32) !u64 {
        const obj = self.handles.get(handle) orelse return GCError.InvalidReference;

        if (obj.header.type != .arrayref) {
            return GCError.InvalidType;
        }

        const element_size = 8; // Simplified
        if (index * element_size >= obj.data.len) {
            return GCError.InvalidReference;
        }

        const element_ptr = @as([*]u8, @ptrCast(obj.data.ptr)) + (index * element_size);
        return @as(*u64, @ptrCast(@alignCast(element_ptr))).*;
    }

    /// Set array element
    pub fn arraySet(self: *WasiGC, handle: GCHandle, index: u32, value: u64) !void {
        const obj = self.handles.get(handle) orelse return GCError.InvalidReference;

        if (obj.header.type != .arrayref) {
            return GCError.InvalidType;
        }

        const element_size = 8; // Simplified
        if (index * element_size >= obj.data.len) {
            return GCError.InvalidReference;
        }

        const element_ptr = @as([*]u8, @ptrCast(obj.data.ptr)) + (index * element_size);
        @as(*u64, @ptrCast(@alignCast(element_ptr))).* = value;
    }

    /// Create i31 reference
    pub fn i31New(self: *WasiGC, value: i32) !GCHandle {
        const obj = try self.gc.allocateI31(@bitCast(value));

        const handle = self.next_handle;
        self.next_handle += 1;
        try self.handles.put(handle, obj);

        return handle;
    }

    /// Get i31 value
    pub fn i31Get(self: *WasiGC, handle: GCHandle) !i32 {
        const obj = self.handles.get(handle) orelse return GCError.InvalidReference;

        if (obj.header.type != .i31ref) {
            return GCError.InvalidType;
        }

        return @bitCast(@as(*u32, @ptrCast(@alignCast(obj.data.ptr))).*);
    }

    /// Create weak reference
    pub fn weakNew(self: *WasiGC, handle: GCHandle) !WeakHandle {
        const obj = self.handles.get(handle) orelse return GCError.InvalidReference;

        const weak_ref = try self.gc.createWeakRef(obj);

        const weak_handle = self.next_weak_handle;
        self.next_weak_handle += 1;
        try self.weak_handles.put(weak_handle, weak_ref);

        return weak_handle;
    }

    /// Get object from weak reference
    pub fn weakGet(self: *WasiGC, weak_handle: WeakHandle) !?GCHandle {
        const weak_ref = self.weak_handles.get(weak_handle) orelse return GCError.InvalidReference;

        if (weak_ref.target) |obj| {
            // Find handle for this object
            var iter = self.handles.iterator();
            while (iter.next()) |entry| {
                if (entry.value_ptr.* == obj) {
                    return entry.key_ptr.*;
                }
            }
        }

        return null;
    }

    /// Force garbage collection
    pub fn collect(self: *WasiGC) !void {
        try self.gc.collect();
    }

    /// Get GC statistics
    pub fn getStats(self: *WasiGC) GC.GCStats {
        return self.gc.getStats();
    }
};
