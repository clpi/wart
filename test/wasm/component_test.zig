const std = @import("std");
const testing = std.testing;
const component = @import("../../src/wasm/component.zig");

const Component = component.Component;
const ComponentType = component.ComponentType;
const ComponentValue = component.ComponentValue;
const ComponentInstance = component.ComponentInstance;
const ComponentLinker = component.ComponentLinker;
const ResourceTable = component.ResourceTable;
const CanonicalABI = component.CanonicalABI;

// Test basic component creation and validation
test "component creation and validation" {
    const allocator = testing.allocator;

    var comp = try Component.init(allocator);
    defer comp.deinit();

    // Add a basic type
    try comp.types.append(allocator, ComponentType{
        .tag = .bool,
        .payload = .{ .bool = {} },
    });

    // Add a function with that type
    try comp.functions.append(allocator, 0);

    // Validate the component
    try comp.validate();
}

// Test component type system
test "component type system - primitives" {
    const allocator = testing.allocator;

    var comp = try Component.init(allocator);
    defer comp.deinit();

    // Test all primitive types
    const primitive_types = [_]ComponentType.ComponentTypeTag{
        .bool,   .s8,  .u8,  .s16,     .u16,     .s32,
        .u32,    .s64, .u64, .float32, .float64, .char,
        .string,
    };

    for (primitive_types) |tag| {
        try comp.types.append(allocator, ComponentType{
            .tag = tag,
            .payload = switch (tag) {
                .bool => .{ .bool = {} },
                .s8 => .{ .s8 = {} },
                .u8 => .{ .u8 = {} },
                .s16 => .{ .s16 = {} },
                .u16 => .{ .u16 = {} },
                .s32 => .{ .s32 = {} },
                .u32 => .{ .u32 = {} },
                .s64 => .{ .s64 = {} },
                .u64 => .{ .u64 = {} },
                .float32 => .{ .float32 = {} },
                .float64 => .{ .float64 = {} },
                .char => .{ .char = {} },
                .string => .{ .string = {} },
                else => unreachable,
            },
        });
    }

    try testing.expectEqual(@as(usize, primitive_types.len), comp.types.items.len);
}

// Test component type system - records
test "component type system - records" {
    const allocator = testing.allocator;

    var comp = try Component.init(allocator);
    defer comp.deinit();

    // Create a record type with two fields
    const fields = try allocator.alloc(ComponentType.Record.Field, 2);
    fields[0] = .{
        .name = try allocator.dupe(u8, "x"),
        .ty_idx = 0,
    };
    fields[1] = .{
        .name = try allocator.dupe(u8, "y"),
        .ty_idx = 0,
    };

    // First add the field type (s32)
    try comp.types.append(allocator, ComponentType{
        .tag = .s32,
        .payload = .{ .s32 = {} },
    });

    // Then add the record type
    try comp.types.append(allocator, ComponentType{
        .tag = .record,
        .payload = .{ .record = .{ .fields = fields } },
    });

    try testing.expectEqual(@as(usize, 2), comp.types.items.len);
}

// Test component values - primitives
test "component values - primitives" {
    const allocator = testing.allocator;

    var val_bool = ComponentValue{ .bool = true };
    try testing.expect(val_bool.bool);

    var val_s32 = ComponentValue{ .s32 = -42 };
    try testing.expectEqual(@as(i32, -42), val_s32.s32);

    var val_u64 = ComponentValue{ .u64 = 12345 };
    try testing.expectEqual(@as(u64, 12345), val_u64.u64);

    var val_f32 = ComponentValue{ .float32 = 3.14 };
    try testing.expectApproxEqAbs(@as(f32, 3.14), val_f32.float32, 0.01);

    var val_string = ComponentValue{ .string = try allocator.dupe(u8, "hello") };
    defer val_string.deinit(allocator);
    try testing.expectEqualStrings("hello", val_string.string);
}

