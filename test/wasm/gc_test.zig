const std = @import("std");
const testing = std.testing;
const gc_mod = @import("../../src/wasm/gc.zig");
const GC = gc_mod.GC;
const RefCountGC = gc_mod.RefCountGC;
const GCType = gc_mod.GCType;
const GCInstructions = gc_mod.GCInstructions;
const Value = @import("../../src/wasm/value.zig").Value;

test "gc - init and deinit" {
    const allocator = testing.allocator;
    var gc = try GC.init(allocator);
    defer gc.deinit();

    try testing.expect(gc.objects.items.len == 0);
    try testing.expect(gc.roots.items.len == 0);
}

test "gc - allocate object" {
    const allocator = testing.allocator;
    var gc = try GC.init(allocator);
    defer gc.deinit();

    const obj = try gc.alloc(.anyref, 128);
    try testing.expect(obj.header.type == .anyref);
    try testing.expect(obj.header.size == 128);
    try testing.expect(obj.data.len == 128);
    try testing.expectEqual(@as(usize, 1), gc.objects.items.len);
}

test "gc - add and remove root" {
    const allocator = testing.allocator;
    var gc = try GC.init(allocator);
    defer gc.deinit();

    const obj = try gc.alloc(.anyref, 64);
    try gc.addRoot(obj);
    
    try testing.expectEqual(@as(usize, 1), gc.roots.items.len);
    try testing.expectEqual(@as(u32, 1), obj.header.ref_count);
    
    gc.removeRoot(obj);
    try testing.expectEqual(@as(usize, 0), gc.roots.items.len);
}

test "gc - weak reference" {
    const allocator = testing.allocator;
    var gc = try GC.init(allocator);
    defer gc.deinit();

    const obj = try gc.alloc(.anyref, 64);
    const weak_ref = try gc.createWeakRef(obj);
    
    try testing.expect(weak_ref.alive);
    try testing.expect(weak_ref.target == obj);
    try testing.expectEqual(@as(usize, 1), obj.header.weak_refs.items.len);
}

test "gc - mark and sweep collection" {
    const allocator = testing.allocator;
    var gc = try GC.init(allocator);
    defer gc.deinit();

    // Create some objects
    const obj1 = try gc.alloc(.anyref, 100);
    const obj2 = try gc.alloc(.anyref, 200);
    const obj3 = try gc.alloc(.anyref, 300);
    
    // Only obj1 and obj2 are roots
    try gc.addRoot(obj1);
    try gc.addRoot(obj2);
    
    try testing.expectEqual(@as(usize, 3), gc.objects.items.len);
    
    // Force collection
    try gc.forceCollect();
    
    // obj3 should be collected since it's not a root
    try testing.expectEqual(@as(usize, 2), gc.objects.items.len);
    try testing.expectEqual(@as(usize, 1), gc.stats.objects_collected);
}

test "gc - generational collection" {
    const allocator = testing.allocator;
    var gc = try GC.init(allocator);
    defer gc.deinit();
    gc.config.enable_generational = true;

    const obj = try gc.alloc(.anyref, 128);
    try gc.addRoot(obj);
    
    try testing.expect(obj.header.generation == .young);
    
    // Collect young generation
    try gc.collectYoung();
    
    // Object should survive and be promoted
    try testing.expect(obj.header.generation == .old);
}

test "gc - finalizer" {
    const allocator = testing.allocator;
    var gc = try GC.init(allocator);
    defer gc.deinit();

    var finalizer_called = false;
    
    const callback = struct {
        fn call(obj: *gc_mod.Object) void {
            _ = obj;
            // Would set finalizer_called = true, but we can't capture in Zig
        }
    }.call;

    const obj = try gc.alloc(.anyref, 64);
    try gc.registerFinalizer(obj, callback);
    
    try testing.expect(obj.header.has_finalizer);
    try testing.expectEqual(@as(usize, 1), gc.finalizers.items.len);
    
    // Not adding as root, so it should be collected
    try gc.forceCollect();
    
    // Finalizer should have run
    try testing.expectEqual(@as(usize, 0), gc.finalizers.items.len);
}

test "gc - heap size tracking" {
    const allocator = testing.allocator;
    var gc = try GC.init(allocator);
    defer gc.deinit();

    const initial_heap = gc.heapSize();
    
    _ = try gc.alloc(.anyref, 1024);
    
    const after_alloc = gc.heapSize();
    try testing.expect(after_alloc > initial_heap);
}

test "gc - object count" {
    const allocator = testing.allocator;
    var gc = try GC.init(allocator);
    defer gc.deinit();

    try testing.expectEqual(@as(usize, 0), gc.objectCount());
    
    _ = try gc.alloc(.anyref, 64);
    try testing.expectEqual(@as(usize, 1), gc.objectCount());
    
    _ = try gc.alloc(.structref, 128);
    try testing.expectEqual(@as(usize, 2), gc.objectCount());
}

