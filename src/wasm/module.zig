const print = @import("../util/fmt.zig").print;
const Color = @import("../util/fmt/color.zig");
const Allocator = std.mem.Allocator;
const std = @import("std");
const Log = @import("../util/fmt.zig").Log;
const value = @import("value.zig");
const Value = value.Value;
const ValueType = value.Type;
const Module = @This();
const Array = std.ArrayList;

pub const Import = @import("module/import.zig");
pub const Export = @import("module/export.zig");
pub const Function = @import("module/function.zig");
pub const Signature = @import("module/signature.zig");
pub const Reader = @import("module/reader.zig");
pub const Global = @import("module/global.zig");
pub const Type = @import("module/type.zig");
pub const Expression = @import("module/expression.zig").Expression;

pub const Memory: type = struct {
    data: []u8,
    min_pages: u64,
    max_pages: ?u64,
    is64: bool,
};

pub const DataSegment: type = struct {
    memory_index: u32,
    offset: usize,
    data: []u8,
};

pub const GCType: type = union(enum) {
    none,
    struct_type: []ValueType,
    array_type: struct {
        element_type: ValueType,
        mutable: bool,
    },
};

// Lightweight block summary for validator/runtime use
pub const BlockSummary: type = struct { start_pos: usize, end_pos: usize };
pub const FunctionCFG: type = struct { blocks: []BlockSummary = &[_]BlockSummary{} };

pub const Section = enum(u8) {
    custom = 0,
    type = 1,
    import = 2,
    function = 3,
    table = 4,
    memory = 5,
    global = 6,
    @"export" = 7,
    start = 8,
    element = 9,
    code = 10,
    data = 11,
};

allocator: Allocator,
functions: Array(*Function),
io: std.Io,
types: Array(Signature),
gc_types: Array(GCType),
// Back-compat: primary memory alias
memory: ?[]u8,
// Multiple memories
memories: Array(Memory),
// Data segments (active) for multiple memories
data_segments: Array(DataSegment),

table: ?Array(value.Value),
table_element_type: ?value.Type,
table_max_size: ?u32,
// Legacy single-memory fields retained for compatibility
memory_min_pages: u64,
memory_max_pages: ?u64,
memory_is_64bit: bool,

globals: Array(Global),
imports: Array(Import),
exports: Array(Export),
start_function_index: ?u32,
cfg: Array(FunctionCFG),
// Passive bulk-memory storage (for memory.init/data.drop)
passive_data_segments: Array([]u8) = undefined,
passive_data_dropped: Array(bool) = undefined,
// Passive element segments (for table.init/elem.drop)
passive_elem_segments: Array([]usize) = undefined,
passive_elem_dropped: Array(bool) = undefined,

pub fn init(allocator: Allocator, io: std.Io) !*Module {
    const module = try allocator.create(Module);
    module.* = .{
        .allocator = allocator,
        .io = io,
        .functions = try Array(*Function).initCapacity(allocator, 0),
        .types = try Array(Signature).initCapacity(allocator, 0),
        .gc_types = try Array(GCType).initCapacity(allocator, 0),
        .memory = null,
        .table = null,
        .table_element_type = null,
        .table_max_size = null,
        .memories = try Array(Memory).initCapacity(allocator, 0),
        .data_segments = try Array(DataSegment).initCapacity(allocator, 0),
        .memory_min_pages = 1,
        .memory_max_pages = null,
        .memory_is_64bit = false,
        .globals = try Array(Global).initCapacity(allocator, 0),
        .imports = try Array(Import).initCapacity(allocator, 0),
        .exports = try Array(Export).initCapacity(allocator, 0),
        .start_function_index = null,
        .cfg = try Array(FunctionCFG).initCapacity(allocator, 0),
        .passive_data_segments = try Array([]u8).initCapacity(allocator, 0),
        .passive_data_dropped = try Array(bool).initCapacity(allocator, 0),
        .passive_elem_segments = try Array([]usize).initCapacity(allocator, 0),
        .passive_elem_dropped = try Array(bool).initCapacity(allocator, 0),
    };
    // Don't pre-allocate memory - let the memory section parsing handle it
    // This ensures data segments are copied to the correct memory buffer

    return module;
}

/// Keep the primary memory view (`memory` alias and the first entry in
/// `memories`) consistent after allocations or growth.
pub fn setPrimaryMemory(self: *Module, buffer: []u8) void {
    const page_size: usize = 65536;
    const pages: u64 = @intCast((buffer.len + page_size - 1) / page_size);

    self.memory = buffer;
    self.memory_min_pages = pages;

    if (self.memories.items.len > 0) {
        self.memories.items[0].data = buffer;
        self.memories.items[0].min_pages = pages;
    }
}

fn readHeapValueType(reader: *Reader, module: *Module) !ValueType {
    const first = try reader.readByte();
    return switch (first) {
        0x63, 0x64 => {
            const heap_type = try reader.readLEB128();
            if (heap_type < module.gc_types.items.len) {
                return switch (module.gc_types.items[heap_type]) {
                    .struct_type => .structref,
                    .array_type => .arrayref,
                    .none => .anyref,
                };
            }
            return .anyref;
        },
        else => try ValueType.fromByte(first),
    };
}