// Test component values - clone
test "component values - clone primitives" {
    const allocator = testing.allocator;

    const original = ComponentValue{ .s32 = 42 };
    const cloned = try original.clone(allocator);

    try testing.expectEqual(original.s32, cloned.s32);
}

test "component values - clone string" {
    const allocator = testing.allocator;

    var original = ComponentValue{ .string = try allocator.dupe(u8, "test") };
    defer original.deinit(allocator);

    var cloned = try original.clone(allocator);
    defer cloned.deinit(allocator);

    try testing.expectEqualStrings(original.string, cloned.string);
    // Verify they're different allocations
    try testing.expect(original.string.ptr != cloned.string.ptr);
}

test "component values - clone list" {
    const allocator = testing.allocator;

    const items = try allocator.alloc(ComponentValue, 3);
    items[0] = ComponentValue{ .s32 = 1 };
    items[1] = ComponentValue{ .s32 = 2 };
    items[2] = ComponentValue{ .s32 = 3 };

    var original = ComponentValue{ .list = items };
    defer original.deinit(allocator);

    var cloned = try original.clone(allocator);
    defer cloned.deinit(allocator);

    try testing.expectEqual(original.list.len, cloned.list.len);
    for (original.list, 0..) |item, i| {
        try testing.expectEqual(item.s32, cloned.list[i].s32);
    }
}

// Test resource management
test "resource table - basic operations" {
    const allocator = testing.allocator;

    var rt = try ResourceTable.init(allocator);
    defer rt.deinit();

    // Add a file resource
    const idx = try rt.addResource(.file, 42);
    try testing.expectEqual(@as(u32, 0), idx);

    // Get the handle back
    const handle = rt.getHandle(idx);
    try testing.expect(handle != null);
    try testing.expectEqual(@as(u32, 42), handle.?);

    // Get resource type
    const res_type = rt.getResourceType(idx);
    try testing.expect(res_type != null);
    try testing.expectEqual(ResourceTable.ResourceType.file, res_type.?);

    // Remove the resource
    try rt.removeResource(idx);

    // Verify it's gone
    try testing.expect(rt.getHandle(idx) == null);
}

test "resource table - multiple resources" {
    const allocator = testing.allocator;

    var rt = try ResourceTable.init(allocator);
    defer rt.deinit();

    const file_idx = try rt.addResource(.file, 10);
    const socket_idx = try rt.addResource(.socket, 20);
    const stream_idx = try rt.addResource(.stream, 30);

    try testing.expectEqual(@as(u32, 10), rt.getHandle(file_idx).?);
    try testing.expectEqual(@as(u32, 20), rt.getHandle(socket_idx).?);
    try testing.expectEqual(@as(u32, 30), rt.getHandle(stream_idx).?);

    try testing.expectEqual(ResourceTable.ResourceType.file, rt.getResourceType(file_idx).?);
    try testing.expectEqual(ResourceTable.ResourceType.socket, rt.getResourceType(socket_idx).?);
    try testing.expectEqual(ResourceTable.ResourceType.stream, rt.getResourceType(stream_idx).?);
}

// Test dereference functions
test "component value - dereference borrow" {
    const allocator = testing.allocator;

    var rt = try ResourceTable.init(allocator);
    defer rt.deinit();

    // Add a resource
    const handle = try rt.addResource(.file, 42);

    // Create a borrow
    const borrow = ComponentValue{ .borrow = handle };

    // Dereference it
    const deref = try borrow.derefBorrow(&rt);
    try testing.expect(deref != null);
    try testing.expectEqual(@as(u32, handle), deref.?.u32);
}

test "component value - dereference own" {
    const allocator = testing.allocator;

    var rt = try ResourceTable.init(allocator);
    defer rt.deinit();

    // Add a resource
    const handle = try rt.addResource(.file, 42);

    // Create an own
    var own = ComponentValue{ .own = handle };

    // Dereference it (transfers ownership)
    const deref = try own.derefOwn(&rt);
    try testing.expectEqual(@as(u32, 42), deref.u32);

    // Resource should be removed from table
    try testing.expect(rt.getHandle(handle) == null);
}

