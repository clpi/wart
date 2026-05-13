const std = @import("std");

// This would be imported from wart runtime in actual use
const GC = @import("../src/wasm/gc.zig").GC;
const GCType = @import("../src/wasm/gc.zig").GCType;
const GCInstructions = @import("../src/wasm/gc.zig").GCInstructions;
const Value = @import("../src/wasm/value.zig").Value;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("=== WebAssembly Garbage Collector Demo ===\n\n", .{});

    // Initialize GC
    var gc = try GC.init(allocator);
    defer gc.deinit();

    std.debug.print("1. Creating GC-managed objects:\n", .{});
    const obj1 = try gc.alloc(.anyref, 1024);
    const obj2 = try gc.alloc(.structref, 512);
    const obj3 = try gc.alloc(.arrayref, 2048);
    std.debug.print("   Created 3 objects (total: {d} bytes)\n", .{gc.heapSize()});
    std.debug.print("   Object count: {d}\n\n", .{gc.objectCount()});

    // Add roots to prevent collection
    std.debug.print("2. Adding root objects:\n", .{});
    try gc.addRoot(obj1);
    try gc.addRoot(obj2);
    std.debug.print("   Added 2 roots, obj3 is unreachable\n\n", .{});

    // Create weak references
    std.debug.print("3. Creating weak references:\n", .{});
    const weak_ref = try gc.createWeakRef(obj1);
    std.debug.print("   Weak reference alive: {}\n", .{weak_ref.alive});
    std.debug.print("   Target object: {*}\n\n", .{weak_ref.target});

    // Perform garbage collection
    std.debug.print("4. Performing garbage collection:\n", .{});
    try gc.collect();
    std.debug.print("   Objects collected: {d}\n", .{gc.stats.objects_collected});
    std.debug.print("   Remaining objects: {d}\n", .{gc.objectCount()});
    std.debug.print("   Heap size: {d} bytes\n\n", .{gc.heapSize()});

    // Create struct using WASM GC instructions
    std.debug.print("5. Using WASM GC instructions (struct.new):\n", .{});
    const fields = [_]Value{
        Value{ .i32 = 42 },
        Value{ .i64 = 1000 },
        Value{ .f32 = 3.14 },
    };
    const struct_obj = try GCInstructions.structNew(gc, 0, &fields);
    try gc.addRoot(struct_obj);
    std.debug.print("   Created struct with {d} fields\n\n", .{fields.len});

    // Create array using WASM GC instructions
    std.debug.print("6. Using WASM GC instructions (array.new):\n", .{});
    const init_value = Value{ .i32 = 7 };
    const length: u32 = 100;
    const array_obj = try GCInstructions.arrayNew(gc, 0, init_value, length);
    try gc.addRoot(array_obj);
    std.debug.print("   Created array with {d} elements\n\n", .{length});

    // Test reference equality
    std.debug.print("7. Testing reference operations:\n", .{});
    std.debug.print("   obj1 == obj1: {}\n", .{GCInstructions.refEq(obj1, obj1)});
    std.debug.print("   obj1 == obj2: {}\n", .{GCInstructions.refEq(obj1, obj2)});
    std.debug.print("   obj1 is null: {}\n", .{GCInstructions.refIsNull(obj1)});
    std.debug.print("   null is null: {}\n\n", .{GCInstructions.refIsNull(null)});

    // Show final statistics
    std.debug.print("8. Final GC Statistics:\n", .{});
    gc.printStats();
}