pub fn parse(allocator: Allocator, io: std.Io, bytes: []const u8) !*Module {
    var reader = Reader.init(bytes);

    // Check magic number and version
    const magic = try reader.readBytes(4);
    if (!std.mem.eql(u8, magic, "\x00asm")) return error.InvalidMagic;

    const version = try reader.readBytes(4);
    if (!std.mem.eql(u8, version, "\x01\x00\x00\x00")) return error.InvalidVersion;

    const module = try Module.init(allocator, io);
    errdefer module.deinit();

    var function_type_indices = try Array(u32).initCapacity(allocator, 0);
    defer function_type_indices.deinit(allocator);

    // Initialize default primary memory via memories list (set above)
    module.memory_min_pages = 1;

    // Parse sections
    while (reader.pos < reader.bytes.len) {
        const section_id = try reader.readByte();
        const section_size = try reader.readLEB128();
        const section_data = try reader.readBytes(section_size);

        // Safely handle section_id by using a switch with explicit cases
        // instead of trying to convert to enum directly
        switch (section_id) {
            0 => {
                var o = Log.op("custom", "section");
                o.log("Skipping custom section (size: {d})", .{section_size});
            },
            1 => {
                // Type section
                const o = Log.op("type", "section");
                _ = o;
                var type_reader = Reader.init(section_data);
                const count = try type_reader.readLEB128();
                // Reserve capacity to avoid reallocations while appending
                try module.types.ensureTotalCapacityPrecise(allocator, module.types.items.len + count);
                try module.gc_types.ensureTotalCapacityPrecise(allocator, module.gc_types.items.len + count);
                var i: usize = 0;
                while (i < count) : (i += 1) {
                    const form = try type_reader.readByte();
                    if (form == 0x5F) {
                        const field_count = try type_reader.readLEB128();
                        var fields = try allocator.alloc(ValueType, field_count);
                        errdefer allocator.free(fields);
                        for (0..field_count) |j| {
                            fields[j] = try readHeapValueType(&type_reader, module);
                            _ = try type_reader.readByte(); // mutability
                        }
                        try module.gc_types.append(allocator, .{ .struct_type = fields });
                        try module.types.append(allocator, .{ .params = &[_]ValueType{}, .results = &[_]ValueType{} });
                        continue;
                    }

                    if (form == 0x5E) {
                        const element_type = try readHeapValueType(&type_reader, module);
                        const mutable = (try type_reader.readByte()) != 0;
                        try module.gc_types.append(allocator, .{ .array_type = .{
                            .element_type = element_type,
                            .mutable = mutable,
                        } });
                        try module.types.append(allocator, .{ .params = &[_]ValueType{}, .results = &[_]ValueType{} });
                        continue;
                    }

                    if (form != 0x60) return error.InvalidType;

                    const param_count = try type_reader.readLEB128();
                    var params = try allocator.alloc(ValueType, param_count);
                    for (0..param_count) |j| {
                        params[j] = try readHeapValueType(&type_reader, module);
                    }

                    const result_count = try type_reader.readLEB128();
                    var results = try allocator.alloc(ValueType, result_count);
                    for (0..result_count) |j| {
                        results[j] = try readHeapValueType(&type_reader, module);
                    }

                    try module.gc_types.append(allocator, .none);
                    try module.types.append(allocator, .{
                        .params = params,
                        .results = results,
                    });
                }
            },
            2 => {
                // Import section - skip for now
                var o = Log.op("import", "section");
                o.log("Parsing import section (size: {d})", .{section_size});
                var import_reader = Reader.init(section_data);
                const count = try import_reader.readLEB128();
                try module.imports.ensureTotalCapacityPrecise(allocator, module.imports.items.len + count);
                o.log("  Found {d} imports", .{count});

                var i: usize = 0;
                while (i < count) : (i += 1) {
                    // Read module name
                    const module_name_len = try import_reader.readLEB128();
                    const module_name = try import_reader.readBytes(module_name_len);

                    // Read field name
                    const field_name_len = try import_reader.readLEB128();
                    const field_name = try import_reader.readBytes(field_name_len);

                    // Read kind
                    const kind = try import_reader.readByte();

                    var import_type: @import("module/export.zig").Type = undefined;
                    var type_index: ?u32 = null;

                    switch (kind) {
                        0x00 => { // Function import
                            import_type = .function;
                            type_index = try import_reader.readLEB128();

                            // Create function placeholder
                            const func = try allocator.create(Function);
                            errdefer allocator.destroy(func);

                            func.* = .{
                                .type_index = type_index.?,
                                .code = &[_]u8{}, // Empty code for imported function
                                .locals = &[_]ValueType{}, // No locals for imported function
                                .imported = true,
                            };

                            try module.functions.append(allocator, func);
                        },
                        0x01 => { // Table import
                            import_type = .table;
                            const elem_type = try import_reader.readByte();
                            // Accept funcref (0x70) and externref (0x6F), but default to funcref for unknown types
                            // to maintain compatibility with newer WASM features

                            const has_max = try import_reader.readByte();
                            const initial_size = try import_reader.readLEB128();
                            var max_size: u32 = 0;

                            if (has_max == 1) {
                                max_size = try import_reader.readLEB128();
                            }

                            o.log("  Table import: initial={d}, max={d}", .{ initial_size, max_size });

                            module.table_element_type = value.Type.fromByte(elem_type) catch .funcref;

                            // Initialize table with null references
                            if (module.table == null) {
                                var table = try Array(value.Value).initCapacity(allocator, 0);
                                errdefer table.deinit(allocator);

                                try table.resize(allocator, initial_size);
                                for (table.items) |*item| {
                                    item.* = .{ .funcref = null };
                                }

                                module.table = table;
                            }
                        },
                        0x02 => { // Memory import
                            import_type = .memory;
                            const limits_flags = try import_reader.readByte();
                            const has_max = (limits_flags & 0x01) != 0;
                            const is_shared = (limits_flags & 0x02) != 0;
                            const is_memory64 = (limits_flags & 0x04) != 0;
                            // Shared memory is not yet fully supported, but we'll accept it gracefully
                            // and treat it as non-shared memory for now to support more WASM files
                            if (is_shared) {
                                var warn_log = Log.op("import", "warning");
                                warn_log.log("  Shared memory import detected - treating as non-shared (partial support)", .{});
                            }

                            const min_pages: u64 = if (is_memory64)
                                try import_reader.readLEB128_u64()
                            else
                                @as(u64, try import_reader.readLEB128());

                            var max_pages: ?u64 = null;
                            if (has_max) {
                                max_pages = if (is_memory64)
                                    try import_reader.readLEB128_u64()
                                else
                                    @as(u64, try import_reader.readLEB128());
                            }

                            // Initialize memory
                            if (module.memory) |mem| {
                                allocator.free(mem);
                            }

                            const page_size: u64 = 65536;
                            const memory_size_u128 = @as(u128, min_pages) * page_size;
                            if (memory_size_u128 > @as(u128, std.math.maxInt(usize))) return error.InvalidModule;
                            const memory_size: usize = @intCast(memory_size_u128);

                            o.log("  Allocating imported memory: {d} pages ({d} bytes)", .{ min_pages, memory_size });

                            const actual_pages = @max(min_pages, @as(u64, 12));
                            const actual_memory_size = actual_pages * page_size;
                            const buf = try allocator.alloc(u8, actual_memory_size);
                            @memset(buf, 0);
                            o.log("  -> Actually allocated {d} pages ({d} bytes) for imported memory", .{ actual_pages, actual_memory_size });
                            module.memory = buf;
                            module.memory_min_pages = actual_pages;
                            module.memory_max_pages = max_pages;
                            module.memory_is_64bit = is_memory64;
                            type_index = 0;
                        },
                        0x03 => { // Global import
                            import_type = .global;
                            const val_type = try import_reader.readByte();
                            const global_type = try ValueType.fromByte(val_type);
                            const mutability = try import_reader.readByte(); // 0 = const, 1 = var

                            // Initialize with default val
                            const default_val: value.Value = switch (global_type) {
                                .i32 => .{ .i32 = 0 },
                                .i64 => .{ .i64 = 0 },
                                .f32 => .{ .f32 = 0.0 },
                                .f64 => .{ .f64 = 0.0 },
                                .funcref => .{ .funcref = null },
                                .externref => .{ .externref = null },
                                .v128 => .{ .v128 = [_]u8{0} **16 },
                                else => .{ .i32 = 0 }, // Default to i32 for unknown types
                            };

                            try module.globals.append(allocator, .{
                                .value = default_val,
                                .mutable = mutability == 1,
                                .val_type = global_type,
                            });
                        },
                        else => {
                            // Unknown import kind - log warning and skip gracefully
                            var warn_log = Log.op("import", "warning");
                            warn_log.log("  Unknown import kind: 0x{X:0>2} - skipping gracefully", .{kind});
                            import_type = .function; // Default to function to avoid crash
                            type_index = 0;
                        },
                    }

                    // Store the import information
                    const module_name_copy = try allocator.dupe(u8, module_name);
                    const field_name_copy = try allocator.dupe(u8, field_name);

                    try module.imports.append(allocator, .{
                        .module = module_name_copy,
                        .name = field_name_copy,
                        .kind = @as(Export.Type, import_type),
                        .type_index = type_index.?,
                    });

                    o.log("  Import {d}: module=\"{s}\", field=\"{s}\", kind={d}", .{
                        i, module_name, field_name, kind,
                    });
                }
            },
            3 => {
                // Function section
                var func_reader = Reader.init(section_data);
                const count = try func_reader.readLEB128();
                // Reserve for defined functions (in addition to already appended imported ones)
                try module.functions.ensureTotalCapacityPrecise(allocator, module.functions.items.len + count);
                var i: usize = 0;
                while (i < count) : (i += 1) {
                    const type_idx = try func_reader.readLEB128();
                    try function_type_indices.append(allocator, type_idx);
                }
            },
            4 => {
                var o = Log.op("table", "section");
                // Table section
                o.log("Parsing table section (size: {d})", .{section_size});

                var table_reader = Reader.init(section_data);
                const count = try table_reader.readLEB128();
                if (count > 1) {
                    // WASM 2.0+ allows multiple tables, but we currently only support one
                    // Log warning and use the first table only
                    var warn_log = Log.op("table", "warning");
                    warn_log.log("  Multiple tables detected ({d}) - only using first table (partial WASM 2.0 support)", .{count});
                }

                // Process the first table (or all tables if count <= 1)
                var table_idx: usize = 0;
                while (table_idx < count) : (table_idx += 1) {
                    const elem_type = try table_reader.readByte();
                    // Typed function references: accept any ref type; default to funcref when unknown

                    const has_max = try table_reader.readByte();
                    const initial_size = try table_reader.readLEB128();
                    var max_size: u32 = 0;

                    if (has_max == 1) {
                        max_size = try table_reader.readLEB128();
                    }

                    // Only use the first table for now
                    if (table_idx == 0) {
                        module.table_max_size = if (has_max == 1) max_size else null;
                        o.log("  Table {d}: initial={d}, max={?d}", .{ table_idx, initial_size, module.table_max_size });

                        module.table_element_type = value.Type.fromByte(elem_type) catch .funcref;

                        // Initialize table with null references if not already initialized
                        if (module.table == null) {
                            var table = try Array(value.Value).initCapacity(allocator, 0);
                            errdefer table.deinit(allocator);

                            try table.resize(allocator, initial_size);
                            for (table.items) |*item| {
                                item.* = .{ .funcref = null };
                            }

                            module.table = table;
                        } else {
                            // If table exists, ensure it's at least as large as initial_size
                            if (module.table.?.items.len < initial_size) {
                                try module.table.?.resize(allocator, initial_size);
                                for (module.table.?.items[module.table.?.items.len - (initial_size - module.table.?.items.len) ..]) |*item| {
                                    item.* = .{ .funcref = null };
                                }
                            }
                        }
                    } else {
                        // Skip additional tables with a log
                        o.log("  Skipping table {d} (only table 0 supported)", .{table_idx});
                    }
                }
            },
            5 => {
                // Memory section
                var mem_reader = Reader.init(section_data);
                const count = try mem_reader.readLEB128();
                // Reset any default memory and rebuild from section entries
                // Free existing memories' buffers
                var idx_free: usize = 0;
                while (idx_free < module.memories.items.len) : (idx_free += 1) {
                    module.allocator.free(module.memories.items[idx_free].data);
                }
                module.memories.clearRetainingCapacity();

                var i_mem: usize = 0;
                while (i_mem < count) : (i_mem += 1) {
                    const limits_flags = try mem_reader.readByte();
                    const has_max = (limits_flags & 0x01) != 0;
                    const is_shared = (limits_flags & 0x02) != 0;
                    const is_memory64 = (limits_flags & 0x04) != 0;

                    // Shared memory is not yet fully supported, but we'll accept it gracefully
                    // and treat it as non-shared memory for now to support more WASM files
                    if (is_shared) {
                        var warn_log = Log.op("memory", "warning");
                        warn_log.log("  Shared memory detected - treating as non-shared (partial support)", .{});
                    }

                    const min_pages: u64 = if (is_memory64)
                        try mem_reader.readLEB128_u64()
                    else
                        @as(u64, try mem_reader.readLEB128());

                    var max_pages: ?u64 = null;
                    if (has_max) {
                        max_pages = if (is_memory64)
                            try mem_reader.readLEB128_u64()
                        else
                            @as(u64, try mem_reader.readLEB128());
                    }

                    const page_size: u64 = 65536;
                    const memory_size_u128 = @as(u128, min_pages) * page_size;
                    if (memory_size_u128 > @as(u128, std.math.maxInt(usize))) return error.InvalidModule;
                    const memory_size: usize = @intCast(memory_size_u128);

                    var o = Log.op("memory", "section");
                    o.log("Allocating memory[{d}] {d} pages ({d} bytes)", .{ i_mem, min_pages, memory_size });

                    // Give the guest a small safety cushion to avoid libc startup crashes
                    // on tiny memories (common with wasi-sdk crt). Respect the declared max.
                    const baseline: u64 = 12;
                    const target_pages = @max(min_pages, baseline);
                    const actual_pages = if (max_pages) |max| @min(target_pages, max) else target_pages;
                    const actual_memory_size = actual_pages * page_size;
                    const buf = try allocator.alloc(u8, actual_memory_size);
                    // Initialize all memory with zeros
                    @memset(buf, 0);
                    o.log("  -> Allocated {d} pages ({d} bytes)", .{ actual_pages, actual_memory_size });
                    // Store the buffer with the actual allocated size
                    try module.memories.append(allocator, .{ .data = buf, .min_pages = actual_pages, .max_pages = max_pages, .is64 = is_memory64 });
                }
                // Primary alias for backwards compatibility
                if (module.memories.items.len > 0) {
                    module.memory_max_pages = module.memories.items[0].max_pages;
                    module.memory_is_64bit = module.memories.items[0].is64;
                    module.setPrimaryMemory(module.memories.items[0].data);
                } else {
                    module.memory = null;
                }
            },
            6 => {
                // Global section
                var global_reader = Reader.init(section_data);
                const count = try global_reader.readLEB128();
                try module.globals.ensureTotalCapacityPrecise(allocator, module.globals.items.len + count);
                var o = Log.op("global", "section");
                o.log("Parsing {d} globals", .{count});

                var i: usize = 0;
                while (i < count) : (i += 1) {
                    const val_type = try global_reader.readByte();
                    const global_type = try ValueType.fromByte(val_type);
                    const mutability = try global_reader.readByte(); // 0 = const, 1 = var
                    o.log("Global {d}: type={s}, mutability={d}", .{ i, @tagName(global_type), mutability });

                    // Read initialization expression
                    var init_expr = Expression.init(allocator);
                    defer init_expr.deinit();
                    try init_expr.parse(&global_reader);

                    // Evaluate the constant expression
                    const init_value = try module.evaluateConstantExpression(&init_expr);

                    try module.globals.append(allocator, .{
                        .value = init_value,
                        .mutable = mutability == 1,
                        .val_type = global_type,
                    });
                }
            },
            7 => {
                // Export section

                var o = Log.op("export", "section");
                o.log("Parsing export section (size: {d})", .{section_size});
                var export_reader = Reader.init(section_data);
                const count = try export_reader.readLEB128();
                try module.exports.ensureTotalCapacityPrecise(allocator, module.exports.items.len + count);
                o.log("  Found {d} exports", .{count});

                var i: usize = 0;
                while (i < count) : (i += 1) {
                    // Read export name
                    const name_len = try export_reader.readLEB128();
                    const name = try export_reader.readBytes(name_len);

                    // Read kind and index
                    const kind = try export_reader.readByte();
                    const index = try export_reader.readLEB128();

                    // Copy name to ensure it lives beyond the section data
                    const name_copy = try allocator.dupe(u8, name);

                    // Add to exports
                    try module.exports.append(allocator, .{
                        .name = name_copy,
                        .kind = @import("module/export.zig").Type.fromByte(kind),
                        .index = index,
                    });

                    o.log("  Export {d}: name=\"{s}\", kind={d}, index={d}", .{
                        i, name, kind, index,
                    });

                    switch (kind) {
                        0x00 => o.log("    (Function export)", .{}),
                        0x01 => o.log("    (Table export)", .{}),
                        0x02 => o.log("    (Memory export)", .{}),
                        0x03 => o.log("    (Global export)", .{}),
                        else => o.log("    (Unknown export kind)", .{}),
                    }
                }
            },
            8 => {
                // Start section
                var o = Log.op("start", "section");
                o.log("Parsing start section (size: {d})", .{section_size});
                var start_reader = Reader.init(section_data);
                const func_index = try start_reader.readLEB128();
                module.start_function_index = func_index;
                o.log(" error.Start function index: {d}", .{func_index});
            },
            9 => {
                var o = Log.op("element", "section");
                // Element section
                o.log("Parsing element section (size: {d})", .{section_size});

                var elem_reader = Reader.init(section_data);
                const count = try elem_reader.readLEB128();
                o.log("  Found {d} element segments", .{count});

                // Debug: Check if table exists before proceeding
                if (module.table) |table| {
                    o.log("  Table exists with size: {d}", .{table.items.len});
                    o.log("  Table contents before initialization:", .{});
                    for (table.items, 0..) |item, idx| {
                        o.log("    table[{d}] = {any}", .{ idx, item });
                    }
                } else {
                    o.log("  ERROR: Table does not exist before element section parsing!", .{});
                }

                var i: usize = 0;
                while (i < count) : (i += 1) {
                    const flags = try elem_reader.readLEB128();
                    switch (flags) {
                        0 => {
                            // Active element segment targeting table 0 with offset expr
                            var offset_expr = Expression.init(allocator);
                            defer offset_expr.deinit();
                            try offset_expr.parse(&elem_reader);
                            const offset_value = try module.evaluateConstantExpression(&offset_expr);
                            const offset = @as(usize, @intCast(offset_value.i32));
                            const num_elems = try elem_reader.readLEB128();

                            if (module.table == null) {
                                o.log("  Error: No table initialized for element segment", .{});
                                return error.InvalidModule;
                            }
                            if (offset + num_elems > module.table.?.items.len) {
                                try module.table.?.resize(allocator, offset + num_elems);
                                for (module.table.?.items[module.table.?.items.len - num_elems ..]) |*item| item.* = .{ .funcref = null };
                            }
                            var j: usize = 0;
                            while (j < num_elems) : (j += 1) {
                                const func_idx = try elem_reader.readLEB128();
                                module.table.?.items[offset + j] = .{ .funcref = func_idx };
                            }
                            o.log("  Initialized active element seg at offset {d} count {d}", .{ offset, num_elems });
                        },
                        1, 3 => {
                            // Passive or declarative: store indices for table.init
                            const elemkind_or_type = try elem_reader.readByte();
                            _ = elemkind_or_type; // expect funcref
                            const n = try elem_reader.readLEB128();
                            const list = try allocator.alloc(usize, n);
                            for (list, 0..) |*slot, k| {
                                _ = k;
                                slot.* = try elem_reader.readLEB128();
                            }
                            try module.passive_elem_segments.append(allocator, list);
                            try module.passive_elem_dropped.append(allocator, false);
                            o.log("  Stored passive element seg {d} with {d} funcs", .{ i, n });
                        },
                        2 => {
                            // Active with explicit table index
                            const table_idx = try elem_reader.readLEB128();
                            if (table_idx != 0) {
                                var warn_log = Log.op("element", "warning");
                                warn_log.log("  Non-zero table index ({d}) - only table 0 is supported, skipping segment", .{table_idx});
                                // Skip this segment by reading and discarding its data
                                var offset_expr = Expression.init(allocator);
                                defer offset_expr.deinit();
                                try offset_expr.parse(&elem_reader);
                                const elemkind_or_type = try elem_reader.readByte();
                                _ = elemkind_or_type;
                                const num_elems = try elem_reader.readLEB128();
                                var j: usize = 0;
                                while (j < num_elems) : (j += 1) {
                                    _ = try elem_reader.readLEB128();
                                }
                                continue;
                            }
                            var offset_expr = Expression.init(allocator);
                            defer offset_expr.deinit();
                            try offset_expr.parse(&elem_reader);
                            const offset_value = try module.evaluateConstantExpression(&offset_expr);
                            const offset = @as(usize, @intCast(offset_value.i32));
                            const elemkind_or_type = try elem_reader.readByte();
                            _ = elemkind_or_type;
                            const num_elems = try elem_reader.readLEB128();
                            if (module.table == null) {
                                return error.InvalidModule;
                            }
                            if (offset + num_elems > module.table.?.items.len) {
                                try module.table.?.resize(allocator, offset + num_elems);
                                for (module.table.?.items[module.table.?.items.len - num_elems ..]) |*item| item.* = .{ .funcref = null };
                            }
                            var j: usize = 0;
                            while (j < num_elems) : (j += 1) {
                                const func_idx = try elem_reader.readLEB128();
                                module.table.?.items[offset + j] = .{ .funcref = func_idx };
                            }
                            o.log("  Initialized active(element) segment at offset {d} count {d}", .{ offset, num_elems });
                        },
                        else => {
                            // Unknown element segment kind - log warning and skip gracefully
                            var warn_log = Log.op("element", "warning");
                            warn_log.log("  Unknown element segment kind: {d} - attempting to skip", .{flags});
                            // Try to consume the segment data to avoid corrupting the parser
                            // This is a best-effort approach - may still fail on malformed data
                            _ = elem_reader.readByte() catch break;
                            const n = elem_reader.readLEB128() catch break;
                            var k: usize = 0;
                            while (k < n) : (k += 1) {
                                _ = elem_reader.readLEB128() catch break;
                            }
                        },
                    }
                }

                // Debug: Check table after initialization
                if (module.table) |table| {
                    o.log("  Table contents after initialization:", .{});
                    for (table.items, 0..) |item, idx| {
                        o.log("    table[{d}] = {any}", .{ idx, item });
                    }
                }
            },
            10 => {
                // Code section
                var code_reader = Reader.init(section_data);
                const count = try code_reader.readLEB128();
                try module.cfg.ensureTotalCapacityPrecise(allocator, module.cfg.items.len + count);
                if (count != function_type_indices.items.len) return error.InvalidModule;

                var i: usize = 0;
                while (i < count) : (i += 1) {
                    const size = try code_reader.readLEB128();
                    const body_start = code_reader.pos;
                    const body_end = body_start + size;
                    if (body_end > section_data.len) return error.InvalidModule;

                    var o = Log.op("code", "section");
                    o.log("Parsing function {d} body at offset {d}, size {d}", .{ i, body_start, size });

                    // Read local declarations
                    const local_decl_count = try code_reader.readLEB128();
                    if (local_decl_count > 10000) {
                        // Very high number of local declarations - log warning but continue
                        var warn_log = Log.op("code", "warning");
                        warn_log.log("  Function {d} has {d} local declarations (unusually high)", .{ i, local_decl_count });
                    }
                    o.log("Local declarations count: {d}", .{local_decl_count});

                    var locals_tmp = try Array(ValueType).initCapacity(allocator, 0);
                    defer locals_tmp.deinit(allocator);

                    var j: usize = 0;
                    while (j < local_decl_count) : (j += 1) {
                        const repeat_count = try code_reader.readLEB128();
                        if (repeat_count > 100000) {
                            // Very high local repeat count - log warning but continue
                            var warn_log = Log.op("code", "warning");
                            warn_log.log("  Local decl {d} in function {d} has repeat count {d} (unusually high)", .{ j, i, repeat_count });
                        }
                        const local_type = readHeapValueType(&code_reader, module) catch |err| {
                            o.log("Error: Invalid local type at index {d}: {any}", .{ j, err });
                            return err;
                        };
                        o.log("Local declaration {d}: count={d}, type={s}", .{ j, repeat_count, @tagName(local_type) });

                        var k: usize = 0;
                        while (k < repeat_count) : (k += 1) {
                            try locals_tmp.append(allocator, local_type);
                        }
                    }

                    // Create function
                    const func = try allocator.create(Function);
                    errdefer allocator.destroy(func);

                    const locals = try allocator.alloc(ValueType, locals_tmp.items.len);
                    errdefer allocator.free(locals);
                    @memcpy(locals, locals_tmp.items);

                    // The remaining bytes after locals declarations are the function body
                    const code_start = code_reader.pos;
                    if (code_start > body_end) return error.InvalidModule;

                    func.* = .{
                        .type_index = function_type_indices.items[i],
                        .code = section_data[code_start..body_end],
                        .locals = locals,
                    };
                    try module.functions.append(allocator, func);
                    // Placeholder CFG slot; filled during validation
                    try module.cfg.append(allocator, .{ .blocks = &[_]BlockSummary{} });

                    // Skip to end of function body
                    code_reader.pos = body_end;

                    o.log("Function {d} parsed with {d} locals, code size {d}", .{ i, locals.len, func.code.len });
                }
            },
            11 => {
                // Data section
                var o = Log.op("data", "section");
                o.log("Parsing data section (size: {d})", .{section_size});

                var data_reader = Reader.init(section_data);
                const count = try data_reader.readLEB128();
                o.log("  Found {d} data segments", .{count});

                var i: usize = 0;
                while (i < count) : (i += 1) {
                    const flags = try data_reader.readLEB128();
                    switch (flags) {
                        0 => { // active, memidx=0
                            // offset expr
                            var offset_expr = Expression.init(allocator);
                            defer offset_expr.deinit();
                            try offset_expr.parse(&data_reader);
                            const offset_value = try module.evaluateConstantExpression(&offset_expr);
                            const offset = @as(usize, @intCast(offset_value.i32));
                            const data_size = try data_reader.readLEB128();
                            const data = try data_reader.readBytes(data_size);
                            const data_copy = try allocator.alloc(u8, data_size);
                            @memcpy(data_copy, data);
                            o.log("  Active data seg {d}: offset=0x{X}, size={d}", .{ i, offset, data_size });
                            const required_size = offset + data_size;
                            if (module.memory == null) {
                                const buffer = try allocator.alloc(u8, required_size);
                                @memset(buffer, 0);
                                module.setPrimaryMemory(buffer);
                            } else if (required_size > module.memory.?.len) {
                                const old_buffer = module.memory.?;
                                const buffer = try allocator.alloc(u8, required_size);
                                @memcpy(buffer[0..old_buffer.len], old_buffer);
                                @memset(buffer[old_buffer.len..], 0);
                                allocator.free(old_buffer);
                                module.setPrimaryMemory(buffer);
                            }
                            @memcpy(module.memory.?[offset .. offset + data_size], data_copy);
                            try module.data_segments.append(allocator, .{
                                .memory_index = 0,
                                .offset = offset,
                                .data = data_copy,
                            });
                        },
                        1 => { // passive
                            const data_size = try data_reader.readLEB128();
                            const data = try allocator.alloc(u8, data_size);
                            const seg_bytes = try data_reader.readBytes(data_size);
                            @memcpy(data, seg_bytes);
                            try module.passive_data_segments.append(allocator, data);
                            try module.passive_data_dropped.append(allocator, false);
                            o.log("  Stored passive data seg {d} size={d}", .{ i, data_size });
                        },
                        2 => { // active with memidx
                            const memidx = try data_reader.readLEB128();
                            var offset_expr = Expression.init(allocator);
                            defer offset_expr.deinit();
                            try offset_expr.parse(&data_reader);
                            const offset_value = try module.evaluateConstantExpression(&offset_expr);
                            const offset = @as(usize, @intCast(offset_value.i32));
                            const data_size = try data_reader.readLEB128();
                            const data = try data_reader.readBytes(data_size);
                            const data_copy = try allocator.alloc(u8, data_size);
                            @memcpy(data_copy, data);
                            o.log("  Active (memidx) data seg {d}: offset=0x{X}, size={d}", .{ i, offset, data_size });
                            const required_size = offset + data_size;
                            if (module.memory == null) {
                                const buffer = try allocator.alloc(u8, required_size);
                                @memset(buffer, 0);
                                module.setPrimaryMemory(buffer);
                            } else if (required_size > module.memory.?.len) {
                                const old_buffer = module.memory.?;
                                const buffer = try allocator.alloc(u8, required_size);
                                @memcpy(buffer[0..old_buffer.len], old_buffer);
                                @memset(buffer[old_buffer.len..], 0);
                                allocator.free(old_buffer);
                                module.setPrimaryMemory(buffer);
                            }
                            @memcpy(module.memory.?[offset .. offset + data_size], data_copy);
                            try module.data_segments.append(allocator, .{
                                .memory_index = @intCast(memidx),
                                .offset = offset,
                                .data = data_copy,
                            });
                        },
                        else => {
                            // Unknown data segment kind - log warning and skip gracefully
                            var warn_log = Log.op("data", "warning");
                            warn_log.log("  Unknown data segment flags: {d} - attempting to skip", .{flags});
                            // Try to read and discard the data to keep parser in sync
                            const data_size = data_reader.readLEB128() catch break;
                            _ = data_reader.readBytes(data_size) catch break;
                        },
                    }
                }
            },
            else => {
                // Unknown section - skip gracefully
                var o = Log.op("unknown", "section");
                o.log("Skipping unknown section ID: {d} (size: {d})", .{ section_id, section_size });
            },
        }
    }

    return module;
}