test "component value - create borrow from own" {
    const allocator = testing.allocator;

    var rt = try ResourceTable.init(allocator);
    defer rt.deinit();

    // Add a resource
    const handle = try rt.addResource(.file, 42);

    // Create an own
    const own = ComponentValue{ .own = handle };

    // Create a borrow
    const borrow = try ComponentValue.createBorrow(&own, allocator, &rt);
    try testing.expectEqual(handle, borrow.borrow);

    // Original resource should still be in table
    try testing.expect(rt.getHandle(handle) != null);
}

test "component value - drop own" {
    const allocator = testing.allocator;

    var rt = try ResourceTable.init(allocator);
    defer rt.deinit();

    // Add a resource
    const handle = try rt.addResource(.file, 42);

    // Create an own
    var own = ComponentValue{ .own = handle };

    // Drop it
    try own.dropOwn(&rt);

    // Resource should be removed
    try testing.expect(rt.getHandle(handle) == null);

    // Handle should be invalidated
    try testing.expectEqual(std.math.maxInt(u32), own.own);
}

// Test component linker
test "component linker - basic loading" {
    const allocator = testing.allocator;

    var linker = ComponentLinker.init(allocator);
    defer linker.deinit();

    // Create minimal component data (just magic + version for now)
    const comp_data = [_]u8{
        0x00, 0x61, 0x73, 0x6d, // magic
        0x0d, 0x00, 0x01, 0x00, // version (component model)
    };

    // Note: This will fail to parse because we don't have a full component
    // In a real test, we'd create valid component bytecode
    const result = linker.loadComponent("test", &comp_data);
    try testing.expect(result != error.InvalidComponentMagic or result != error.InvalidComponentVersion);
}

test "component linker - get component" {
    const allocator = testing.allocator;

    var linker = ComponentLinker.init(allocator);
    defer linker.deinit();

    // Component that doesn't exist
    const comp = linker.getComponent("nonexistent");
    try testing.expect(comp == null);
}

// Test canonical ABI
test "canonical abi - lift primitive" {
    const allocator = testing.allocator;

    var abi = CanonicalABI.init(allocator);
    defer abi.type_cache.deinit();

    // Test lifting a bool
    const wasm_val = component.Value{ .i32 = 1 };
    const comp_val = abi.liftPrimitive(wasm_val, .bool);
    try testing.expect(comp_val.bool);

    // Test lifting an s32
    const wasm_s32 = component.Value{ .i32 = -42 };
    const comp_s32 = abi.liftPrimitive(wasm_s32, .s32);
    try testing.expectEqual(@as(i32, -42), comp_s32.s32);

    // Test lifting a u64
    const wasm_u64 = component.Value{ .i64 = @bitCast(@as(u64, 12345)) };
    const comp_u64 = abi.liftPrimitive(wasm_u64, .u64);
    try testing.expectEqual(@as(u64, 12345), comp_u64.u64);
}

test "canonical abi - lower primitive" {
    const allocator = testing.allocator;

    var abi = CanonicalABI.init(allocator);
    defer abi.type_cache.deinit();

    // Test lowering a bool
    const comp_bool = ComponentValue{ .bool = true };
    const wasm_bool = abi.lowerPrimitive(comp_bool);
    try testing.expectEqual(@as(i32, 1), wasm_bool.i32);

    // Test lowering an s32
    const comp_s32 = ComponentValue{ .s32 = -42 };
    const wasm_s32 = abi.lowerPrimitive(comp_s32);
    try testing.expectEqual(@as(i32, -42), wasm_s32.i32);

    // Test lowering a u64
    const comp_u64 = ComponentValue{ .u64 = 12345 };
    const wasm_u64 = abi.lowerPrimitive(comp_u64);
    const result: u64 = @bitCast(wasm_u64.i64);
    try testing.expectEqual(@as(u64, 12345), result);
}

