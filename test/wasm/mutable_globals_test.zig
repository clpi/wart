const std = @import("std");
const testing = std.testing;
const globals = @import("../../src/wasm/mutable_globals.zig");
const Value = @import("../../src/wasm/value.zig").Value;
const ValueType = @import("../../src/wasm/value.zig").Type;

const GlobalDescriptor = globals.GlobalDescriptor;
const Global = globals.Global;
const GlobalManager = globals.GlobalManager;
const ModuleInstance = globals.ModuleInstance;
const ModuleLinker = globals.ModuleLinker;
const HostEnvironment = globals.HostEnvironment;

// GlobalDescriptor tests
test "global descriptor - immutable i32" {
    const desc = GlobalDescriptor{
        .value_type = .i32,
        .mutable = false,
    };
    
    try testing.expect(!desc.mutable);
    try testing.expectEqual(ValueType.i32, desc.value_type);
}

test "global descriptor - mutable i64" {
    const desc = GlobalDescriptor{
        .value_type = .i64,
        .mutable = true,
    };
    
    try testing.expect(desc.mutable);
    try testing.expectEqual(ValueType.i64, desc.value_type);
}

// Global tests
test "global - init and get" {
    const desc = GlobalDescriptor{ .value_type = .i32, .mutable = false };
    const init = Value{ .i32 = 42 };
    
    const global = Global.init(desc, init);
    
    try testing.expectEqual(@as(i32, 42), global.get().i32);
}

test "global - mutable set" {
    const desc = GlobalDescriptor{ .value_type = .i32, .mutable = true };
    const init = Value{ .i32 = 42 };
    
    var global = Global.init(desc, init);
    
    try global.set(Value{ .i32 = 100 });
    try testing.expectEqual(@as(i32, 100), global.get().i32);
}

test "global - immutable set fails" {
    const desc = GlobalDescriptor{ .value_type = .i32, .mutable = false };
    const init = Value{ .i32 = 42 };
    
    var global = Global.init(desc, init);
    
    const result = global.set(Value{ .i32 = 100 });
    try testing.expectError(error.ImmutableGlobal, result);
}

test "global - type mismatch" {
    const desc = GlobalDescriptor{ .value_type = .i32, .mutable = true };
    const init = Value{ .i32 = 42 };
    
    var global = Global.init(desc, init);
    
    const result = global.set(Value{ .i64 = 100 });
    try testing.expectError(error.TypeMismatch, result);
}

// GlobalManager tests
test "global manager - define global" {
    const allocator = testing.allocator;
    var mgr = GlobalManager.init(allocator);
    defer mgr.deinit();

    const desc = GlobalDescriptor{ .value_type = .i32, .mutable = true };
    const index = try mgr.define(desc, Value{ .i32 = 42 });

    try testing.expectEqual(@as(u32, 0), index);
    try testing.expectEqual(@as(usize, 1), mgr.globals.items.len);
}

test "global manager - import global" {
    const allocator = testing.allocator;
    var mgr = GlobalManager.init(allocator);
    defer mgr.deinit();

    const desc = GlobalDescriptor{ .value_type = .i32, .mutable = true };
    const index = try mgr.import("env", "counter", desc, Value{ .i32 = 0 });

    try testing.expectEqual(@as(u32, 0), index);
    try testing.expect(mgr.globals.items[index].imported);
}

test "global manager - export global" {
    const allocator = testing.allocator;
    var mgr = GlobalManager.init(allocator);
    defer mgr.deinit();

    const desc = GlobalDescriptor{ .value_type = .f64, .mutable = false };
    const index = try mgr.define(desc, Value{ .f64 = 3.14 });
    
    try mgr.@"export"(index, "pi");

    try testing.expect(mgr.globals.items[index].exported);
    const found_idx = try mgr.getByExportName("pi");
    try testing.expectEqual(index, found_idx);
}