pub fn deinit(self: *Module) void {
    for (self.functions.items) |func| {
        self.allocator.free(func.locals);
        self.allocator.destroy(func);
    }
    for (self.types.items) |*typ| {
        if (typ.params.len > 0) self.allocator.free(typ.params);
        if (typ.results.len > 0) self.allocator.free(typ.results);
    }
    for (self.gc_types.items) |gc_type| {
        switch (gc_type) {
            .struct_type => |fields| self.allocator.free(fields),
            else => {},
        }
    }

    // Free import strings
    for (self.imports.items) |import| {
        self.allocator.free(import.module);
        self.allocator.free(import.name);
    }

    // Free export strings
    for (self.exports.items) |exp| {
        self.allocator.free(exp.name);
    }

    self.functions.deinit(self.allocator);
    self.types.deinit(self.allocator);
    self.gc_types.deinit(self.allocator);
    // Free memories
    for (self.memories.items) |m| {
        self.allocator.free(m.data);
    }
    self.memories.deinit(self.allocator);
    for (self.data_segments.items) |seg| {
        self.allocator.free(seg.data);
    }
    self.data_segments.deinit(self.allocator);
    if (self.table) |*table| {
        table.deinit(self.allocator);
    }
    // Free passive data segments
    for (self.passive_data_segments.items) |seg| {
        self.allocator.free(seg);
    }
    self.passive_data_segments.deinit(self.allocator);
    self.passive_data_dropped.deinit(self.allocator);
    // Free passive element segments
    for (self.passive_elem_segments.items) |seg| {
        self.allocator.free(seg);
    }
    self.passive_elem_segments.deinit(self.allocator);
    self.passive_elem_dropped.deinit(self.allocator);
    self.globals.deinit(self.allocator);
    self.imports.deinit(self.allocator);
    self.exports.deinit(self.allocator);
    self.allocator.destroy(self);
}

