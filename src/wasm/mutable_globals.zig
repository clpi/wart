/// Mutable Globals Import/Export
///
/// Implements the WebAssembly Mutable Globals proposal:
/// - Import mutable globals from host or other modules
/// - Export mutable globals to host or other modules
/// - Get and set operations on both imported and defined globals
/// - Validation of mutability constraints
/// - Cross-module global sharing
///
/// Reference: https://github.com/WebAssembly/mutable-global
const std = @import("std");
const Allocator = std.mem.Allocator;
const Value = @import("value.zig").Value;
const ValueType = @import("value.zig").Type;

/// Global descriptor with mutability
pub const GlobalDescriptor = struct {
    value_type: ValueType,
    mutable: bool,

    pub fn format(
        self: GlobalDescriptor,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        const mut_str = if (self.mutable) "mut" else "const";
        try writer.print("(global {s} {s})", .{ mut_str, @tagName(self.value_type) });
    }
};

/// Global instance (combines descriptor and value)
pub const Global = struct {
    descriptor: GlobalDescriptor,
    value: Value,
    imported: bool = false,
    exported: bool = false,
    export_name: ?[]const u8 = null,
    import_module: ?[]const u8 = null,
    import_name: ?[]const u8 = null,

    pub fn init(desc: GlobalDescriptor, init_value: Value) Global {
        return Global{
            .descriptor = desc,
            .value = init_value,
        };
    }

    pub fn get(self: *const Global) Value {
        return self.value;
    }

    pub fn set(self: *Global, val: Value) !void {
        if (!self.descriptor.mutable) {
            return error.ImmutableGlobal;
        }

        // Type checking
        const val_type = std.meta.activeTag(val);
        if (val_type != self.descriptor.value_type) {
            return error.TypeMismatch;
        }

        self.value = val;
    }

    pub fn format(
        self: Global,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("{} = {any}", .{ self.descriptor, self.value });
    }
};

/// Global manager for import/export
pub const GlobalManager = struct {
    const Self = @This();

    allocator: Allocator,
    globals: std.ArrayList(Global),
    import_map: std.StringHashMap(u32), // "module.name" -> global_index
    export_map: std.StringHashMap(u32), // name -> global_index

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .globals = std.ArrayList(Global).init(allocator),
            .import_map = std.StringHashMap(u32).init(allocator),
            .export_map = std.StringHashMap(u32).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        // Free import/export names
        for (self.globals.items) |*global| {
            if (global.export_name) |name| {
                self.allocator.free(name);
            }
            if (global.import_module) |module| {
                self.allocator.free(module);
            }
            if (global.import_name) |name| {
                self.allocator.free(name);
            }
        }

        self.globals.deinit();
        self.import_map.deinit();
        self.export_map.deinit();
    }

    /// Add a new global definition
    pub fn define(self: *Self, desc: GlobalDescriptor, init_value: Value) !u32 {
        const index: u32 = @intCast(self.globals.items.len);
        try self.globals.append(Global.init(desc, init_value));
        return index;
    }

    /// Import a global from another module
    pub fn import(
        self: *Self,
        module_name: []const u8,
        field_name: []const u8,
        desc: GlobalDescriptor,
        init_value: Value,
    ) !u32 {
        const index: u32 = @intCast(self.globals.items.len);

        var global = Global.init(desc, init_value);
        global.imported = true;
        global.import_module = try self.allocator.dupe(u8, module_name);
        global.import_name = try self.allocator.dupe(u8, field_name);

        try self.globals.append(global);

        // Add to import map
        const key = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ module_name, field_name });
        defer self.allocator.free(key);
        try self.import_map.put(key, index);

        return index;
    }

    /// Export a global
    pub fn @"export"(self: *Self, index: u32, name: []const u8) !void {
        if (index >= self.globals.items.len) {
            return error.InvalidGlobalIndex;
        }

        self.globals.items[index].exported = true;
        self.globals.items[index].export_name = try self.allocator.dupe(u8, name);

        try self.export_map.put(name, index);
    }

    /// Get a global value
    pub fn get(self: *Self, index: u32) !Value {
        if (index >= self.globals.items.len) {
            return error.InvalidGlobalIndex;
        }
        return self.globals.items[index].get();
    }

    /// Set a global value
    pub fn set(self: *Self, index: u32, value: Value) !void {
        if (index >= self.globals.items.len) {
            return error.InvalidGlobalIndex;
        }
        try self.globals.items[index].set(value);
    }

    /// Look up a global by export name
    pub fn getByExportName(self: *Self, name: []const u8) !u32 {
        return self.export_map.get(name) orelse error.GlobalNotFound;
    }

    /// Look up a global by import
    pub fn getByImport(self: *Self, module_name: []const u8, field_name: []const u8) !u32 {
        const key = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ module_name, field_name });
        defer self.allocator.free(key);
        return self.import_map.get(key) orelse error.GlobalNotFound;
    }

    /// Get all exported globals
    pub fn getExports(self: *Self, allocator: Allocator) ![]ExportedGlobal {
        var exports = std.ArrayList(ExportedGlobal).init(allocator);

        for (self.globals.items, 0..) |*global, i| {
            if (global.exported) {
                try exports.append(ExportedGlobal{
                    .name = global.export_name.?,
                    .index = @intCast(i),
                    .descriptor = global.descriptor,
                });
            }
        }

        return try exports.toOwnedSlice();
    }

    /// Get all imported globals
    pub fn getImports(self: *Self, allocator: Allocator) ![]ImportedGlobal {
        var imports = std.ArrayList(ImportedGlobal).init(allocator);

        for (self.globals.items, 0..) |*global, i| {
            if (global.imported) {
                try imports.append(ImportedGlobal{
                    .module_name = global.import_module.?,
                    .field_name = global.import_name.?,
                    .index = @intCast(i),
                    .descriptor = global.descriptor,
                });
            }
        }

        return try imports.toOwnedSlice();
    }

    /// Validate global access is legal
    pub fn validateAccess(self: *Self, index: u32, is_set: bool) !void {
        if (index >= self.globals.items.len) {
            return error.InvalidGlobalIndex;
        }

        const global = &self.globals.items[index];

        if (is_set and !global.descriptor.mutable) {
            return error.ImmutableGlobal;
        }
    }

    /// Link imported globals from a host environment
    pub fn linkImport(
        self: *Self,
        module_name: []const u8,
        field_name: []const u8,
        value: Value,
    ) !void {
        const index = try self.getByImport(module_name, field_name);
        const global = &self.globals.items[index];

        // Verify type matches
        const val_type = std.meta.activeTag(value);
        if (val_type != global.descriptor.value_type) {
            return error.IncompatibleImportType;
        }

        global.value = value;
    }
};