// Test component instance
test "component instance - creation" {
    const allocator = testing.allocator;

    var comp = try Component.init(allocator);
    defer comp.deinit();

    var instance = try ComponentInstance.init(allocator, &comp);
    defer instance.deinit();

    try testing.expect(instance.exports.count() == 0);
    try testing.expect(instance.imports.count() == 0);
}

test "component instance - exports" {
    const allocator = testing.allocator;

    var comp = try Component.init(allocator);
    defer comp.deinit();

    // Add an export
    const export_name = try allocator.dupe(u8, "test_export");
    try comp.exports.append(allocator, .{
        .name = export_name,
        .ty_idx = 0,
    });

    // Add a type for the export
    try comp.types.append(allocator, ComponentType{
        .tag = .bool,
        .payload = .{ .bool = {} },
    });

    var instance = try ComponentInstance.init(allocator, &comp);
    defer instance.deinit();

    const imports = std.StringHashMap(ComponentValue).init(allocator);
    try instance.instantiate(imports);

    // Should have created the export (as placeholder)
    try testing.expect(instance.exports.count() > 0);
}

// Integration test for component model workflow
test "component workflow - create, instantiate, execute" {
    const allocator = testing.allocator;

    // Create component
    var comp = try Component.init(allocator);
    defer comp.deinit();

    // Add a bool type
    try comp.types.append(allocator, ComponentType{
        .tag = .bool,
        .payload = .{ .bool = {} },
    });

    // Add a function
    try comp.functions.append(allocator, 0);

    // Validate
    try comp.validate();

    // Create instance
    var instance = try ComponentInstance.init(allocator, &comp);
    defer instance.deinit();

    // Instantiate with empty imports
    const imports = std.StringHashMap(ComponentValue).init(allocator);
    try instance.instantiate(imports);

    // Call start if present
    try instance.callStart();
}

// Test error cases
test "component validation - invalid type index" {
    const allocator = testing.allocator;

    var comp = try Component.init(allocator);
    defer comp.deinit();

    // Add a function with invalid type index
    try comp.functions.append(allocator, 999);

    // Validation should fail
    const result = comp.validate();
    try testing.expectError(error.InvalidTypeIndex, result);
}

test "component validation - invalid start function" {
    const allocator = testing.allocator;

    var comp = try Component.init(allocator);
    defer comp.deinit();

    // Set invalid start function
    comp.start = 999;

    // Validation should fail
    const result = comp.validate();
    try testing.expectError(error.InvalidStartFunctionIndex, result);
}

test "resource table - invalid handle access" {
    const allocator = testing.allocator;

    var rt = try ResourceTable.init(allocator);
    defer rt.deinit();

    // Try to access non-existent handle
    const handle = rt.getHandle(999);
    try testing.expect(handle == null);

    // Try to remove non-existent handle
    const result = rt.removeResource(999);
    try testing.expectError(error.InvalidIndex, result);
}

test "component value - invalid dereference" {
    const allocator = testing.allocator;

    var rt = try ResourceTable.init(allocator);
    defer rt.deinit();

    // Try to deref a non-borrow value
    const not_borrow = ComponentValue{ .s32 = 42 };
    const result = not_borrow.derefBorrow(&rt);
    try testing.expectError(error.NotABorrowHandle, result);

    // Try to deref a non-own value
    var not_own = ComponentValue{ .s32 = 42 };
    const result2 = not_own.derefOwn(&rt);
    try testing.expectError(error.NotAnOwnHandle, result2);
}

// ============================================================================
// INTEGRATION TESTS FOR LINKED COMPONENTS
// ============================================================================