// pub fn parseDataSection(self: *Module, reader: anytype) !void {
//     var reader = Reader.init(bytes);
//     const count = try reader.readULEB128(u32, reader);
//     o.log("Parsing data section with {d} segments\n", .{count});

//     var i: u32 = 0;
//     while (i < count) : (i += 1) {
//         const flags = try leb.readULEB128(u32, reader);
//         o.log("  Data segment {d} flags: {d}\n", .{ i, flags });

//         var memory_index: u32 = 0;
//         var offset_expr = Expression{};
//         var offset: u32 = 0;

//         if (flags == 0) {
//             try offset_expr.parse(reader);
//             const result = try self.evaluateConstantExpression(&offset_expr);
//             offset = @intCast(result.i32);
//             o.log("  Data segment {d} active, offset: {d}\n", .{ i, offset });
//         } else if (flags == 1) {
//             o.log("  Data segment {d} passive\n", .{i});
//         } else if (flags == 2) {
//             memory_index = try leb.readULEB128(u32, reader);
//             try offset_expr.parse(reader);
//             const result = try self.evaluateConstantExpression(&offset_expr);
//             offset = @intCast(result.i32);
//             o.log("  Data segment {d} active, memory: {d}, offset: {d}\n", .{ i, memory_index, offset });
//         } else {
//             return error.InvalidDataSegmentFlags;
//         }

//         const size = try leb.readULEB128(u32, reader);
//         o.log("  Data segment {d} size: {d} bytes\n", .{ i, size });

//         if (size > 0) {
//             const data = try self.allocator.alloc(u8, size);
//             errdefer self.allocator.free(data);

//             const bytes_read = try reader.readAll(data);
//             if (bytes_read != size) {
//                 return error.UnexpectedEndOfFile;
//             }

//             // o.log( the first few bytes of the data for debugging
//             if (size <= 64) {
//                 o.log("  Data content: ", .{});
//                 for (data) |byte| {
//                     if (byte >= 32 and byte <= 126) {
//                         o.log("{c}", .{byte});
//                     } else {
//                         o.log("\\x{X:0>2}", .{byte});
//                     }
//                 }
//                 o.log("\n", .{});
//             } else {
//                 o.log("  Data content (first 64 bytes): ", .{});
//                 for (data[0..@min(64, data.len)]) |byte| {
//                     if (byte >= 32 and byte <= 126) {
//                         o.log("{c}", .{byte});
//                     } else {
//                         o.log("\\x{X:0>2}", .{byte});
//                     }
//                 }
//                 o.log("...\n", .{});
//             }

//             if (flags != 1) { // Not passive
//                 try self.data_segments.append(self.allocator, .{
//                     .memory_index = memory_index,
//                     .offset = offset,
//                     .data = data,
//                 });
//             } else {
//                 // For passive segments, we just store them for now
//                 try self.passive_data_segments.append(self.allocator, data);
//             }
//         } else {
//             o.log("  Data segment {d} is empty\n", .{i});
//             if (flags != 1) { // Not passive
//                 try self.data_segments.append(self.allocator, .{
//                     .memory_index = memory_index,
//                     .offset = offset,
//                     .data = &[_]u8{},
//                 });
//             } else {
//                 // For passive segments, we just store them for now
//                 try self.passive_data_segments.append(self.allocator, &[_]u8{});
//             }
//         }
//     }
// }

pub fn initMemory(self: *Module) !void {
    // Initialize memory with data segments
    var o = Log.op("memory", "init");
    o.log("Initializing memory with {d} data segments\n", .{self.data_segments.items.len});

    for (self.data_segments.items, 0..) |segment, i| {
        if (segment.memory_index >= self.memories.items.len) {
            return error.InvalidMemoryIndex;
        }

        const memory = &self.memories.items[segment.memory_index];
        const offset = segment.offset;
        const data = segment.data;

        o.log("Initializing memory[{d}] at offset {d} with {d} bytes\n", .{
            segment.memory_index, offset, data.len,
        });

        if (offset + data.len > memory.data.len) {
            o.log("Error: Data segment {d} would exceed memory bounds (offset={d}, size={d}, memory_size={d})\n", .{ i, offset, data.len, memory.data.len });
            return error.DataSegmentOutOfBounds;
        }

        // Copy data to memory
        @memcpy(memory.data[offset..][0..data.len], data);

        // Debug o.log( the data
        if (data.len <= 64) {
            o.log("  Data content: ", .{});
            for (data) |byte| {
                if (byte >= 32 and byte <= 126) {
                    o.log("{c}", .{byte});
                } else {
                    o.log("\\x{X:0>2}", .{byte});
                }
            }
            o.log("\n", .{});
        } else {
            o.log("  Data content (first 64 bytes): ", .{});
            for (data[0..@min(64, data.len)]) |byte| {
                if (byte >= 32 and byte <= 126) {
                    o.log("{c}", .{byte});
                } else {
                    o.log("\\x{X:0>2}", .{byte});
                }
            }
            o.log("...\n", .{});
        }
    }
}

/// Evaluates a constant expression and returns the result
/// Used for global initializers, element segments, and data segments
pub fn evaluateConstantExpression(self: *Module, expr: *const Expression) !Value {
    return try expr.evaluate(self);
}

/// Validates a WebAssembly module before execution
/// This checks for common errors and inconsistencies in the module
pub fn validateModule(self: *Module) !void {
    var o = Log.op("validateModule", "");
    o.log("Validating WebAssembly module", .{});

    // 1. Validate function signatures against type section
    o.log("Validating {d} functions against type section", .{self.functions.items.len});
    for (self.functions.items, 0..) |func, idx| {
        if (func.type_index >= self.types.items.len) {
            o.log("Error: Function {d} has invalid type index {d} (max: {d})", .{ idx, func.type_index, self.types.items.len - 1 });
            return error.InvalidTypeIndex;
        }
    }

    // 2. Validate imports
    o.log("Validating {d} imports", .{self.imports.items.len});
    for (self.imports.items, 0..) |import, idx| {
        if (import.kind == .function and import.type_index >= self.types.items.len) {
            o.log("Error: Import {d} ({s}::{s}) has invalid type index {d} (max: {d})", .{ idx, import.module, import.name, import.type_index, self.types.items.len - 1 });
            return error.InvalidTypeIndex;
        }
    }

    // 3. Validate exports
    o.log("Validating {d} exports", .{self.exports.items.len});
    for (self.exports.items, 0..) |export_item, idx| {
        return switch (export_item.kind) {
            .function => {
                if (export_item.index >= self.functions.items.len) {
                    o.log("Error: Export {d} ({s}) references invalid function index {d} (max: {d})", .{ idx, export_item.name, export_item.index, self.functions.items.len - 1 });
                    return error.InvalidExportIndex;
                }
            },
            .memory => {
                if (self.memory == null) {
                    o.log("Error: Export {d} ({s}) references memory but no memory section exists", .{ idx, export_item.name });
                    return error.InvalidExport;
                }
            },
            .table => {
                if (self.table == null) {
                    o.log("Error: Export {d} ({s}) references table but no table section exists", .{ idx, export_item.name });
                    return error.InvalidExport;
                }
            },
            .global => {
                if (export_item.index >= self.globals.items.len) {
                    o.log("Error: Export {d} ({s}) references invalid global index {d} (max: {d})", .{ idx, export_item.name, export_item.index, self.globals.items.len - 1 });
                    return error.InvalidExportIndex;
                }
            },
        };
    }

    // 4. Validate function code
    o.log("Validating function code", .{});
    for (self.functions.items, 0..) |func, idx| {
        if (!func.imported) {
            // Skip imports - they don't have code
            try validateFunctionCode(self, func, idx);
        }
    }

    o.log("Module validation complete", .{});
}

