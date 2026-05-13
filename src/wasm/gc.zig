/// WebAssembly Garbage Collector
///
/// Implements automatic memory management for WASM modules:
/// - Mark-and-sweep collection
/// - Generational GC (young/old generations)
/// - Reference counting for optimization
/// - Support for WASM GC proposal types (struct, array, i31ref, etc.)
/// - Weak references
/// - Finalizers
const std = @import("std");
const Allocator = std.mem.Allocator;
const value = @import("value.zig");
const Value = value.Value;
const GCRef = value.GCRef;
const Log = @import("../util/fmt.zig").Log;

/// GC types from WASM GC proposal
pub const GCType = enum {
    structref,
    arrayref,
    i31ref,
    eqref,
    anyref,
    funcref,
    externref,
    nullref,
};

/// Object metadata for GC tracking
pub const ObjectHeader = struct {
    marked: bool = false,
    generation: Generation = .young,
    ref_count: u32 = 0,
    type: GCType,
    size: usize,
    has_finalizer: bool = false,
    weak_refs: std.ArrayList(*WeakRef) = undefined,

    pub const Generation = enum {
        young,
        old,
    };
};

/// Weak reference to a GC object
pub const WeakRef = struct {
    target: ?*Object = null,
    alive: bool = true,
};

/// GC-managed object
pub const Object = struct {
    header: ObjectHeader,
    data: []u8,

    pub fn init(allocator: Allocator, gc_type: GCType, size: usize) !*Object {
        const obj = try allocator.create(Object);
        obj.* = Object{
            .header = ObjectHeader{
                .type = gc_type,
                .size = size,
                .weak_refs = std.ArrayList(*WeakRef).init(allocator),
            },
            .data = try allocator.alloc(u8, size),
        };
        return obj;
    }

    pub fn deinit(self: *Object, allocator: Allocator) void {
        allocator.free(self.data);

        for (self.header.weak_refs.items) |weak_ref| {
            weak_ref.target = null;
            weak_ref.alive = false;
        }
        self.header.weak_refs.deinit(allocator);

        allocator.destroy(self);
    }
};

/// Finalizer callback
pub const Finalizer = struct {
    object: *Object,
    callback: *const fn (*Object) void,
};