/// Exported global information
pub const ExportedGlobal = struct {
    name: []const u8,
    index: u32,
    descriptor: GlobalDescriptor,
};

/// Imported global information
pub const ImportedGlobal = struct {
    module_name: []const u8,
    field_name: []const u8,
    index: u32,
    descriptor: GlobalDescriptor,
};

/// Module instance with global sharing
pub const ModuleInstance = struct {
    const Self = @This();

    name: []const u8,
    global_mgr: GlobalManager,
    allocator: Allocator,

    pub fn init(allocator: Allocator, name: []const u8) !*Self {
        const instance = try allocator.create(Self);
        instance.* = Self{
            .name = try allocator.dupe(u8, name),
            .global_mgr = GlobalManager.init(allocator),
            .allocator = allocator,
        };
        return instance;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.name);
        self.global_mgr.deinit();
        self.allocator.destroy(self);
    }
};

/// Linker for connecting multiple modules
pub const ModuleLinker = struct {
    const Self = @This();

    allocator: Allocator,
    modules: std.StringHashMap(*ModuleInstance),

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .modules = std.StringHashMap(*ModuleInstance).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        var iter = self.modules.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.*.deinit();
        }
        self.modules.deinit();
    }

    /// Register a module instance
    pub fn registerModule(self: *Self, instance: *ModuleInstance) !void {
        try self.modules.put(instance.name, instance);
    }

    /// Link an import from one module to an export in another
    pub fn linkModules(
        self: *Self,
        importer_name: []const u8,
        import_module: []const u8,
        import_field: []const u8,
    ) !void {
        const importer = self.modules.get(importer_name) orelse return error.ModuleNotFound;
        const exporter = self.modules.get(import_module) orelse return error.ModuleNotFound;

        // Find the exported global
        const export_idx = try exporter.global_mgr.getByExportName(import_field);
        const exported_value = try exporter.global_mgr.get(export_idx);

        // Link to the importer
        try importer.global_mgr.linkImport(import_module, import_field, exported_value);
    }

    /// Get a global value across module boundaries
    pub fn getGlobal(
        self: *Self,
        module_name: []const u8,
        global_name: []const u8,
    ) !Value {
        const module = self.modules.get(module_name) orelse return error.ModuleNotFound;
        const index = try module.global_mgr.getByExportName(global_name);
        return try module.global_mgr.get(index);
    }

    /// Set a global value across module boundaries
    pub fn setGlobal(
        self: *Self,
        module_name: []const u8,
        global_name: []const u8,
        value: Value,
    ) !void {
        const module = self.modules.get(module_name) orelse return error.ModuleNotFound;
        const index = try module.global_mgr.getByExportName(global_name);
        try module.global_mgr.set(index, value);
    }
};

/// Host environment for providing imported globals
pub const HostEnvironment = struct {
    const Self = @This();

    allocator: Allocator,
    globals: std.StringHashMap(Global),

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .globals = std.StringHashMap(Global).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        var iter = self.globals.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.globals.deinit();
    }

    /// Provide a global to modules
    pub fn provideGlobal(
        self: *Self,
        name: []const u8,
        desc: GlobalDescriptor,
        init_value: Value,
    ) !void {
        const key = try self.allocator.dupe(u8, name);
        try self.globals.put(key, Global.init(desc, init_value));
    }

    /// Get a host global
    pub fn getGlobal(self: *Self, name: []const u8) !*Global {
        return self.globals.getPtr(name) orelse error.GlobalNotFound;
    }

    /// Satisfy a module's import request
    pub fn satisfyImport(
        self: *Self,
        module: *ModuleInstance,
        import_module: []const u8,
        import_field: []const u8,
    ) !void {
        const key = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ import_module, import_field });
        defer self.allocator.free(key);

        const host_global = try self.getGlobal(key);
        try module.global_mgr.linkImport(import_module, import_field, host_global.value);
    }
};