test "global manager - get and set" {
    const allocator = testing.allocator;
    var mgr = GlobalManager.init(allocator);
    defer mgr.deinit();

    const desc = GlobalDescriptor{ .value_type = .i32, .mutable = true };
    const index = try mgr.define(desc, Value{ .i32 = 10 });

    const val = try mgr.get(index);
    try testing.expectEqual(@as(i32, 10), val.i32);

    try mgr.set(index, Value{ .i32 = 20 });
    const new_val = try mgr.get(index);
    try testing.expectEqual(@as(i32, 20), new_val.i32);
}

test "global manager - validate access" {
    const allocator = testing.allocator;
    var mgr = GlobalManager.init(allocator);
    defer mgr.deinit();

    const immutable = GlobalDescriptor{ .value_type = .i32, .mutable = false };
    const idx1 = try mgr.define(immutable, Value{ .i32 = 42 });

    const mutable = GlobalDescriptor{ .value_type = .i32, .mutable = true };
    const idx2 = try mgr.define(mutable, Value{ .i32 = 100 });

    // Get is always valid
    try mgr.validateAccess(idx1, false);
    try mgr.validateAccess(idx2, false);

    // Set only valid on mutable
    const result = mgr.validateAccess(idx1, true);
    try testing.expectError(error.ImmutableGlobal, result);
    
    try mgr.validateAccess(idx2, true);
}

// ModuleInstance tests
test "module instance - create and destroy" {
    const allocator = testing.allocator;
    var instance = try ModuleInstance.init(allocator, "test_module");
    defer instance.deinit();

    try testing.expectEqualStrings("test_module", instance.name);
}

test "module instance - define and export global" {
    const allocator = testing.allocator;
    var instance = try ModuleInstance.init(allocator, "test");
    defer instance.deinit();

    const desc = GlobalDescriptor{ .value_type = .i32, .mutable = true };
    const idx = try instance.global_mgr.define(desc, Value{ .i32 = 42 });
    try instance.global_mgr.@"export"(idx, "shared_counter");

    const val = try instance.global_mgr.get(idx);
    try testing.expectEqual(@as(i32, 42), val.i32);
}

// ModuleLinker tests
test "module linker - register modules" {
    const allocator = testing.allocator;
    var linker = ModuleLinker.init(allocator);
    defer linker.deinit();

    var mod1 = try ModuleInstance.init(allocator, "module1");
    var mod2 = try ModuleInstance.init(allocator, "module2");

    try linker.registerModule(mod1);
    try linker.registerModule(mod2);

    try testing.expectEqual(@as(usize, 2), linker.modules.count());
}

test "module linker - link modules" {
    const allocator = testing.allocator;
    var linker = ModuleLinker.init(allocator);
    defer linker.deinit();

    // Create exporter module
    var exporter = try ModuleInstance.init(allocator, "exporter");
    const desc = GlobalDescriptor{ .value_type = .i32, .mutable = true };
    const idx = try exporter.global_mgr.define(desc, Value{ .i32 = 42 });
    try exporter.global_mgr.@"export"(idx, "shared");
    try linker.registerModule(exporter);

    // Create importer module
    var importer = try ModuleInstance.init(allocator, "importer");
    _ = try importer.global_mgr.import("exporter", "shared", desc, Value{ .i32 = 0 });
    try linker.registerModule(importer);

    // Link the modules
    try linker.linkModules("importer", "exporter", "shared");
}

test "module linker - get and set across modules" {
    const allocator = testing.allocator;
    var linker = ModuleLinker.init(allocator);
    defer linker.deinit();

    var module = try ModuleInstance.init(allocator, "test");
    const desc = GlobalDescriptor{ .value_type = .i32, .mutable = true };
    const idx = try module.global_mgr.define(desc, Value{ .i32 = 100 });
    try module.global_mgr.@"export"(idx, "counter");
    try linker.registerModule(module);

    const val = try linker.getGlobal("test", "counter");
    try testing.expectEqual(@as(i32, 100), val.i32);

    try linker.setGlobal("test", "counter", Value{ .i32 = 200 });
    const new_val = try linker.getGlobal("test", "counter");
    try testing.expectEqual(@as(i32, 200), new_val.i32);
}