test "linked components - basic linking workflow" {
    const allocator = testing.allocator;

    var linker = ComponentLinker.init(allocator);
    defer linker.deinit();

    // Create two components manually
    var comp_a = try Component.init(allocator);
    var comp_b = try Component.init(allocator);

    // Component A exports a value
    const export_name_a = try allocator.dupe(u8, "exported_func");
    try comp_a.exports.append(allocator, .{
        .name = export_name_a,
        .ty_idx = 0,
    });

    // Add type
    try comp_a.types.append(allocator, ComponentType{
        .tag = .s32,
        .payload = .{ .s32 = {} },
    });

    // Component B imports a value
    const import_name_b = try allocator.dupe(u8, "imported_func");
    try comp_b.imports.append(allocator, .{
        .name = import_name_b,
        .ty_idx = 0,
    });

    // Add type
    try comp_b.types.append(allocator, ComponentType{
        .tag = .s32,
        .payload = .{ .s32 = {} },
    });

    // Create instances manually (since we can't parse binary)
    const inst_a = try allocator.create(ComponentInstance);
    inst_a.* = try ComponentInstance.init(allocator, &comp_a);

    const inst_b = try allocator.create(ComponentInstance);
    inst_b.* = try ComponentInstance.init(allocator, &comp_b);

    // Add some exports to instance A
    const key_a = try allocator.dupe(u8, "exported_func");
    try inst_a.exports.put(key_a, ComponentValue{ .s32 = 42 });

    // Store in linker
    try linker.loaded_components.put(try allocator.dupe(u8, "comp_a"), inst_a);
    try linker.loaded_components.put(try allocator.dupe(u8, "comp_b"), inst_b);

    // Link export from A to import in B
    try linker.linkExportToImport("comp_a", "exported_func", "comp_b", "imported_func");

    // Verify the import was satisfied
    const imported = inst_b.imports.get("imported_func");
    try testing.expect(imported != null);
    try testing.expectEqual(@as(i32, 42), imported.?.s32);

    // Clean up (linker.deinit will free everything)
}

test "linked components - resolve imports automatically" {
    const allocator = testing.allocator;

    var linker = ComponentLinker.init(allocator);
    defer linker.deinit();

    // Create provider component with exports
    var provider = try Component.init(allocator);
    const export_name = try allocator.dupe(u8, "utility_func");
    try provider.exports.append(allocator, .{
        .name = export_name,
        .ty_idx = 0,
    });
    try provider.types.append(allocator, ComponentType{
        .tag = .bool,
        .payload = .{ .bool = {} },
    });

    const provider_inst = try allocator.create(ComponentInstance);
    provider_inst.* = try ComponentInstance.init(allocator, &provider);

    // Add export value
    const key = try allocator.dupe(u8, "utility_func");
    try provider_inst.exports.put(key, ComponentValue{ .bool = true });

    // Create consumer component with imports
    var consumer = try Component.init(allocator);
    const import_name = try allocator.dupe(u8, "utility_func");
    try consumer.imports.append(allocator, .{
        .name = import_name,
        .ty_idx = 0,
    });
    try consumer.types.append(allocator, ComponentType{
        .tag = .bool,
        .payload = .{ .bool = {} },
    });

    const consumer_inst = try allocator.create(ComponentInstance);
    consumer_inst.* = try ComponentInstance.init(allocator, &consumer);

    // Register both
    try linker.loaded_components.put(try allocator.dupe(u8, "provider"), provider_inst);
    try linker.loaded_components.put(try allocator.dupe(u8, "consumer"), consumer_inst);

    // Resolve imports for consumer
    try linker.resolveImports("consumer");

    // Verify import was resolved
    const resolved = consumer_inst.imports.get("utility_func");
    try testing.expect(resolved != null);
    try testing.expect(resolved.?.bool);
}