/// Garbage Collector
pub const GC = struct {
    const Self = @This();

    allocator: Allocator,
    objects: std.ArrayList(*Object),
    roots: std.ArrayList(*Object),
    finalizers: std.ArrayList(Finalizer),

    // GC statistics
    stats: Stats,

    // GC configuration
    config: Config,

    // Allocation tracking
    bytes_allocated: usize = 0,
    bytes_freed: usize = 0,
    collection_count: usize = 0,

    pub const Stats = struct {
        total_collections: usize = 0,
        young_collections: usize = 0,
        full_collections: usize = 0,
        objects_collected: usize = 0,
        bytes_collected: usize = 0,
        last_collection_time_ns: i64 = 0,
    };

    pub const Config = struct {
        young_gen_threshold: usize = 1024 * 1024, // 1MB
        old_gen_threshold: usize = 8 * 1024 * 1024, // 8MB
        heap_growth_factor: f64 = 2.0,
        enable_ref_counting: bool = true,
        enable_generational: bool = true,
        enable_incremental: bool = false,
    };

    pub fn init(allocator: Allocator) !*Self {
        const gc = try allocator.create(Self);
        gc.* = Self{
            .allocator = allocator,
            .objects = std.ArrayList(*Object).init(allocator),
            .roots = std.ArrayList(*Object).init(allocator),
            .finalizers = std.ArrayList(Finalizer).init(allocator),
            .stats = Stats{},
            .config = Config{},
        };
        return gc;
    }

    pub fn deinit(self: *Self) void {
        // Run finalizers
        for (self.finalizers.items) |finalizer| {
            finalizer.callback(finalizer.object);
        }
        self.finalizers.deinit(self.allocator);

        // Free all objects
        for (self.objects.items) |obj| {
            obj.deinit(self.allocator);
        }
        self.objects.deinit(self.allocator);
        self.roots.deinit(self.allocator);

        self.allocator.destroy(self);
    }

    /// Allocate a new GC-managed object
    pub fn alloc(self: *Self, gc_type: GCType, size: usize) !*Object {
        const obj = try Object.init(self.allocator, gc_type, size);
        try self.objects.append(obj);

        self.bytes_allocated += size + @sizeOf(Object);

        // Check if we need to collect
        if (self.shouldCollect()) {
            try self.collect();
        }

        return obj;
    }

    /// Add a root object (prevents collection)
    pub fn addRoot(self: *Self, obj: *Object) !void {
        try self.roots.append(obj);
        if (self.config.enable_ref_counting) {
            obj.header.ref_count += 1;
        }
    }

    /// Remove a root object
    pub fn removeRoot(self: *Self, obj: *Object) void {
        for (self.roots.items, 0..) |root, i| {
            if (root == obj) {
                _ = self.roots.swapRemove(i);
                if (self.config.enable_ref_counting) {
                    obj.header.ref_count -= 1;
                }
                break;
            }
        }
    }

    /// Create a weak reference to an object
    pub fn createWeakRef(self: *Self, obj: *Object) !*WeakRef {
        const weak_ref = try self.allocator.create(WeakRef);
        weak_ref.* = WeakRef{ .target = obj, .alive = true };
        try obj.header.weak_refs.append(weak_ref);
        return weak_ref;
    }

    /// Register a finalizer for an object
    pub fn registerFinalizer(self: *Self, obj: *Object, callback: *const fn (*Object) void) !void {
        obj.header.has_finalizer = true;
        try self.finalizers.append(Finalizer{
            .object = obj,
            .callback = callback,
        });
    }

    /// Check if collection should be triggered
    fn shouldCollect(self: *Self) bool {
        return self.bytes_allocated > self.config.young_gen_threshold;
    }

    /// Perform garbage collection
    pub fn collect(self: *Self) !void {
        const start_time = @import("../util/time.zig").nanoTimestamp();

        if (self.config.enable_generational) {
            try self.collectYoung();
        } else {
            try self.collectFull();
        }

        const end_time = @import("../util/time.zig").nanoTimestamp();
        self.stats.last_collection_time_ns = end_time - start_time;
        self.stats.total_collections += 1;
        self.collection_count += 1;
    }

    /// Young generation collection (minor GC)
    fn collectYoung(self: *Self) !void {
        self.stats.young_collections += 1;

        // Mark phase
        try self.mark();

        // Sweep young generation only
        try self.sweepYoung();

        // Promote survivors to old generation
        self.promoteToOld();
    }

    /// Full collection (major GC)
    fn collectFull(self: *Self) !void {
        self.stats.full_collections += 1;

        // Mark phase
        try self.mark();

        // Sweep all generations
        try self.sweep();
    }

    /// Mark phase: mark all reachable objects
    fn mark(self: *Self) !void {
        // Clear all marks
        for (self.objects.items) |obj| {
            obj.header.marked = false;
        }

        // Mark from roots
        for (self.roots.items) |root| {
            try self.markObject(root);
        }
    }

    /// Mark a single object and its children
    fn markObject(self: *Self, obj: *Object) !void {
        if (obj.header.marked) return;

        obj.header.marked = true;

        // For reference types, recursively mark referenced objects
        switch (obj.header.type) {
            .structref, .arrayref => {
                // Parse object data to find references
                try self.markReferences(obj);
            },
            else => {},
        }
    }

    /// Mark references within an object
    fn markReferences(self: *Self, obj: *Object) !void {
        // This is a simplified version. In a real implementation,
        // we would parse the object's structure to find all references.
        _ = self;
        _ = obj;
    }

    /// Sweep phase: collect unmarked objects (young generation only)
    fn sweepYoung(self: *Self) !void {
        var i: usize = 0;
        while (i < self.objects.items.len) {
            const obj = self.objects.items[i];

            if (!obj.header.marked and obj.header.generation == .young) {
                // Run finalizer if present
                if (obj.header.has_finalizer) {
                    try self.runFinalizer(obj);
                }

                // Remove from list and free
                const removed = self.objects.swapRemove(i);
                self.bytes_freed += removed.header.size + @sizeOf(Object);
                self.stats.objects_collected += 1;
                self.stats.bytes_collected += removed.header.size;
                removed.deinit(self.allocator);
            } else {
                i += 1;
            }
        }
    }

    /// Sweep phase: collect all unmarked objects
    fn sweep(self: *Self) !void {
        var i: usize = 0;
        while (i < self.objects.items.len) {
            const obj = self.objects.items[i];

            if (!obj.header.marked) {
                // Run finalizer if present
                if (obj.header.has_finalizer) {
                    try self.runFinalizer(obj);
                }

                // Remove from list and free
                const removed = self.objects.swapRemove(i);
                self.bytes_freed += removed.header.size + @sizeOf(Object);
                self.stats.objects_collected += 1;
                self.stats.bytes_collected += removed.header.size;
                removed.deinit(self.allocator);
            } else {
                i += 1;
            }
        }
    }

    /// Promote young objects that survived collection to old generation
    fn promoteToOld(self: *Self) void {
        for (self.objects.items) |obj| {
            if (obj.header.marked and obj.header.generation == .young) {
                obj.header.generation = .old;
            }
        }
    }

    /// Run finalizer for an object
    fn runFinalizer(self: *Self, obj: *Object) !void {
        var i: usize = 0;
        while (i < self.finalizers.items.len) {
            if (self.finalizers.items[i].object == obj) {
                const finalizer = self.finalizers.swapRemove(i);
                finalizer.callback(finalizer.object);
                return;
            }
            i += 1;
        }
    }

    /// Force immediate collection
    pub fn forceCollect(self: *Self) !void {
        try self.collectFull();
    }

    /// Get current heap size
    pub fn heapSize(self: *Self) usize {
        return self.bytes_allocated - self.bytes_freed;
    }

    /// Get number of live objects
    pub fn objectCount(self: *Self) usize {
        return self.objects.items.len;
    }

    /// Print GC statistics
    pub fn printStats(self: *Self) void {
        std.debug.print("=== GC Statistics ===\n", .{});
        std.debug.print("Total collections: {d}\n", .{self.stats.total_collections});
        std.debug.print("Young collections: {d}\n", .{self.stats.young_collections});
        std.debug.print("Full collections: {d}\n", .{self.stats.full_collections});
        std.debug.print("Objects collected: {d}\n", .{self.stats.objects_collected});
        std.debug.print("Bytes collected: {d}\n", .{self.stats.bytes_collected});
        std.debug.print("Live objects: {d}\n", .{self.objectCount()});
        std.debug.print("Heap size: {d} bytes\n", .{self.heapSize()});
        std.debug.print("Last collection time: {d} ns\n", .{self.stats.last_collection_time_ns});
    }
};