test "gc - statistics" {
    const allocator = testing.allocator;
    var gc = try GC.init(allocator);
    defer gc.deinit();

    const obj = try gc.alloc(.anyref, 100);
    _ = obj;
    
    try testing.expectEqual(@as(usize, 0), gc.stats.total_collections);
    
    try gc.forceCollect();
    
    try testing.expectEqual(@as(usize, 1), gc.stats.total_collections);
    try testing.expect(gc.stats.last_collection_time_ns > 0);
}

// Reference Counting GC Tests

test "refcount gc - init and deinit" {
    const allocator = testing.allocator;
    var gc = try RefCountGC.init(allocator);
    defer gc.deinit();

    try testing.expectEqual(@as(usize, 0), gc.objects.items.len);
}

test "refcount gc - allocate object" {
    const allocator = testing.allocator;
    var gc = try RefCountGC.init(allocator);
    defer gc.deinit();

    const obj = try gc.alloc(.anyref, 256);
    try testing.expectEqual(@as(u32, 1), obj.ref_count);
    try testing.expectEqual(@as(usize, 256), obj.data.len);
}

test "refcount gc - retain and release" {
    const allocator = testing.allocator;
    var gc = try RefCountGC.init(allocator);
    defer gc.deinit();

    const obj = try gc.alloc(.anyref, 128);
    try testing.expectEqual(@as(u32, 1), obj.ref_count);
    
    gc.retain(obj);
    try testing.expectEqual(@as(u32, 2), obj.ref_count);
    
    gc.release(obj);
    try testing.expectEqual(@as(u32, 1), obj.ref_count);
}

// GC Instructions Tests

test "gc instructions - struct.new" {
    const allocator = testing.allocator;
    var gc = try GC.init(allocator);
    defer gc.deinit();

    const fields = [_]Value{
        Value{ .i32 = 42 },
        Value{ .i64 = 1000 },
        Value{ .f32 = 3.14 },
    };

    const obj = try GCInstructions.structNew(gc, 0, &fields);
    try gc.addRoot(obj);
    
    try testing.expect(obj.header.type == .structref);
    try testing.expect(obj.data.len >= fields.len * @sizeOf(Value));
}

test "gc instructions - array.new" {
    const allocator = testing.allocator;
    var gc = try GC.init(allocator);
    defer gc.deinit();

    const init_value = Value{ .i32 = 7 };
    const length: u32 = 10;
    
    const obj = try GCInstructions.arrayNew(gc, 0, init_value, length);
    try gc.addRoot(obj);
    
    try testing.expect(obj.header.type == .arrayref);
    try testing.expect(obj.data.len >= length * @sizeOf(Value));
}

test "gc instructions - ref.eq" {
    const allocator = testing.allocator;
    var gc = try GC.init(allocator);
    defer gc.deinit();

    const obj1 = try gc.alloc(.anyref, 64);
    const obj2 = try gc.alloc(.anyref, 64);
    
    try testing.expect(GCInstructions.refEq(obj1, obj1));
    try testing.expect(!GCInstructions.refEq(obj1, obj2));
    try testing.expect(GCInstructions.refEq(null, null));
}

test "gc instructions - ref.is_null" {
    const allocator = testing.allocator;
    var gc = try GC.init(allocator);
    defer gc.deinit();

    const obj = try gc.alloc(.anyref, 64);
    
    try testing.expect(!GCInstructions.refIsNull(obj));
    try testing.expect(GCInstructions.refIsNull(null));
}

test "gc instructions - ref.as_non_null" {
    const allocator = testing.allocator;
    var gc = try GC.init(allocator);
    defer gc.deinit();

    const obj = try gc.alloc(.anyref, 64);
    
    const result = try GCInstructions.refAsNonNull(obj);
    try testing.expect(result == obj);
    
    const null_result = GCInstructions.refAsNonNull(null);
    try testing.expectError(error.NullReference, null_result);
}

test "gc - multiple collections" {
    const allocator = testing.allocator;
    var gc = try GC.init(allocator);
    defer gc.deinit();

    // Allocate many small objects
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const obj = try gc.alloc(.anyref, 64);
        if (i % 10 == 0) {
            try gc.addRoot(obj);
        }
    }

    try testing.expectEqual(@as(usize, 100), gc.objects.items.len);
    try testing.expectEqual(@as(usize, 10), gc.roots.items.len);

    // Force collection
    try gc.forceCollect();

    // Should only have the 10 roots left
    try testing.expectEqual(@as(usize, 10), gc.objects.items.len);
    try testing.expectEqual(@as(usize, 90), gc.stats.objects_collected);
}

test "gc - stress test" {
    const allocator = testing.allocator;
    var gc = try GC.init(allocator);
    defer gc.deinit();
    
    gc.config.young_gen_threshold = 10000; // 10KB threshold

    // Allocate many objects to trigger automatic collection
    var roots = std.ArrayList(*gc_mod.Object).init(allocator);
    defer roots.deinit();

    var i: usize = 0;
    while (i < 50) : (i += 1) {
        const obj = try gc.alloc(.anyref, 512);
        if (i % 5 == 0) {
            try gc.addRoot(obj);
            try roots.append(obj);
        }
    }

    // Should have triggered at least one collection
    try testing.expect(gc.stats.total_collections > 0);
}