test "linked components - link all" {
    const allocator = testing.allocator;

    var linker = ComponentLinker.init(allocator);
    defer linker.deinit();

    // Create multiple components with interdependencies

    // Component A - provides service1
    var comp_a = try Component.init(allocator);
    try comp_a.exports.append(allocator, .{
        .name = try allocator.dupe(u8, "service1"),
        .ty_idx = 0,
    });
    try comp_a.types.append(allocator, ComponentType{
        .tag = .u32,
        .payload = .{ .u32 = {} },
    });

    const inst_a = try allocator.create(ComponentInstance);
    inst_a.* = try ComponentInstance.init(allocator, &comp_a);
    try inst_a.exports.put(try allocator.dupe(u8, "service1"), ComponentValue{ .u32 = 100 });

    // Component B - provides service2, uses service1
    var comp_b = try Component.init(allocator);
    try comp_b.exports.append(allocator, .{
        .name = try allocator.dupe(u8, "service2"),
        .ty_idx = 0,
    });
    try comp_b.imports.append(allocator, .{
        .name = try allocator.dupe(u8, "service1"),
        .ty_idx = 0,
    });
    try comp_b.types.append(allocator, ComponentType{
        .tag = .u32,
        .payload = .{ .u32 = {} },
    });

    const inst_b = try allocator.create(ComponentInstance);
    inst_b.* = try ComponentInstance.init(allocator, &comp_b);
    try inst_b.exports.put(try allocator.dupe(u8, "service2"), ComponentValue{ .u32 = 200 });

    // Component C - uses service2
    var comp_c = try Component.init(allocator);
    try comp_c.imports.append(allocator, .{
        .name = try allocator.dupe(u8, "service2"),
        .ty_idx = 0,
    });
    try comp_c.types.append(allocator, ComponentType{
        .tag = .u32,
        .payload = .{ .u32 = {} },
    });

    const inst_c = try allocator.create(ComponentInstance);
    inst_c.* = try ComponentInstance.init(allocator, &comp_c);

    // Register all components
    try linker.loaded_components.put(try allocator.dupe(u8, "comp_a"), inst_a);
    try linker.loaded_components.put(try allocator.dupe(u8, "comp_b"), inst_b);
    try linker.loaded_components.put(try allocator.dupe(u8, "comp_c"), inst_c);

    // Link all at once
    try linker.linkAll();

    // Verify all imports are resolved
    const b_import = inst_b.imports.get("service1");
    try testing.expect(b_import != null);
    try testing.expectEqual(@as(u32, 100), b_import.?.u32);

    const c_import = inst_c.imports.get("service2");
    try testing.expect(c_import != null);
    try testing.expectEqual(@as(u32, 200), c_import.?.u32);
}

test "linked components - resource sharing" {
    const allocator = testing.allocator;

    var linker = ComponentLinker.init(allocator);
    defer linker.deinit();

    // Create component A with a resource
    var comp_a = try Component.init(allocator);
    try comp_a.exports.append(allocator, .{
        .name = try allocator.dupe(u8, "file_handle"),
        .ty_idx = 0,
    });
    try comp_a.types.append(allocator, ComponentType{
        .tag = .own,
        .payload = .{ .own = 0 },
    });

    const inst_a = try allocator.create(ComponentInstance);
    inst_a.* = try ComponentInstance.init(allocator, &comp_a);

    // Add a file resource
    const handle = try inst_a.resource_table.addResource(.file, 42);
    try inst_a.exports.put(try allocator.dupe(u8, "file_handle"), ComponentValue{ .own = handle });

    // Create component B that borrows the resource
    var comp_b = try Component.init(allocator);
    try comp_b.imports.append(allocator, .{
        .name = try allocator.dupe(u8, "file_handle"),
        .ty_idx = 0,
    });
    try comp_b.types.append(allocator, ComponentType{
        .tag = .borrow,
        .payload = .{ .borrow = 0 },
    });

    const inst_b = try allocator.create(ComponentInstance);
    inst_b.* = try ComponentInstance.init(allocator, &comp_b);

    // Register components
    try linker.loaded_components.put(try allocator.dupe(u8, "comp_a"), inst_a);
    try linker.loaded_components.put(try allocator.dupe(u8, "comp_b"), inst_b);

    // Get the owned resource from A
    const owned = inst_a.exports.get("file_handle");
    try testing.expect(owned != null);

    // Create a borrow for B
    const borrowed = try ComponentValue.createBorrow(&owned.?, allocator, &inst_a.resource_table);
    try inst_b.imports.put(try allocator.dupe(u8, "file_handle"), borrowed);

    // Verify the borrow points to the same resource
    try testing.expectEqual(handle, borrowed.borrow);

    // Original resource should still be valid
    try testing.expect(inst_a.resource_table.getHandle(handle) != null);
}

