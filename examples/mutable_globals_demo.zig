const std = @import("std");
const globals = @import("../src/wasm/mutable_globals.zig");
const Value = @import("../src/wasm/value.zig").Value;
const ValueType = @import("../src/wasm/value.zig").Type;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("=== Mutable Globals Import/Export Demo ===\n\n", .{});

    // 1. Create module linker
    var linker = globals.ModuleLinker.init(allocator);
    defer linker.deinit();

    // 2. Create Module A with exported mutable global
    std.debug.print("1. Module A: Exporting mutable global 'shared_counter'\n", .{});
    var moduleA = try globals.ModuleInstance.init(allocator, "moduleA");
    const counter_desc = globals.GlobalDescriptor{
        .value_type = .i32,
        .mutable = true,
    };
    const counter_idx = try moduleA.global_mgr.define(counter_desc, Value{ .i32 = 0 });
    try moduleA.global_mgr.@"export"(counter_idx, "shared_counter");
    try linker.registerModule(moduleA);
    std.debug.print("   Initial value: {d}\n\n", .{0});

    // 3. Create Module B that imports the counter
    std.debug.print("2. Module B: Importing 'shared_counter' from Module A\n", .{});
    var moduleB = try globals.ModuleInstance.init(allocator, "moduleB");
    _ = try moduleB.global_mgr.import("moduleA", "shared_counter", counter_desc, Value{ .i32 = 0 });
    try linker.registerModule(moduleB);

    // Link the modules
    try linker.linkModules("moduleB", "moduleA", "shared_counter");
    std.debug.print("   Modules linked successfully\n\n", .{});

    // 4. Module A increments the counter
    std.debug.print("3. Module A: Incrementing counter\n", .{});
    try linker.setGlobal("moduleA", "shared_counter", Value{ .i32 = 1 });
    const val1 = try linker.getGlobal("moduleA", "shared_counter");
    std.debug.print("   Counter value: {d}\n\n", .{val1.i32});

    // 5. Module A increments again
    try linker.setGlobal("moduleA", "shared_counter", Value{ .i32 = 2 });
    const val2 = try linker.getGlobal("moduleA", "shared_counter");
    std.debug.print("4. Counter incremented again: {d}\n\n", .{val2.i32});

    // 6. Host environment providing globals
    std.debug.print("5. Host Environment: Providing globals to modules\n", .{});
    var host = globals.HostEnvironment.init(allocator);
    defer host.deinit();

    const mem_offset_desc = globals.GlobalDescriptor{
        .value_type = .i32,
        .mutable = false,
    };
    try host.provideGlobal("env.mem_offset", mem_offset_desc, Value{ .i32 = 4096 });
    std.debug.print("   Provided 'env.mem_offset' = 4096\n\n", .{});

    // 7. Demonstrate immutable global
    std.debug.print("6. Immutable Global: Cannot be modified\n", .{});
    var moduleC = try globals.ModuleInstance.init(allocator, "moduleC");
    defer moduleC.deinit();

    const pi_desc = globals.GlobalDescriptor{
        .value_type = .f64,
        .mutable = false,
    };
    const pi_idx = try moduleC.global_mgr.define(pi_desc, Value{ .f64 = 3.14159 });
    try moduleC.global_mgr.@"export"(pi_idx, "pi");

    std.debug.print("   Defined immutable global 'pi' = 3.14159\n", .{});
    std.debug.print("   Attempting to modify... ", .{});

    const set_result = moduleC.global_mgr.set(pi_idx, Value{ .f64 = 3.0 });
    if (set_result) |_| {
        std.debug.print("ERROR: Should have failed!\n", .{});
    } else |err| {
        std.debug.print("Correctly rejected: {s}\n\n", .{@errorName(err)});
    }

    // 8. Multiple types
    std.debug.print("7. Multiple Global Types:\n", .{});
    var moduleD = try globals.ModuleInstance.init(allocator, "moduleD");
    defer moduleD.deinit();

    _ = try moduleD.global_mgr.define(
        globals.GlobalDescriptor{ .value_type = .i32, .mutable = true },
        Value{ .i32 = 42 },
    );
    _ = try moduleD.global_mgr.define(
        globals.GlobalDescriptor{ .value_type = .i64, .mutable = true },
        Value{ .i64 = 1000 },
    );
    _ = try moduleD.global_mgr.define(
        globals.GlobalDescriptor{ .value_type = .f32, .mutable = true },
        Value{ .f32 = 3.14 },
    );
    _ = try moduleD.global_mgr.define(
        globals.GlobalDescriptor{ .value_type = .f64, .mutable = false },
        Value{ .f64 = 2.71828 },
    );

    std.debug.print("   i32: ✓\n", .{});
    std.debug.print("   i64: ✓\n", .{});
    std.debug.print("   f32: ✓\n", .{});
    std.debug.print("   f64: ✓\n\n", .{});

    std.debug.print("Demo completed.\n", .{});
}