// HostEnvironment tests
test "host environment - provide global" {
    const allocator = testing.allocator;
    var host = HostEnvironment.init(allocator);
    defer host.deinit();

    const desc = GlobalDescriptor{ .value_type = .i32, .mutable = false };
    try host.provideGlobal("env.version", desc, Value{ .i32 = 1 });

    const global = try host.getGlobal("env.version");
    try testing.expectEqual(@as(i32, 1), global.value.i32);
}

test "host environment - satisfy import" {
    const allocator = testing.allocator;
    var host = HostEnvironment.init(allocator);
    defer host.deinit();

    // Host provides a global
    const desc = GlobalDescriptor{ .value_type = .i32, .mutable = true };
    try host.provideGlobal("env.mem_offset", desc, Value{ .i32 = 4096 });

    // Module imports it
    var module = try ModuleInstance.init(allocator, "test");
    defer module.deinit();
    _ = try module.global_mgr.import("env", "mem_offset", desc, Value{ .i32 = 0 });

    // Host satisfies the import
    try host.satisfyImport(module, "env", "mem_offset");
}

// Integration tests
test "integration - mutable global shared between modules" {
    const allocator = testing.allocator;
    var linker = ModuleLinker.init(allocator);
    defer linker.deinit();

    // Module A exports a mutable counter
    var moduleA = try ModuleInstance.init(allocator, "moduleA");
    const desc = GlobalDescriptor{ .value_type = .i32, .mutable = true };
    const idx_a = try moduleA.global_mgr.define(desc, Value{ .i32 = 0 });
    try moduleA.global_mgr.@"export"(idx_a, "counter");
    try linker.registerModule(moduleA);

    // Module B imports the counter
    var moduleB = try ModuleInstance.init(allocator, "moduleB");
    _ = try moduleB.global_mgr.import("moduleA", "counter", desc, Value{ .i32 = 0 });
    try linker.registerModule(moduleB);

    // Link the modules
    try linker.linkModules("moduleB", "moduleA", "counter");

    // Module A increments the counter
    try linker.setGlobal("moduleA", "counter", Value{ .i32 = 1 });

    // Module B can see the change (through the link)
    const val_a = try linker.getGlobal("moduleA", "counter");
    try testing.expectEqual(@as(i32, 1), val_a.i32);
}

test "integration - multiple mutable globals" {
    const allocator = testing.allocator;
    var mgr = GlobalManager.init(allocator);
    defer mgr.deinit();

    const desc_i32 = GlobalDescriptor{ .value_type = .i32, .mutable = true };
    const desc_i64 = GlobalDescriptor{ .value_type = .i64, .mutable = true };
    const desc_f32 = GlobalDescriptor{ .value_type = .f32, .mutable = true };
    const desc_f64 = GlobalDescriptor{ .value_type = .f64, .mutable = true };

    const idx1 = try mgr.define(desc_i32, Value{ .i32 = 1 });
    const idx2 = try mgr.define(desc_i64, Value{ .i64 = 2 });
    const idx3 = try mgr.define(desc_f32, Value{ .f32 = 3.0 });
    const idx4 = try mgr.define(desc_f64, Value{ .f64 = 4.0 });

    try mgr.@"export"(idx1, "int32_var");
    try mgr.@"export"(idx2, "int64_var");
    try mgr.@"export"(idx3, "float32_var");
    try mgr.@"export"(idx4, "float64_var");

    try testing.expectEqual(@as(i32, 1), (try mgr.get(idx1)).i32);
    try testing.expectEqual(@as(i64, 2), (try mgr.get(idx2)).i64);
    try testing.expectEqual(@as(f32, 3.0), (try mgr.get(idx3)).f32);
    try testing.expectEqual(@as(f64, 4.0), (try mgr.get(idx4)).f64);
}