/// Reference counting GC (alternative/supplementary strategy)
pub const RefCountGC = struct {
    const Self = @This();

    allocator: Allocator,
    objects: std.ArrayList(*RCObject),

    pub const RCObject = struct {
        ref_count: u32 = 1,
        data: []u8,
        type: GCType,

        pub fn retain(self: *RCObject) void {
            self.ref_count += 1;
        }

        pub fn release(self: *RCObject, allocator: Allocator) void {
            self.ref_count -= 1;
            if (self.ref_count == 0) {
                allocator.free(self.data);
                allocator.destroy(self);
            }
        }
    };

    pub fn init(allocator: Allocator) !*Self {
        const gc = try allocator.create(Self);
        gc.* = Self{
            .allocator = allocator,
            .objects = std.ArrayList(*RCObject).init(allocator),
        };
        return gc;
    }

    pub fn deinit(self: *Self) void {
        for (self.objects.items) |obj| {
            self.allocator.free(obj.data);
            self.allocator.destroy(obj);
        }
        self.objects.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn alloc(self: *Self, gc_type: GCType, size: usize) !*RCObject {
        const obj = try self.allocator.create(RCObject);
        obj.* = RCObject{
            .ref_count = 1,
            .data = try self.allocator.alloc(u8, size),
            .type = gc_type,
        };
        try self.objects.append(obj);
        return obj;
    }

    pub fn retain(self: *Self, obj: *RCObject) void {
        _ = self;
        obj.retain();
    }

    pub fn release(self: *Self, obj: *RCObject) void {
        obj.release(self.allocator);
    }
};

/// WASM GC instructions support
pub const GCInstructions = struct {
    /// struct.new - create a new struct
    pub fn structNew(gc: *GC, type_idx: u32, fields: []const Value) !*Object {
        _ = type_idx;
        const size = fields.len * @sizeOf(Value);
        const obj = try gc.alloc(.structref, size);

        // Copy field values
        const values = @as([*]Value, @ptrCast(@alignCast(obj.data.ptr)))[0..fields.len];
        @memcpy(values, fields);

        return obj;
    }

    /// array.new - create a new array
    pub fn arrayNew(gc: *GC, type_idx: u32, init: Value, length: u32) !*Object {
        _ = type_idx;
        const size = length * @sizeOf(Value);
        const obj = try gc.alloc(.arrayref, size);

        // Initialize array elements
        const values = @as([*]Value, @ptrCast(@alignCast(obj.data.ptr)))[0..length];
        for (values) |*v| {
            v.* = init;
        }

        return obj;
    }

    /// ref.eq - compare two references
    pub fn refEq(ref1: ?*Object, ref2: ?*Object) bool {
        return ref1 == ref2;
    }

    /// ref.is_null - check if reference is null
    pub fn refIsNull(ref: ?*Object) bool {
        return ref == null;
    }

    /// ref.as_non_null - assert reference is not null
    pub fn refAsNonNull(ref: ?*Object) !*Object {
        return ref orelse error.NullReference;
    }
};

// Simple GC heap implementation used by the runtime for GC proposal opcodes.
// This intentionally keeps a minimal API surface that matches the runtime needs
// (struct/array allocation and field access).
pub const Error = error{
    OutOfMemory,
    InvalidReference,
    TypeMismatch,
    NullReference,
};

pub const ObjectType = enum {
    struct_obj,
    array,
    string,
};

pub const FieldType = struct {
    mutable: bool,
    value_type: value.Type,
};

pub const StructType = struct {
    fields: []FieldType,
};

pub const ArrayType = struct {
    element_type: value.Type,
    mutable: bool,
};

pub const GCObject = struct {
    type: ObjectType,
    generation: u32,
    marked: bool,
    data: union {
        struct_obj: StructObject,
        array: ArrayObject,
        string: []const u8,
    },

    pub const StructObject = struct {
        type_index: u32,
        fields: []Value,
    };

    pub const ArrayObject = struct {
        element_type: value.Type,
        length: u32,
        elements: []Value,
    };
};

pub const GCHeap = struct {
    allocator: std.mem.Allocator,
    objects: std.ArrayList(GCObject),
    free_list: std.ArrayList(u32),
    generation: u32,
    struct_types: std.ArrayList(StructType),
    array_types: std.ArrayList(ArrayType),
    allocations: u64,
    collections: u64,
    bytes_allocated: u64,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !Self {
        var o = Log.op("GC", "init");
        o.log("Initializing GC heap", .{});

        return Self{
            .allocator = allocator,
            .objects = try std.ArrayList(GCObject).initCapacity(allocator, 0),
            .free_list = try std.ArrayList(u32).initCapacity(allocator, 0),
            .generation = 0,
            .struct_types = try std.ArrayList(StructType).initCapacity(allocator, 0),
            .array_types = try std.ArrayList(ArrayType).initCapacity(allocator, 0),
            .allocations = 0,
            .collections = 0,
            .bytes_allocated = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        var o = Log.op("GC", "deinit");
        o.log("Cleaning up GC heap (allocated: {d}, collected: {d})", .{
            self.allocations, self.collections,
        });

        for (self.objects.items) |*obj| {
            switch (obj.type) {
                .struct_obj => {
                    self.allocator.free(obj.data.struct_obj.fields);
                },
                .array => {
                    self.allocator.free(obj.data.array.elements);
                },
                .string => {
                    self.allocator.free(obj.data.string);
                },
            }
        }

        for (self.struct_types.items) |st| {
            self.allocator.free(st.fields);
        }

        self.objects.deinit(self.allocator);
        self.free_list.deinit(self.allocator);
        self.struct_types.deinit(self.allocator);
        self.array_types.deinit(self.allocator);
    }

    pub fn defineStructType(self: *Self, fields: []const FieldType) !u32 {
        const fields_copy = try self.allocator.dupe(FieldType, fields);
        try self.struct_types.append(self.allocator, .{ .fields = fields_copy });
        return @intCast(self.struct_types.items.len - 1);
    }

    pub fn defineArrayType(self: *Self, element_type: value.Type, mutable: bool) !u32 {
        try self.array_types.append(self.allocator, .{
            .element_type = element_type,
            .mutable = mutable,
        });
        return @intCast(self.array_types.items.len - 1);
    }

    pub fn allocStruct(self: *Self, type_index: u32, field_values: []const Value) !GCRef {
        var o = Log.op("GC", "allocStruct");

        if (type_index >= self.struct_types.items.len) return Error.TypeMismatch;

        const struct_type = self.struct_types.items[type_index];
        if (field_values.len != struct_type.fields.len) return Error.TypeMismatch;

        const fields = try self.allocator.dupe(Value, field_values);

        const obj = GCObject{
            .type = .struct_obj,
            .generation = self.generation,
            .marked = false,
            .data = .{
                .struct_obj = .{
                    .type_index = type_index,
                    .fields = fields,
                },
            },
        };

        const index = try self.addObject(obj);
        self.allocations += 1;
        self.bytes_allocated += field_values.len * @sizeOf(Value);

        o.log("Allocated struct (type={d}, index={d}, fields={d})", .{
            type_index, index, field_values.len,
        });

        return GCRef{ .index = index, .generation = self.generation };
    }

    pub fn allocArray(self: *Self, element_type: value.Type, length: u32, init_value: Value) !GCRef {
        var o = Log.op("GC", "allocArray");

        const elements = try self.allocator.alloc(Value, length);
        for (elements) |*elem| {
            elem.* = init_value;
        }

        const obj = GCObject{
            .type = .array,
            .generation = self.generation,
            .marked = false,
            .data = .{
                .array = .{
                    .element_type = element_type,
                    .length = length,
                    .elements = elements,
                },
            },
        };

        const index = try self.addObject(obj);
        self.allocations += 1;
        self.bytes_allocated += length * @sizeOf(Value);

        o.log("Allocated array (type={any}, length={d}, index={d})", .{
            element_type, length, index,
        });

        return GCRef{ .index = index, .generation = self.generation };
    }

    fn addObject(self: *Self, obj: GCObject) !u32 {
        if (self.free_list.items.len > 0) {
            const index = self.free_list.pop().?;
            self.objects.items[index] = obj;
            return index;
        }

        try self.objects.append(self.allocator, obj);
        return @intCast(self.objects.items.len - 1);
    }

    pub fn getObject(self: *Self, ref: GCRef) Error!*GCObject {
        if (ref.is_null()) return Error.NullReference;
        if (ref.index >= self.objects.items.len) return Error.InvalidReference;
        return &self.objects.items[ref.index];
    }

    pub fn structGet(self: *Self, ref: GCRef, field_index: u32) Error!Value {
        const obj = try self.getObject(ref);
        if (obj.type != .struct_obj) return Error.TypeMismatch;

        const struct_obj = obj.data.struct_obj;
        if (field_index >= struct_obj.fields.len) return Error.InvalidReference;

        return struct_obj.fields[field_index];
    }

    pub fn structSet(self: *Self, ref: GCRef, field_index: u32, val: Value) Error!void {
        const obj = try self.getObject(ref);
        if (obj.type != .struct_obj) return Error.TypeMismatch;

        var struct_obj = &obj.data.struct_obj;
        if (field_index >= struct_obj.fields.len) return Error.InvalidReference;

        const struct_type = self.struct_types.items[struct_obj.type_index];
        if (!struct_type.fields[field_index].mutable) return Error.TypeMismatch;

        struct_obj.fields[field_index] = val;
    }

    pub fn arrayGet(self: *Self, ref: GCRef, index: u32) Error!Value {
        const obj = try self.getObject(ref);
        if (obj.type != .array) return Error.TypeMismatch;

        const array_obj = obj.data.array;
        if (index >= array_obj.length) return Error.InvalidReference;

        return array_obj.elements[index];
    }

    pub fn arraySet(self: *Self, ref: GCRef, index: u32, val: Value) Error!void {
        const obj = try self.getObject(ref);
        if (obj.type != .array) return Error.TypeMismatch;

        const array_obj = &obj.data.array;
        if (index >= array_obj.length) return Error.InvalidReference;

        array_obj.elements[index] = val;
    }

    pub fn arrayLen(self: *Self, ref: GCRef) Error!u32 {
        const obj = try self.getObject(ref);
        if (obj.type != .array) return Error.TypeMismatch;
        return obj.data.array.length;
    }

    pub fn collect(self: *Self, roots: []const Value) !void {
        var o = Log.op("GC", "collect");
        const before_count = self.objects.items.len - self.free_list.items.len;
        o.log("Starting GC (live objects: {d})", .{before_count});

        for (self.objects.items) |*obj| {
            obj.marked = false;
        }

        for (roots) |root_val| {
            try self.mark(root_val);
        }

        var freed: u32 = 0;
        for (self.objects.items, 0..) |*obj, i| {
            if (!obj.marked) {
                switch (obj.type) {
                    .struct_obj => {
                        self.allocator.free(obj.data.struct_obj.fields);
                    },
                    .array => {
                        self.allocator.free(obj.data.array.elements);
                    },
                    .string => {
                        self.allocator.free(obj.data.string);
                    },
                }

                try self.free_list.append(self.allocator, @intCast(i));
                freed += 1;
            }
        }

        self.collections += 1;
        const after_count = before_count - freed;
        o.log("GC complete (freed: {d}, live: {d})", .{ freed, after_count });
    }

    fn mark(self: *Self, val: Value) Error!void {
        const ref = switch (val) {
            .structref => |r| r,
            .arrayref => |r| r,
            .anyref => |r| r,
            .eqref => |r| r,
            else => return,
        };

        if (ref.is_null()) return;

        const obj = try self.getObject(ref);
        if (obj.marked) return;
        obj.marked = true;

        switch (obj.type) {
            .struct_obj => {
                for (obj.data.struct_obj.fields) |field| {
                    try self.mark(field);
                }
            },
            .array => {
                for (obj.data.array.elements) |elem| {
                    try self.mark(elem);
                }
            },
            .string => {},
        }
    }
};