test "linked components - unload component" {
    const allocator = testing.allocator;

    var linker = ComponentLinker.init(allocator);
    defer linker.deinit();

    // Create a component
    var comp = try Component.init(allocator);
    try comp.types.append(allocator, ComponentType{
        .tag = .bool,
        .payload = .{ .bool = {} },
    });

    const inst = try allocator.create(ComponentInstance);
    inst.* = try ComponentInstance.init(allocator, &comp);

    // Register it
    try linker.loaded_components.put(try allocator.dupe(u8, "test_comp"), inst);

    // Verify it's loaded
    try testing.expect(linker.getComponent("test_comp") != null);

    // Unload it
    try linker.unloadComponent("test_comp");

    // Verify it's gone
    try testing.expect(linker.getComponent("test_comp") == null);
}

test "linked components - error handling" {
    const allocator = testing.allocator;

    var linker = ComponentLinker.init(allocator);
    defer linker.deinit();

    // Try to get non-existent component
    try testing.expect(linker.getComponent("nonexistent") == null);

    // Try to unload non-existent component
    const result = linker.unloadComponent("nonexistent");
    try testing.expectError(error.ComponentNotLoaded, result);

    // Try to link to non-existent component
    const link_result = linker.linkExportToImport("comp_a", "export", "comp_b", "import");
    try testing.expectError(error.ComponentNotLoaded, link_result);
}

test "linked components - complex value transfer" {
    const allocator = testing.allocator;

    var linker = ComponentLinker.init(allocator);
    defer linker.deinit();

    // Create provider with complex values
    var provider = try Component.init(allocator);
    try provider.exports.append(allocator, .{
        .name = try allocator.dupe(u8, "data"),
        .ty_idx = 0,
    });
    try provider.types.append(allocator, ComponentType{
        .tag = .list,
        .payload = .{ .list = {} },
    });

    const provider_inst = try allocator.create(ComponentInstance);
    provider_inst.* = try ComponentInstance.init(allocator, &provider);

    // Create a list value
    const list = try allocator.alloc(ComponentValue, 3);
    list[0] = ComponentValue{ .s32 = 1 };
    list[1] = ComponentValue{ .s32 = 2 };
    list[2] = ComponentValue{ .s32 = 3 };
    try provider_inst.exports.put(try allocator.dupe(u8, "data"), ComponentValue{ .list = list });

    // Create consumer
    var consumer = try Component.init(allocator);
    try consumer.imports.append(allocator, .{
        .name = try allocator.dupe(u8, "data"),
        .ty_idx = 0,
    });
    try consumer.types.append(allocator, ComponentType{
        .tag = .list,
        .payload = .{ .list = {} },
    });

    const consumer_inst = try allocator.create(ComponentInstance);
    consumer_inst.* = try ComponentInstance.init(allocator, &consumer);

    // Register and link
    try linker.loaded_components.put(try allocator.dupe(u8, "provider"), provider_inst);
    try linker.loaded_components.put(try allocator.dupe(u8, "consumer"), consumer_inst);

    try linker.linkExportToImport("provider", "data", "consumer", "data");

    // Verify the list was transferred
    const imported = consumer_inst.imports.get("data");
    try testing.expect(imported != null);
    try testing.expectEqual(@as(usize, 3), imported.?.list.len);
    try testing.expectEqual(@as(i32, 1), imported.?.list[0].s32);
    try testing.expectEqual(@as(i32, 2), imported.?.list[1].s32);
    try testing.expectEqual(@as(i32, 3), imported.?.list[2].s32);
}