/// Validates the bytecode of a single function
fn validateFunctionCode(module: *Module, func: *Function, func_idx: usize) !void {
    var o = Log.op("validateFunctionCode", "");
    o.log("Validating function {d} code ({d} bytes)", .{ func_idx, func.code.len });

    // Create a reader for the function code
    var code_reader = Reader.init(func.code);

    // Quick pre-scan to size validation stacks (approximate # of blocks)
    var approx_blocks: usize = 0;
    for (func.code) |b|
        switch (b) {
            0x02, 0x03, 0x04 => approx_blocks += 1, // block/loop/if
            else => {},
        };

    // Track blocks for balance checking (function body is implicit block)
    var block_depth: usize = 1;
    var blocks = try Array(BlockSummary).initCapacity(module.allocator, @max(8, approx_blocks + 2));
    defer blocks.deinit(module.allocator);
    var start_stack = try Array(usize).initCapacity(module.allocator, @max(8, approx_blocks + 2));
    defer start_stack.deinit(module.allocator);
    const ElseOpen = struct { end_depth: usize, idx: usize };
    var else_stack = try Array(ElseOpen).initCapacity(module.allocator, @max(4, approx_blocks));
    defer else_stack.deinit(module.allocator);

    // Track value types on conceptual stack for type checking
    var type_stack = try Array(ValueType).initCapacity(module.allocator, 0);
    defer type_stack.deinit(module.allocator);

    // Get the function type
    const func_type = module.types.items[func.type_index];

    // Add locals (parameters + locals)
    var locals = try Array(ValueType).initCapacity(module.allocator, 0);
    defer locals.deinit(module.allocator);

    // Add parameters as locals first
    try locals.appendSlice(module.allocator, func_type.params);

    // Add function-defined locals
    for (func.locals) |local_type|
        try locals.append(module.allocator, local_type);
    while (code_reader.pos < func.code.len) {
        const opcode = code_reader.readByte() catch |err| {
            o.log("Error reading opcode at position {d}: {any}", .{ code_reader.pos, err });
            return err;
        };

        // Handle control flow instructions
        switch (opcode) {
            0x02, 0x03, 0x04 => { // block, loop, if
                // Record start position of this block (current opcode was at pos-1)
                const start_pos = code_reader.pos - 1;
                try start_stack.append(module.allocator, start_pos);
                block_depth += 1;

                // Skip block type
                _ = code_reader.readByte() catch |err| {
                    o.log("Error reading block type at position {d}: {any}", .{ code_reader.pos, err });
                    return err;
                };

                // For if instructions, ensure there's a condition value
                if (opcode == 0x04 and type_stack.items.len == 0) {
                    o.log("Error: if instruction at position {d} without condition value", .{code_reader.pos - 2});
                    return error.TypeMismatch;
                }

                // Pop the condition for if
                if (opcode == 0x04) {
                    const condition_type = type_stack.pop();
                    if (condition_type == null or condition_type.? != .i32) {
                        o.log("Error: if instruction at position {d} with invalid condition type", .{code_reader.pos - 2});
                        return error.TypeMismatch;
                    }
                }
            },
            0x05 => { // else
                if (block_depth == 0) {
                    o.log("Error: else instruction at position {d} without matching if", .{code_reader.pos - 1});
                    return error.InvalidCode;
                }
                const else_pos = code_reader.pos - 1;
                const idx = blocks.items.len;
                try blocks.append(module.allocator, .{ .start_pos = else_pos, .end_pos = 0 });
                // Matching end will reduce depth by 1
                try else_stack.append(module.allocator, .{ .end_depth = block_depth - 1, .idx = idx });
                // Note: we don't decrement block_depth for else
            },
            0x0B => { // end
                if (block_depth == 0) {
                    o.log("Error: end instruction at position {d} without matching block", .{code_reader.pos - 1});
                    return error.InvalidCode;
                }
                block_depth -= 1;
                const end_pos = code_reader.pos - 1;
                const start_opt = if (start_stack.items.len > 0) start_stack.pop() else null;
                const start_pos = if (start_opt) |sp| sp else 0;
                try blocks.append(module.allocator, .{ .start_pos = start_pos, .end_pos = end_pos });
                // If an else region is open for this depth,.close() it now
                if (else_stack.items.len > 0) {
                    const top = else_stack.items[else_stack.items.len - 1];
                    if (top.end_depth == block_depth) {
                        else_stack.items.len -= 1;
                        blocks.items[top.idx].end_pos = end_pos;
                    }
                }
            },
            // Handle local access
            0x20 => { // local.get
                const local_idx = code_reader.readLEB128() catch |err| {
                    o.log("Error reading local index at position {d}: {any}", .{ code_reader.pos, err });
                    return err;
                };

                if (local_idx >= locals.items.len) {
                    o.log("Error: local.get at position {d} references invalid local index {d} (max: {d})", .{ code_reader.pos - 2, local_idx, locals.items.len - 1 });
                    return error.InvalidLocalIndex;
                }

                // Push the local's type onto the stack
                try type_stack.append(module.allocator, locals.items[local_idx]);
            },
            0x21 => { // local.set
                const local_idx = code_reader.readLEB128() catch |err| {
                    o.log("Error reading local index at position {d}: {any}", .{ code_reader.pos, err });
                    return err;
                };

                if (local_idx >= locals.items.len) {
                    o.log("Error: local.set at position {d} references invalid local index {d} (max: {d})", .{ code_reader.pos - 2, local_idx, locals.items.len - 1 });
                    return error.InvalidLocalIndex;
                }

                // Check for stack underflow
                if (type_stack.items.len == 0) {
                    o.log("Error: local.set at position {d} with empty stack", .{code_reader.pos - 2});
                    return error.StackUnderflow;
                }

                // Pop the value type and check compatibility
                const value_type = type_stack.pop() orelse {
                    o.log("Error: local.set at position {d} with empty stack", .{code_reader.pos - 2});
                    return error.StackUnderflow;
                };
                if (value_type != locals.items[local_idx]) {
                    o.log("Error: local.set at position {d} with incompatible types: expected {s}, got {s}", .{ code_reader.pos - 2, @tagName(locals.items[local_idx]), @tagName(value_type) });
                    return error.TypeMismatch;
                }
            },
            // Memory operations
            0x28, 0x29, 0x2A, 0x2B => { // i32.load, i64.load, f32.load, f64.load
                // Skip alignment and offset
                _ = code_reader.readLEB128() catch |err| {
                    o.log("Error reading alignment at position {d}: {any}", .{ code_reader.pos, err });
                    return err;
                };
                _ = code_reader.readLEB128() catch |err| {
                    o.log("Error reading offset at position {d}: {any}", .{ code_reader.pos, err });
                    return err;
                };

                // Check for memory section
                if (module.memory == null) {
                    o.log("Error: memory operation at position {d} but no memory section exists", .{code_reader.pos - 3});
                    return error.InvalidMemoryAccess;
                }

                // Check for address on stack
                if (type_stack.items.len == 0) {
                    o.log("Error: memory load at position {d} with empty stack", .{code_reader.pos - 3});
                    return error.StackUnderflow;
                }

                // Pop address and check type
                const addr_type = type_stack.pop() orelse {
                    o.log("Error: memory load at position {d} with empty stack", .{code_reader.pos - 3});
                    return error.StackUnderflow;
                };
                const addr_expected: ValueType = if (module.memory_is_64bit) .i64 else .i32;
                if (addr_type != addr_expected) {
                    o.log("Error: memory load at position {d} with incorrect address type: expected {s}, got {s}", .{ code_reader.pos - 3, @tagName(addr_expected), @tagName(addr_type) });
                    return error.TypeMismatch;
                }

                // Push result type based on opcode
                const result_type: ValueType = switch (opcode) {
                    0x28 => .i32,
                    0x29 => .i64,
                    0x2A => .f32,
                    0x2B => .f64,
                    else => unreachable,
                };
                try type_stack.append(module.allocator, result_type);
            },
            // Memory store operations
            0x36, 0x37, 0x38, 0x39 => { // i32.store, i64.store, f32.store, f64.store
                // Skip alignment and offset
                _ = code_reader.readLEB128() catch |err| {
                    o.log("Error reading alignment at position {d}: {any}", .{ code_reader.pos, err });
                    return err;
                };
                _ = code_reader.readLEB128() catch |err| {
                    o.log("Error reading offset at position {d}: {any}", .{ code_reader.pos, err });
                    return err;
                };

                // Check for memory section
                if (module.memory == null) {
                    o.log("Error: memory store at position {d} but no memory section exists", .{code_reader.pos - 3});
                    return error.InvalidMemoryAccess;
                }

                // Check for value and address on stack
                if (type_stack.items.len < 2) {
                    o.log("Error: memory store at position {d} with insufficient stack values", .{code_reader.pos - 3});
                    return error.StackUnderflow;
                }

                // Pop value and address, check types
                const value_type = type_stack.pop().?;
                const addr_type = type_stack.pop().?;
                const addr_expected: ValueType = if (module.memory_is_64bit) .i64 else .i32;
                if (addr_type != addr_expected) {
                    o.log("Error: memory store at position {d} with incorrect address type: expected {s}, got {s}", .{ code_reader.pos - 3, @tagName(addr_expected), @tagName(addr_type) });
                    return error.TypeMismatch;
                }
                const expected_value_type: ValueType = switch (opcode) {
                    0x36 => .i32,
                    0x37 => .i64,
                    0x38 => .f32,
                    0x39 => .f64,
                    else => unreachable,
                };
                if (value_type != expected_value_type) {
                    o.log("Error: memory store at position {d} with invalid value type: expected {s}, got {s}", .{ code_reader.pos - 3, @tagName(expected_value_type), @tagName(value_type) });
                    return error.TypeMismatch;
                }
            },
            0x3A, 0x3B => { // i32.store8, i32.store16
                // Skip alignment and offset
                _ = code_reader.readLEB128() catch |err| {
                    o.log("Error reading alignment at position {d}: {any}", .{ code_reader.pos, err });
                    return err;
                };
                _ = code_reader.readLEB128() catch |err| {
                    o.log("Error reading offset at position {d}: {any}", .{ code_reader.pos, err });
                    return err;
                };

                // Check for memory section
                if (module.memory == null) {
                    o.log("Error: memory store at position {d} but no memory section exists", .{code_reader.pos - 3});
                    return error.InvalidMemoryAccess;
                }

                // Check for value and address on stack
                if (type_stack.items.len < 2) {
                    o.log("Error: memory store at position {d} with insufficient stack values", .{code_reader.pos - 3});
                    return error.StackUnderflow;
                }

                // Pop value and address, check types
                const value_type = type_stack.pop().?;
                const addr_type = type_stack.pop().?;
                const addr_expected: ValueType = if (module.memory_is_64bit) .i64 else .i32;
                if (addr_type != addr_expected) {
                    o.log("Error: memory store at position {d} with incorrect address type: expected {s}, got {s}", .{ code_reader.pos - 3, @tagName(addr_expected), @tagName(addr_type) });
                    return error.TypeMismatch;
                }
                if (value_type != .i32) {
                    o.log("Error: i32 memory store at position {d} with invalid value type: {s}", .{ code_reader.pos - 3, @tagName(value_type) });
                    return error.TypeMismatch;
                }
            },
            0x3C, 0x3D, 0x3E => { // i64.store8, i64.store16, i64.store32
                // Skip alignment and offset
                _ = code_reader.readLEB128() catch |err| {
                    o.log("Error reading alignment at position {d}: {any}", .{ code_reader.pos, err });
                    return err;
                };
                _ = code_reader.readLEB128() catch |err| {
                    o.log("Error reading offset at position {d}: {any}", .{ code_reader.pos, err });
                    return err;
                };

                // Check for memory section
                if (module.memory == null) {
                    o.log("Error: memory store at position {d} but no memory section exists", .{code_reader.pos - 3});
                    return error.InvalidMemoryAccess;
                }

                // Check for value and address on stack
                if (type_stack.items.len < 2) {
                    o.log("Error: memory store at position {d} with insufficient stack values", .{code_reader.pos - 3});
                    return error.StackUnderflow;
                }

                // Pop value and address, check types
                const value_type = type_stack.pop().?;
                const addr_type = type_stack.pop().?;
                const addr_expected: ValueType = if (module.memory_is_64bit) .i64 else .i32;
                if (addr_type != addr_expected) {
                    o.log("Error: memory store at position {d} with incorrect address type: expected {s}, got {s}", .{ code_reader.pos - 3, @tagName(addr_expected), @tagName(addr_type) });
                    return error.TypeMismatch;
                }
                if (value_type != .i64) {
                    o.log("Error: i64 memory store at position {d} with invalid value type: {s}", .{ code_reader.pos - 3, @tagName(value_type) });
                    return error.TypeMismatch;
                }
            },
            // i32 operations
            0x41 => { // i32.const
                _ = code_reader.readSLEB32() catch |err| {
                    o.log("Error reading i32.const value at position {d}: {any}", .{ code_reader.pos, err });
                    return err;
                };
                try type_stack.append(module.allocator, .i32);
            },
            0x45 => { // i32.eqz
                if (type_stack.items.len == 0) {
                    o.log("Error: i32.eqz at position {d} with empty stack", .{code_reader.pos - 1});
                    return error.StackUnderflow;
                }
                const val_type = type_stack.pop();
                if (val_type.? != .i32) {
                    o.log("Error: i32.eqz at position {d} with invalid operand type: {s}", .{ code_reader.pos - 1, @tagName(val_type.?) });
                    return error.TypeMismatch;
                }
                try type_stack.append(module.allocator, .i32);
            },
            0x46...0x4F => { // i32 comparison ops (eq, ne, lt_s, lt_u, gt_s, gt_u, le_s, le_u, ge_s, ge_u)
                if (type_stack.items.len < 2) {
                    o.log("Error: i32 comparison at position {d} with insufficient stack values", .{code_reader.pos - 1});
                    return error.StackUnderflow;
                }
                const rhs = type_stack.pop().?;
                const lhs = type_stack.pop().?;
                if (lhs != .i32 or rhs != .i32) {
                    o.log("Error: i32 comparison at position {d} with invalid operand types: {s}, {s}", .{ code_reader.pos - 1, @tagName(lhs), @tagName(rhs) });
                    return error.TypeMismatch;
                }
                try type_stack.append(module.allocator, .i32);
            },
            0x67...0x78 => { // i32 arithmetic and bitwise ops (clz, ctz, popcnt, add, sub, mul, div_s, div_u, rem_s, rem_u, and, or, xor, shl, shr_s, shr_u, rotl, rotr)
                if (type_stack.items.len < 2) {
                    o.log("Error: i32 binary op at position {d} with insufficient stack values", .{code_reader.pos - 1});
                    return error.StackUnderflow;
                }
                const rhs = type_stack.pop().?;
                const lhs = type_stack.pop().?;
                if (lhs != .i32 or rhs != .i32) {
                    o.log("Error: i32 binary op at position {d} with invalid operand types: {s}, {s}", .{ code_reader.pos - 1, @tagName(lhs), @tagName(rhs) });
                    return error.TypeMismatch;
                }
                try type_stack.append(module.allocator, .i32);
            },
            0xA7...0xAB => { // i32 conversion ops (wrap_i64, trunc_f32_s, trunc_f32_u, trunc_f64_s, trunc_f64_u)
                if (type_stack.items.len == 0) {
                    o.log("Error: i32 conversion at position {d} with empty stack", .{code_reader.pos - 1});
                    return error.StackUnderflow;
                }
                const val_type = type_stack.pop().?;
                const expected_type: ValueType = switch (opcode) {
                    0xA7 => .i64, // wrap_i64
                    0xA8, 0xA9 => .f32, // trunc_f32_s, trunc_f32_u
                    0xAA, 0xAB => .f64, // trunc_f64_s, trunc_f64_u
                    else => unreachable,
                };
                if (val_type != expected_type) {
                    o.log("Error: i32 conversion at position {d} with invalid operand type: expected {s}, got {s}", .{ code_reader.pos - 1, @tagName(expected_type), @tagName(val_type) });
                    return error.TypeMismatch;
                }
                try type_stack.append(module.allocator, .i32);
            },
            0xBC => { // i32.reinterpret_f32
                if (type_stack.items.len == 0) {
                    o.log("Error: i32.reinterpret_f32 at position {d} with empty stack", .{code_reader.pos - 1});
                    return error.StackUnderflow;
                }
                const val_type = type_stack.pop().?;
                if (val_type != .f32) {
                    o.log("Error: i32.reinterpret_f32 at position {d} with invalid operand type: {s}", .{ code_reader.pos - 1, @tagName(val_type) });
                    return error.TypeMismatch;
                }
                try type_stack.append(module.allocator, .i32);
            },
            // i64 operations
            0x42 => { // i64.const
                _ = code_reader.readSLEB64() catch |err| {
                    o.log("Error reading i64.const value at position {d}: {any}", .{ code_reader.pos, err });
                    return err;
                };
                try type_stack.append(module.allocator, .i64);
            },
            0x50 => { // i64.eqz
                if (type_stack.items.len == 0) {
                    o.log("Error: i64.eqz at position {d} with empty stack", .{code_reader.pos - 1});
                    return error.StackUnderflow;
                }
                const val_type = type_stack.pop().?;
                if (val_type != .i64) {
                    o.log("Error: i64.eqz at position {d} with invalid operand type: {s}", .{ code_reader.pos - 1, @tagName(val_type) });
                    return error.TypeMismatch;
                }
                try type_stack.append(module.allocator, .i64);
            },
            0x51...0x5A => { // i64 comparison ops (eq, ne, lt_s, lt_u, gt_s, gt_u, le_s, le_u, ge_s, ge_u)
                if (type_stack.items.len < 2) {
                    o.log("Error: i64 comparison at position {d} with insufficient stack values", .{code_reader.pos - 1});
                    return error.StackUnderflow;
                }
                const rhs = type_stack.pop().?;
                const lhs = type_stack.pop().?;
                if (lhs != .i64 or rhs != .i64) {
                    o.log("Error: i64 comparison at position {d} with invalid operand types: {s}, {s}", .{ code_reader.pos - 1, @tagName(lhs), @tagName(rhs) });
                    return error.TypeMismatch;
                }
                try type_stack.append(module.allocator, .i64);
            },
            0x79...0x8A => { // i64 arithmetic and bitwise ops (clz, ctz, popcnt, add, sub, mul, div_s, div_u, rem_s, rem_u, and, or, xor, shl, shr_s, shr_u, rotl, rotr)
                if (type_stack.items.len < 2) {
                    o.log("Error: i64 binary op at position {d} with insufficient stack values", .{code_reader.pos - 1});
                    return error.StackUnderflow;
                }
                const rhs = type_stack.pop().?;
                const lhs = type_stack.pop().?;
                if (lhs != .i64 or rhs != .i64) {
                    o.log("Error: i64 binary op at position {d} with invalid operand types: {s}, {s}", .{ code_reader.pos - 1, @tagName(lhs), @tagName(rhs) });
                    return error.TypeMismatch;
                }
                try type_stack.append(module.allocator, .i64);
            },
            0xAC...0xB1 => { // i64 conversion ops (extend_i32_s, extend_i32_u, trunc_f32_s, trunc_f32_u, trunc_f64_s, trunc_f64_u)
                if (type_stack.items.len == 0) {
                    o.log("Error: i64 conversion at position {d} with empty stack", .{code_reader.pos - 1});
                    return error.StackUnderflow;
                }
                const val_type = type_stack.pop().?;
                const expected_type: ValueType = switch (opcode) {
                    0xAC, 0xAD => .i32, // extend_i32_s, extend_i32_u
                    0xAE, 0xAF => .f32, // trunc_f32_s, trunc_f32_u
                    0xB0, 0xB1 => .f64, // trunc_f64_s, trunc_f64_u
                    else => unreachable,
                };
                if (val_type != expected_type) {
                    o.log("Error: i64 conversion at position {d} with invalid operand type: expected {s}, got {s}", .{ code_reader.pos - 1, @tagName(expected_type), @tagName(val_type) });
                    return error.TypeMismatch;
                }
                try type_stack.append(module.allocator, .i64);
            },
            0xBD => { // i64.reinterpret_f64
                if (type_stack.items.len == 0) {
                    o.log("Error: i64.reinterpret_f64 at position {d} with empty stack", .{code_reader.pos - 1});
                    return error.StackUnderflow;
                }
                const val_type = type_stack.pop().?;
                if (val_type != .f64) {
                    o.log("Error: i64.reinterpret_f64 at position {d} with invalid operand type: {s}", .{ code_reader.pos - 1, @tagName(val_type) });
                    return error.TypeMismatch;
                }
                try type_stack.append(module.allocator, .i64);
            },
            // f32 operations
            0x43 => { // f32.const
                _ = code_reader.readBytes(4) catch |err| {
                    o.log("Error reading f32.const value at position {d}: {any}", .{ code_reader.pos, err });
                    return err;
                };
                try type_stack.append(module.allocator, .f32);
            },
            0x5B...0x60 => { // f32 comparison ops (eq, ne, lt, gt, le, ge)
                if (type_stack.items.len < 2) {
                    o.log("Error: f32 comparison at position {d} with insufficient stack values", .{code_reader.pos - 1});
                    return error.StackUnderflow;
                }
                const rhs = type_stack.pop().?;
                const lhs = type_stack.pop().?;
                if (lhs != .f32 or rhs != .f32) {
                    o.log("Error: f32 comparison at position {d} with invalid operand types: {s}, {s}", .{ code_reader.pos - 1, @tagName(lhs), @tagName(rhs) });
                    return error.TypeMismatch;
                }
                try type_stack.append(module.allocator, .i32);
            },
            0x8B...0x98 => { // f32 unary and binary ops (abs, neg, ceil, floor, trunc, nearest, sqrt, add, sub, mul, div, min, max, copysign)
                if (opcode >= 0x92) { // binary ops start at add (0x92)
                    if (type_stack.items.len < 2) {
                        o.log("Error: f32 binary op at position {d} with insufficient stack values", .{code_reader.pos - 1});
                        return error.StackUnderflow;
                    }
                    const rhs = type_stack.pop().?;
                    const lhs = type_stack.pop().?;
                    if (lhs != .f32 or rhs != .f32) {
                        o.log("Error: f32 binary op at position {d} with invalid operand types: {s}, {s}", .{ code_reader.pos - 1, @tagName(lhs), @tagName(rhs) });
                        return error.TypeMismatch;
                    }
                } else { // unary ops
                    if (type_stack.items.len == 0) {
                        o.log("Error: f32 unary op at position {d} with empty stack", .{code_reader.pos - 1});
                        return error.StackUnderflow;
                    }
                    const val_type = type_stack.pop().?;
                    if (val_type != .f32) {
                        o.log("Error: f32 unary op at position {d} with invalid operand type: {s}", .{ code_reader.pos - 1, @tagName(val_type) });
                        return error.TypeMismatch;
                    }
                }
                try type_stack.append(module.allocator, .f32);
            },
            0xB2...0xB6 => { // f32 conversion ops (convert_i32_s, convert_i32_u, convert_i64_s, convert_i64_u, demote_f64)
                if (type_stack.items.len == 0) {
                    o.log("Error: f32 conversion at position {d} with empty stack", .{code_reader.pos - 1});
                    return error.StackUnderflow;
                }
                const val_type = type_stack.pop().?;
                const expected_type: ValueType = switch (opcode) {
                    0xB2, 0xB3 => .i32, // convert_i32_s, convert_i32_u
                    0xB4, 0xB5 => .i64, // convert_i64_s, convert_i64_u
                    0xB6 => .f64, // demote_f64
                    else => unreachable,
                };
                if (val_type != expected_type) {
                    o.log("Error: f32 conversion at position {d} with invalid operand type: expected {s}, got {s}", .{ code_reader.pos - 1, @tagName(expected_type), @tagName(val_type) });
                    return error.TypeMismatch;
                }
                try type_stack.append(module.allocator, .f32);
            },
            0xBE => { // f32.reinterpret_i32
                if (type_stack.items.len == 0) {
                    o.log("Error: f32.reinterpret_i32 at position {d} with empty stack", .{code_reader.pos - 1});
                    return error.StackUnderflow;
                }
                const val_type = type_stack.pop().?;
                if (val_type != .i32) {
                    o.log("Error: f32.reinterpret_i32 at position {d} with invalid operand type: {s}", .{ code_reader.pos - 1, @tagName(val_type) });
                    return error.TypeMismatch;
                }
                try type_stack.append(module.allocator, .f32);
            },
            // f64 operations
            0x44 => { // f64.const
                _ = code_reader.readBytes(8) catch |err| {
                    o.log("Error reading f64.const value at position {d}: {any}", .{ code_reader.pos, err });
                    return err;
                };
                try type_stack.append(module.allocator, .f64);
            },
            0x61...0x66 => { // f64 comparison ops (eq, ne, lt, gt, le, ge)
                if (type_stack.items.len < 2) {
                    o.log("Error: f64 comparison at position {d} with insufficient stack values", .{code_reader.pos - 1});
                    return error.StackUnderflow;
                }
                const rhs = type_stack.pop().?;
                const lhs = type_stack.pop().?;
                if (lhs != .f64 or rhs != .f64) {
                    o.log("Error: f64 comparison at position {d} with invalid operand types: {s}, {s}", .{ code_reader.pos - 1, @tagName(lhs), @tagName(rhs) });
                    return error.TypeMismatch;
                }
                try type_stack.append(module.allocator, .i32);
            },
            0x99...0xA6 => { // f64 unary and binary ops (abs, neg, ceil, floor, trunc, nearest, sqrt, add, sub, mul, div, min, max, copysign)
                if (opcode >= 0xA0) { // binary ops start at add (0xA0)
                    if (type_stack.items.len < 2) {
                        o.log("Error: f64 binary op at position {d} with insufficient stack values", .{code_reader.pos - 1});
                        return error.StackUnderflow;
                    }
                    const rhs = type_stack.pop().?;
                    const lhs = type_stack.pop().?;
                    if (lhs != .f64 or rhs != .f64) {
                        o.log("Error: f64 binary op at position {d} with invalid operand types: {s}, {s}", .{ code_reader.pos - 1, @tagName(lhs), @tagName(rhs) });
                        return error.TypeMismatch;
                    }
                } else { // unary ops
                    if (type_stack.items.len == 0) {
                        o.log("Error: f64 unary op at position {d} with empty stack", .{code_reader.pos - 1});
                        return error.StackUnderflow;
                    }
                    const val_type = type_stack.pop().?;
                    if (val_type != .f64) {
                        o.log("Error: f64 unary op at position {d} with invalid operand type: {s}", .{ code_reader.pos - 1, @tagName(val_type) });
                        return error.TypeMismatch;
                    }
                }
                try type_stack.append(module.allocator, .f64);
            },
            0xB7...0xBB => { // f64 conversion ops (convert_i32_s, convert_i32_u, convert_i64_s, convert_i64_u, promote_f32)
                if (type_stack.items.len == 0) {
                    o.log("Error: f64 conversion at position {d} with empty stack", .{code_reader.pos - 1});
                    return error.StackUnderflow;
                }
                const val_type = type_stack.pop().?;
                const expected_type: ValueType = switch (opcode) {
                    0xB7, 0xB8 => .i32, // convert_i32_s, convert_i32_u
                    0xB9, 0xBA => .i64, // convert_i64_s, convert_i64_u
                    0xBB => .f32, // promote_f32
                    else => unreachable,
                };
                if (val_type != expected_type) {
                    o.log("Error: f64 conversion at position {d} with invalid operand type: expected {s}, got {s}", .{ code_reader.pos - 1, @tagName(expected_type), @tagName(val_type) });
                    return error.TypeMismatch;
                }
                try type_stack.append(module.allocator, .f64);
            },
            0xBF => { // f64.reinterpret_i64
                if (type_stack.items.len == 0) {
                    o.log("Error: f64.reinterpret_i64 at position {d} with empty stack", .{code_reader.pos - 1});
                    return error.StackUnderflow;
                }
                const val_type = type_stack.pop().?;
                if (val_type != .i64) {
                    o.log("Error: f64.reinterpret_i64 at position {d} with invalid operand type: {s}", .{ code_reader.pos - 1, @tagName(val_type) });
                    return error.TypeMismatch;
                }
                try type_stack.append(module.allocator, .f64);
            },
            // Global operations
            0x23 => { // global.get
                const global_idx = code_reader.readLEB128() catch |err| {
                    o.log("Error reading global index at position {d}: {any}", .{ code_reader.pos, err });
                    return err;
                };

                if (global_idx >= module.globals.items.len) {
                    o.log("Error: global.get at position {d} references invalid global index {d} (max: {d})", .{ code_reader.pos - 2, global_idx, module.globals.items.len - 1 });
                    return error.InvalidGlobalIndex;
                }
                const global_type = module.globals.items[global_idx].val_type;
                try type_stack.append(module.allocator, global_type);
            },
            0x24 => { // global.set
                const global_idx = code_reader.readLEB128() catch |err| {
                    o.log("Error reading global index at position {d}: {any}", .{ code_reader.pos, err });
                    return err;
                };

                if (global_idx >= module.globals.items.len) {
                    o.log("Error: global.set at position {d} references invalid global index {d} (max: {d})", .{ code_reader.pos - 2, global_idx, module.globals.items.len - 1 });
                    return error.InvalidGlobalIndex;
                }

                if (type_stack.items.len == 0) {
                    o.log("Error: global.set at position {d} with empty stack", .{code_reader.pos - 2});
                    return error.StackUnderflow;
                }

                const value_type = type_stack.pop().?;
                const global_type = module.globals.items[global_idx].val_type;
                if (value_type != global_type) {
                    o.log("Error: global.set at position {d} with incompatible types: expected {s}, got {s}", .{ code_reader.pos - 2, @tagName(global_type), @tagName(value_type) });
                    return error.TypeMismatch;
                }
            },
            // Table operations
            0x25 => { // table.get
                const table_idx = code_reader.readLEB128() catch |err| {
                    o.log("Error reading table index at position {d}: {any}", .{ code_reader.pos, err });
                    return err;
                };

                if (module.table == null) {
                    o.log("Error: table.get at position {d} but no table section exists", .{code_reader.pos - 2});
                    return error.InvalidTableAccess;
                }

                if (table_idx >= 1) { // WebAssembly 1.0 only supports one table
                    o.log("Error: table.get at position {d} references invalid table index {d}", .{ code_reader.pos - 2, table_idx });
                    return error.InvalidTableIndex;
                }

                if (type_stack.items.len == 0) {
                    o.log("Error: table.get at position {d} with empty stack", .{code_reader.pos - 2});
                    return error.StackUnderflow;
                }

                const index_type = type_stack.pop().?;
                if (index_type != .i32) {
                    o.log("Error: table.get at position {d} with non-i32 index type: {s}", .{ code_reader.pos - 2, @tagName(index_type) });
                    return error.TypeMismatch;
                }

                // Push the table's element type
                try type_stack.append(module.allocator, module.table_element_type.?);
            },
            0x26 => { // table.set
                const table_idx = code_reader.readLEB128() catch |err| {
                    o.log("Error reading table index at position {d}: {any}", .{ code_reader.pos, err });
                    return err;
                };

                if (module.table == null) {
                    o.log("Error: table.set at position {d} but no table section exists", .{code_reader.pos - 2});
                    return error.InvalidTableAccess;
                }

                if (table_idx >= 1) { // WebAssembly 1.0 only supports one table
                    o.log("Error: table.set at position {d} references invalid table index {d}", .{ code_reader.pos - 2, table_idx });
                    return error.InvalidTableIndex;
                }

                if (type_stack.items.len < 2) {
                    o.log("Error: table.set at position {d} with insufficient stack values", .{code_reader.pos - 2});
                    return error.StackUnderflow;
                }

                const value_type = type_stack.pop().?;
                const index_type = type_stack.pop().?;
                if (index_type != .i32) {
                    o.log("Error: table.set at position {d} with non-i32 index type: {s}", .{ code_reader.pos - 2, @tagName(index_type) });
                    return error.TypeMismatch;
                }
                if (value_type != module.table_element_type.?) {
                    o.log("Error: table.set at position {d} with incompatible value type: expected {s}, got {s}", .{ code_reader.pos - 2, @tagName(module.table_element_type.?), @tagName(value_type) });
                    return error.TypeMismatch;
                }
            },
            // Reference type operations
            0xD0 => { // ref.null
                const heap_type = code_reader.readLEB128() catch |err| {
                    o.log("Error reading heap type at position {d}: {any}", .{ code_reader.pos, err });
                    return err;
                };
                // For now, assume funcref (0x70) or externref (0x6F)
                const ref_type: ValueType = if (heap_type == 0x70) .funcref else .externref;
                try type_stack.append(module.allocator, ref_type);
            },
            0xD1 => { // ref.is_null
                if (type_stack.items.len == 0) {
                    o.log("Error: ref.is_null at position {d} with empty stack", .{code_reader.pos - 1});
                    return error.StackUnderflow;
                }
                const ref_type = type_stack.pop().?;
                if (ref_type != .funcref and ref_type != .externref) {
                    o.log("Error: ref.is_null at position {d} with invalid reference type: {s}", .{ code_reader.pos - 1, @tagName(ref_type) });
                    return error.TypeMismatch;
                }
                try type_stack.append(module.allocator, .i32);
            },
            0xD2 => { // ref.func
                const ref_func_idx = code_reader.readLEB128() catch |err| {
                    o.log("Error reading function index at position {d}: {any}", .{ code_reader.pos, err });
                    return err;
                };

                if (ref_func_idx >= module.functions.items.len) {
                    o.log("Error: ref.func at position {d} references invalid function index {d} (max: {d})", .{ code_reader.pos - 2, ref_func_idx, module.functions.items.len - 1 });
                    return error.InvalidFunctionIndex;
                }

                try type_stack.append(module.allocator, .funcref);
            },
            // Bulk memory and table operations (0xFC prefix)
            0xFC => {
                const sub_op = code_reader.readLEB128() catch |err| {
                    o.log("Error reading bulk operation sub-opcode at position {d}: {any}", .{ code_reader.pos, err });
                    return err;
                };
                switch (sub_op) {
                    0x08 => { // memory.init
                        const mem_idx = try code_reader.readLEB128();
                        if (mem_idx >= 1) { // WebAssembly 1.0 only supports one memory
                            o.log("Error: memory.init at position {d} references invalid memory index {d}", .{ code_reader.pos - 4, mem_idx });
                            return error.InvalidMemoryIndex;
                        }
                        const data_idx = try code_reader.readLEB128();
                        if (module.memory == null) {
                            o.log("Error: memory.init at position {d} but no memory section exists", .{code_reader.pos - 4});
                            return error.InvalidMemoryAccess;
                        }
                        if (type_stack.items.len < 3) {
                            o.log("Error: memory.init at position {d} with insufficient stack values", .{code_reader.pos - 4});
                            return error.StackUnderflow;
                        }
                        const n_type = type_stack.pop().?;
                        const src_type = type_stack.pop().?;
                        const dst_type = type_stack.pop().?;
                        if (n_type != .i32 or src_type != .i32 or dst_type != .i32) {
                            o.log("Error: memory.init at position {d} with invalid operand types", .{code_reader.pos - 4});
                            return error.TypeMismatch;
                        }
                        if (data_idx >= module.passive_data_segments.items.len) return error.InvalidAccess;
                        if (module.passive_data_dropped.items.len <= data_idx) return error.InvalidAccess;
                        if (module.passive_data_dropped.items[data_idx]) return error.InvalidAccess;
                    },
                    0x09 => { // data.drop
                        _ = try code_reader.readLEB128();
                        // No stack effect
                    },
                    0x0A => { // memory.copy
                        const dst_mem_idx = code_reader.readLEB128() catch |err| {
                            o.log("Error reading destination memory index at position {d}: {any}", .{ code_reader.pos, err });
                            return err;
                        };
                        const src_mem_idx = code_reader.readLEB128() catch |err| {
                            o.log("Error reading source memory index at position {d}: {any}", .{ code_reader.pos, err });
                            return err;
                        };
                        if (dst_mem_idx >= 1 or src_mem_idx >= 1) {
                            o.log("Error: memory.copy at position {d} references invalid memory index", .{code_reader.pos - 4});
                            return error.InvalidMemoryIndex;
                        }
                        if (module.memory == null) {
                            o.log("Error: memory.copy at position {d} but no memory section exists", .{code_reader.pos - 4});
                            return error.InvalidMemoryAccess;
                        }
                        if (type_stack.items.len < 3) {
                            o.log("Error: memory.copy at position {d} with insufficient stack values", .{code_reader.pos - 4});
                            return error.StackUnderflow;
                        }
                        const n_type = type_stack.pop().?;
                        const src_type = type_stack.pop().?;
                        const dst_type = type_stack.pop().?;
                        if (n_type != .i32 or src_type != .i32 or dst_type != .i32) {
                            o.log("Error: memory.copy at position {d} with invalid operand types", .{code_reader.pos - 4});
                            return error.TypeMismatch;
                        }
                    },
                    0x0B => { // memory.fill
                        const mem_idx = code_reader.readLEB128() catch |err| {
                            o.log("Error reading memory index at position {d}: {any}", .{ code_reader.pos, err });
                            return err;
                        };
                        if (mem_idx >= 1) {
                            o.log("Error: memory.fill at position {d} references invalid memory index {d}", .{ code_reader.pos - 3, mem_idx });
                            return error.InvalidMemoryIndex;
                        }
                        if (module.memory == null) {
                            o.log("Error: memory.fill at position {d} but no memory section exists", .{code_reader.pos - 3});
                            return error.InvalidMemoryAccess;
                        }
                        if (type_stack.items.len < 3) {
                            o.log("Error: memory.fill at position {d} with insufficient stack values", .{code_reader.pos - 3});
                            return error.StackUnderflow;
                        }
                        const n_type = type_stack.pop().?;
                        const val_type = type_stack.pop().?;
                        const dst_type = type_stack.pop().?;
                        if (n_type != .i32 or val_type != .i32 or dst_type != .i32) {
                            o.log("Error: memory.fill at position {d} with invalid operand types", .{code_reader.pos - 3});
                            return error.TypeMismatch;
                        }
                    },
                    0x0C => { // table.init
                        const elem_idx = try code_reader.readLEB128();
                        const table_idx = try code_reader.readLEB128();
                        if (elem_idx >= module.passive_elem_segments.items.len) return error.InvalidAccess;
                        if (module.passive_elem_dropped.items.len <= elem_idx) return error.InvalidAccess;
                        if (module.passive_elem_dropped.items[elem_idx]) return error.InvalidAccess;
                        if (table_idx >= 1) {
                            o.log("Error: table.init at position {d} references invalid table index {d}", .{ code_reader.pos - 4, table_idx });
                            return error.InvalidTableIndex;
                        }
                        if (module.table == null) {
                            o.log("Error: table.init at position {d} but no table section exists", .{code_reader.pos - 4});
                            return error.InvalidTableAccess;
                        }
                        if (type_stack.items.len < 3) {
                            o.log("Error: table.init at position {d} with insufficient stack values", .{code_reader.pos - 4});
                            return error.StackUnderflow;
                        }
                        const n_type = type_stack.pop().?;
                        const src_type = type_stack.pop().?;
                        const dst_type = type_stack.pop().?;
                        if (n_type != .i32 or src_type != .i32 or dst_type != .i32) {
                            o.log("Error: table.init at position {d} with invalid operand types", .{code_reader.pos - 4});
                            return error.TypeMismatch;
                        }
                    },
                    0x0D => { // elem.drop
                        _ = code_reader.readLEB128() catch |err| {
                            o.log("Error reading element index at position {d}: {any}", .{ code_reader.pos, err });
                            return err;
                        };
                        // No stack effect
                    },
                    0x0E => { // table.copy
                        const dst_table_idx = code_reader.readLEB128() catch |err| {
                            o.log("Error reading destination table index at position {d}: {any}", .{ code_reader.pos, err });
                            return err;
                        };
                        const src_table_idx = code_reader.readLEB128() catch |err| {
                            o.log("Error reading source table index at position {d}: {any}", .{ code_reader.pos, err });
                            return err;
                        };
                        if (dst_table_idx >= 1 or src_table_idx >= 1) {
                            o.log("Error: table.copy at position {d} references invalid table index", .{code_reader.pos - 4});
                            return error.InvalidTableIndex;
                        }
                        if (module.table == null) {
                            o.log("Error: table.copy at position {d} but no table section exists", .{code_reader.pos - 4});
                            return error.InvalidTableAccess;
                        }
                        if (type_stack.items.len < 3) {
                            o.log("Error: table.copy at position {d} with insufficient stack values", .{code_reader.pos - 4});
                            return error.StackUnderflow;
                        }
                        const n_type = type_stack.pop().?;
                        const src_type = type_stack.pop().?;
                        const dst_type = type_stack.pop().?;
                        if (n_type != .i32 or src_type != .i32 or dst_type != .i32) {
                            o.log("Error: table.copy at position {d} with invalid operand types", .{code_reader.pos - 4});
                            return error.TypeMismatch;
                        }
                    },
                    0x0F => { // table.grow
                        const table_idx = code_reader.readLEB128() catch |err| {
                            o.log("Error reading table index at position {d}: {any}", .{ code_reader.pos, err });
                            return err;
                        };
                        if (table_idx >= 1) {
                            o.log("Error: table.grow at position {d} references invalid table index {d}", .{ code_reader.pos - 3, table_idx });
                            return error.InvalidTableIndex;
                        }
                        if (module.table == null) {
                            o.log("Error: table.grow at position {d} but no table section exists", .{code_reader.pos - 3});
                            return error.InvalidTableAccess;
                        }
                        if (type_stack.items.len < 2) {
                            o.log("Error: table.grow at position {d} with insufficient stack values", .{code_reader.pos - 3});
                            return error.StackUnderflow;
                        }
                        const n_type = type_stack.pop().?;
                        const val_type = type_stack.pop().?;
                        if (n_type != .i32) {
                            o.log("Error: table.grow at position {d} with invalid n type: {s}", .{ code_reader.pos - 3, @tagName(n_type) });
                            return error.TypeMismatch;
                        }
                        if (val_type != module.table_element_type.?) {
                            o.log("Error: table.grow at position {d} with invalid value type: expected {s}, got {s}", .{ code_reader.pos - 3, @tagName(module.table_element_type.?), @tagName(val_type) });
                            return error.TypeMismatch;
                        }
                        try type_stack.append(module.allocator, .i32); // returns previous size
                    },
                    0x10 => { // table.size
                        const table_idx = code_reader.readLEB128() catch |err| {
                            o.log("Error reading table index at position {d}: {any}", .{ code_reader.pos, err });
                            return err;
                        };
                        if (table_idx >= 1) {
                            o.log("Error: table.size at position {d} references invalid table index {d}", .{ code_reader.pos - 3, table_idx });
                            return error.InvalidTableIndex;
                        }
                        if (module.table == null) {
                            o.log("Error: table.size at position {d} but no table section exists", .{code_reader.pos - 3});
                            return error.InvalidTableAccess;
                        }
                        try type_stack.append(module.allocator, .i32);
                    },
                    0x11 => { // table.fill
                        const table_idx = code_reader.readLEB128() catch |err| {
                            o.log("Error reading table index at position {d}: {any}", .{ code_reader.pos, err });
                            return err;
                        };
                        if (table_idx >= 1) {
                            o.log("Error: table.fill at position {d} references invalid table index {d}", .{ code_reader.pos - 3, table_idx });
                            return error.InvalidTableIndex;
                        }
                        if (module.table == null) {
                            o.log("Error: table.fill at position {d} but no table section exists", .{code_reader.pos - 3});
                            return error.InvalidTableAccess;
                        }
                        if (type_stack.items.len < 3) {
                            o.log("Error: table.fill at position {d} with insufficient stack values", .{code_reader.pos - 3});
                            return error.StackUnderflow;
                        }
                        const n_type = type_stack.pop().?;
                        const val_type = type_stack.pop().?;
                        const dst_type = type_stack.pop().?;
                        if (n_type != .i32 or dst_type != .i32) {
                            o.log("Error: table.fill at position {d} with invalid operand types", .{code_reader.pos - 3});
                            return error.TypeMismatch;
                        }
                        if (val_type != module.table_element_type.?) {
                            o.log("Error: table.fill at position {d} with invalid value type: expected {s}, got {s}", .{ code_reader.pos - 3, @tagName(module.table_element_type.?), @tagName(val_type) });
                            return error.TypeMismatch;
                        }
                    },
                    else => {
                        o.log("Error: unknown bulk operation sub-opcode 0x{x} at position {d}", .{ sub_op, code_reader.pos - 1 });
                        return error.InvalidOpcode;
                    },
                }
            },
            0xFB => {
                const sub_op = try code_reader.readLEB128();
                switch (sub_op) {
                    0x00 => {
                        const type_idx = try code_reader.readLEB128();
                        const fields = switch (module.gc_types.items[type_idx]) {
                            .struct_type => |fields| fields,
                            else => return error.TypeMismatch,
                        };
                        if (type_stack.items.len < fields.len) return error.StackUnderflow;
                        var n = fields.len;
                        while (n > 0) {
                            n -= 1;
                            _ = type_stack.pop();
                        }
                        try type_stack.append(module.allocator, .structref);
                    },
                    0x01 => {
                        const type_idx = try code_reader.readLEB128();
                        if (type_idx >= module.gc_types.items.len) return error.InvalidType;
                        try type_stack.append(module.allocator, .structref);
                    },
                    0x02, 0x03, 0x04 => {
                        const type_idx = try code_reader.readLEB128();
                        const field_idx = try code_reader.readLEB128();
                        const fields = switch (module.gc_types.items[type_idx]) {
                            .struct_type => |fields| fields,
                            else => return error.TypeMismatch,
                        };
                        if (field_idx >= fields.len) return error.InvalidType;
                        if (type_stack.items.len < 1) return error.StackUnderflow;
                        _ = type_stack.pop();
                        try type_stack.append(module.allocator, fields[field_idx]);
                    },
                    0x05 => {
                        const type_idx = try code_reader.readLEB128();
                        const field_idx = try code_reader.readLEB128();
                        const fields = switch (module.gc_types.items[type_idx]) {
                            .struct_type => |fields| fields,
                            else => return error.TypeMismatch,
                        };
                        if (field_idx >= fields.len) return error.InvalidType;
                        if (type_stack.items.len < 2) return error.StackUnderflow;
                        _ = type_stack.pop();
                        _ = type_stack.pop();
                    },
                    else => return error.UnsupportedInstruction,
                }
            },
            // Skip other opcodes for now - continue with more in next steps
            else => {
                // For opcodes not yet implemented in validation, skip for now
                // This will be completed in subsequent steps
            },
        }
    }

    // After processing all opcodes, ensure blocks are balanced
    if (block_depth != 0) {
        o.log("Error: Function has {d} unclosed blocks", .{block_depth});
        return error.UnbalancedBlocks;
    }

    // For functions with results, ensure the correct number of values are on the stack
    if (func_type.results.len > 0) {
        if (type_stack.items.len < func_type.results.len) {
            o.log("Error: Function has insufficient return values on stack: expected {d}, got {d}", .{ func_type.results.len, type_stack.items.len });
            return error.InvalidReturnValue;
        }

        // Check result types match function signature
        const stack_pos = type_stack.items.len - func_type.results.len;
        for (func_type.results, 0..) |expected_type, i| {
            const actual_type = type_stack.items[stack_pos + i];
            if (expected_type != actual_type) {
                o.log("Error: Function return type mismatch at position {d}: expected {s}, got {s}", .{ i, @tagName(expected_type), @tagName(actual_type) });
                return error.TypeMismatch;
            }
        }
    }

    o.log("Function {d} code validation succeeded", .{func_idx});

    // Store block summaries
    const slice = try module.allocator.dupe(BlockSummary, blocks.items);
    if (func_idx < module.cfg.items.len) {
        module.cfg.items[func_idx].blocks = slice;
    } else {
        // Ensure cfg has slots up to func_idx
        while (module.cfg.items.len < func_idx) {
            try module.cfg.append(module.allocator, .{ .blocks = &[_]BlockSummary{} });
        }
        try module.cfg.append(module.allocator, .{ .blocks = slice });
    }
}
