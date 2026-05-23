const std = @import("std");
const Runtime = @import("../wasm/runtime.zig");
const Module = Runtime.Module;
const Value = Runtime.Value;
const ValueType = Runtime.ValueType;

const empty_bytes = [_]u8{};

/// Errors that can be produced by the JS façade.
pub const Error = error{
    ImportsNotSupported,
    ExportNotFound,
    ExportNotFunction,
    InvalidArgumentCount,
    TypeMismatch,
    MultipleResultsUnsupported,
    UnsupportedValueType,
};

/// Mirrors the WebAssembly JS API `Value` conversions that we support.
pub const JsValue = union(enum) {
    void: void,
    i32: i32,
    i64: i64,
    f32: f32,
    f64: f64,
    funcref: ?usize,
    externref: ?*anyopaque,
};

/// Represents a WebAssembly value type for type reflection.
pub const JsValueType = enum {
    i32,
    i64,
    f32,
    f64,
    funcref,
    externref,

    pub fn fromValueType(vt: ValueType) JsValueType {
        return switch (vt) {
            .i32 => .i32,
            .i64 => .i64,
            .f32 => .f32,
            .f64 => .f64,
            .funcref => .funcref,
            .externref => .externref,
            else => unreachable, // Should not happen for supported types
        };
    }
};

/// Represents a function signature for type reflection.
pub const JsFunctionType = struct {
    parameters: []const JsValueType,
    results: []const JsValueType,
};

/// Represents an export with type information.
pub const JsExport = struct {
    name: []const u8,
    kind: Module.Export.Type,
    index: u32,
    function_type: ?JsFunctionType = null,

    /// Free any allocated memory for this export.
    pub fn deinit(self: *JsExport, allocator: std.mem.Allocator) void {
        if (self.function_type) |*ft| {
            allocator.free(ft.parameters);
            allocator.free(ft.results);
        }
    }
};

/// Heap-owned module bytes that stay alive for the lifetime of instantiated modules.
pub const JsModule = struct {
    allocator: std.mem.Allocator,
    bytes: []u8,

    pub fn fromBytes(allocator: std.mem.Allocator, bytes: []const u8) !JsModule {
        const copy = try allocator.dupe(u8, bytes);
        return .{
            .allocator = allocator,
            .bytes = copy,
        };
    }

    pub fn deinit(self: *JsModule) void {
        const owned = self.bytes;
        self.bytes = @constCast(empty_bytes[0..]);
        self.allocator.free(owned);
    }
};

/// Runtime wrapper that offers a JS-style interface.
pub const JsRuntime = struct {
    allocator: std.mem.Allocator,
    runtime: *Runtime,

    pub fn init(allocator: std.mem.Allocator, io: std.Io) !JsRuntime {
        const rt = try Runtime.init(allocator, io);
        return .{
            .allocator = allocator,
            .runtime = rt,
        };
    }

    pub fn deinit(self: *JsRuntime) void {
        self.runtime.deinit();
        self.allocator.destroy(self.runtime);
    }

    /// Configure runtime options exposed through the CLI.
    pub fn setConfig(self: *JsRuntime, debug: bool, validate: bool) void {
        self.runtime.debug = debug;
        self.runtime.validate = validate;
    }

    /// Instantiate a module and return a JS-style instance wrapper.
    pub fn instantiate(self: *JsRuntime, module: *JsModule) !JsInstance {
        if (module.bytes.len == 0) return Error.UnsupportedValueType;

        // Runtime currently supports a single resident module; make sure we release any previous one.
        if (self.runtime.module) |existing| {
            existing.deinit();
            self.runtime.module = null;
        }

        const mod = try self.runtime.loadModule(module.bytes);
        if (mod.imports.items.len != 0) {
            mod.deinit();
            self.runtime.module = null;
            return Error.ImportsNotSupported;
        }

        return JsInstance{
            .allocator = self.allocator,
            .runtime = self.runtime,
            .module = mod,
        };
    }
};

/// Wrapper around a loaded module that provides convenience accessors.
pub const JsInstance = struct {
    allocator: std.mem.Allocator,
    runtime: *Runtime,
    module: *Module,

    pub fn deinit(self: *JsInstance) void {
        if (self.runtime.module) |mod| {
            if (mod == self.module) {
                self.runtime.module = null;
            }
        }
        self.module.deinit();
        self.* = JsInstance{
            .allocator = self.allocator,
            .runtime = self.runtime,
            .module = undefined,
        };
    }

    /// Get all exports with basic information (legacy method).
    pub fn exports(self: *JsInstance) []const Module.Export {
        return self.module.exports.items;
    }

    /// Get all exports with type information for reflection.
    /// The returned slice must be freed with deinitExportsWithTypes.
    pub fn exportsWithTypes(self: *JsInstance, allocator: std.mem.Allocator) ![]JsExport {
        const module_exports = self.module.exports.items;
        const result = try allocator.alloc(JsExport, module_exports.len);

        for (module_exports, 0..) |exp, i| {
            result[i] = JsExport{
                .name = exp.name,
                .kind = exp.kind,
                .index = exp.index,
            };

            // Add function type information if this is a function export
            if (exp.kind == .function) {
                const func = self.module.functions.items[exp.index];
                const sig = self.module.types.items[func.type_index];

                // Convert parameter types
                const params = try allocator.alloc(JsValueType, sig.params.len);
                for (sig.params, 0..) |param_type, j| {
                    params[j] = JsValueType.fromValueType(param_type);
                }

                // Convert result types
                const results = try allocator.alloc(JsValueType, sig.results.len);
                for (sig.results, 0..) |result_type, j| {
                    results[j] = JsValueType.fromValueType(result_type);
                }

                result[i].function_type = JsFunctionType{
                    .parameters = params,
                    .results = results,
                };
            }
        }

        return result;
    }

    /// Free memory allocated by exportsWithTypes.
    pub fn deinitExportsWithTypes(self: *JsInstance, allocator: std.mem.Allocator, js_exports: []JsExport) void {
        _ = self; // unused
        for (js_exports) |*exp| {
            exp.deinit(allocator);
        }
        allocator.free(js_exports);
    }

    /// Get the function type for a specific exported function.
    /// The returned JsFunctionType must be freed with deinitFunctionType.
    pub fn getFunctionType(self: *JsInstance, name: []const u8, allocator: std.mem.Allocator) !JsFunctionType {
        const export_entry = try self.findFunction(name);
        const func = self.module.functions.items[export_entry.index];
        const sig = self.module.types.items[func.type_index];

        // Convert parameter types
        const params = try allocator.alloc(JsValueType, sig.params.len);
        for (sig.params, 0..) |param_type, i| {
            params[i] = JsValueType.fromValueType(param_type);
        }

        // Convert result types
        const results = try allocator.alloc(JsValueType, sig.results.len);
        for (sig.results, 0..) |result_type, i| {
            results[i] = JsValueType.fromValueType(result_type);
        }

        return JsFunctionType{
            .parameters = params,
            .results = results,
        };
    }

    /// Free memory allocated by getFunctionType.
    pub fn deinitFunctionType(self: *JsInstance, allocator: std.mem.Allocator, func_type: JsFunctionType) void {
        _ = self; // unused
        allocator.free(func_type.parameters);
        allocator.free(func_type.results);
    }

    pub fn invoke(self: *JsInstance, name: []const u8, args: []const JsValue) !JsValue {
        const export_entry = try self.findFunction(name);
        const func_index = export_entry.index;
        const func = self.module.functions.items[func_index];
        const sig = self.module.types.items[func.type_index];

        if (sig.params.len != args.len) return Error.InvalidArgumentCount;
        if (sig.results.len > 1) return Error.MultipleResultsUnsupported;

        var tmp_args = try self.runtime.allocator.alloc(Value, sig.params.len);
        defer self.runtime.allocator.free(tmp_args);

        for (sig.params, args, 0..) |param_type, arg, idx| {
            tmp_args[idx] = try convertArg(param_type, arg);
        }

        const result = try self.runtime.executeFunction(func_index, tmp_args);
        if (sig.results.len == 0) {
            return JsValue{ .void = {} };
        }

        return try convertResult(sig.results[0], result);
    }

    fn findFunction(self: *JsInstance, name: []const u8) !Module.Export {
        for (self.module.exports.items) |exp| {
            if (std.mem.eql(u8, exp.name, name)) {
                if (exp.kind != .function) return Error.ExportNotFunction;
                return exp;
            }
        }
        return Error.ExportNotFound;
    }
};

fn convertArg(expected: ValueType, value: JsValue) Error!Value {
    return switch (expected) {
        .i32 => switch (value) {
            .i32 => |v| Value{ .i32 = v },
            else => Error.TypeMismatch,
        },
        .i64 => switch (value) {
            .i64 => |v| Value{ .i64 = v },
            else => Error.TypeMismatch,
        },
        .f32 => switch (value) {
            .f32 => |v| Value{ .f32 = v },
            else => Error.TypeMismatch,
        },
        .f64 => switch (value) {
            .f64 => |v| Value{ .f64 = v },
            else => Error.TypeMismatch,
        },
        .funcref => switch (value) {
            .funcref => |v| Value{ .funcref = v },
            else => Error.TypeMismatch,
        },
        .externref => switch (value) {
            .externref => |v| Value{ .externref = v },
            else => Error.TypeMismatch,
        },
        else => Error.UnsupportedValueType,
    };
}

fn convertResult(expected: ValueType, value: Value) Error!JsValue {
    return switch (expected) {
        .i32 => switch (@as(ValueType, std.meta.activeTag(value))) {
            .i32 => JsValue{ .i32 = value.i32 },
            else => Error.TypeMismatch,
        },
        .i64 => switch (@as(ValueType, std.meta.activeTag(value))) {
            .i64 => JsValue{ .i64 = value.i64 },
            else => Error.TypeMismatch,
        },
        .f32 => switch (@as(ValueType, std.meta.activeTag(value))) {
            .f32 => JsValue{ .f32 = value.f32 },
            else => Error.TypeMismatch,
        },
        .f64 => switch (@as(ValueType, std.meta.activeTag(value))) {
            .f64 => JsValue{ .f64 = value.f64 },
            else => Error.TypeMismatch,
        },
        .funcref => switch (@as(ValueType, std.meta.activeTag(value))) {
            .funcref => JsValue{ .funcref = value.funcref },
            else => Error.TypeMismatch,
        },
        .externref => switch (@as(ValueType, std.meta.activeTag(value))) {
            .externref => JsValue{ .externref = value.externref },
            else => Error.TypeMismatch,
        },
        else => Error.UnsupportedValueType,
    };
}

test "JsModule copies input bytes" {
    const allocator = std.testing.allocator;
    const sample = [_]u8{ 0x00, 0x61, 0x73, 0x6D };
    var module = try JsModule.fromBytes(allocator, &sample);
    defer module.deinit();

    try std.testing.expectEqual(@as(usize, sample.len), module.bytes.len);
    module.bytes[0] = 0xFF;
    try std.testing.expect(sample[0] == 0x00);
}

test "type reflection works" {
    const allocator = std.testing.allocator;

    // Create a simple WASM module with a function export
    const wasm_bytes = [_]u8{
        // WASM magic and version
        0x00, 0x61, 0x73, 0x6D, 0x01, 0x00, 0x00, 0x00,
        // Type section
        0x01, 0x07, 0x01, 0x60, 0x02, 0x7F, 0x7F, 0x01,
        0x7F,
        // Function section
        0x03, 0x02, 0x01, 0x00,
        // Export section
        0x07, 0x0A, 0x01,
        0x04, 0x61, 0x64, 0x64, 0x00, 0x00,
        // Code section
        0x0A, 0x09,
        0x01, 0x07, 0x00, 0x20, 0x00, 0x20, 0x01, 0x6A,
        0x0B,
    };

    var js_module = try JsModule.fromBytes(allocator, &wasm_bytes);
    defer js_module.deinit();

    var io_provider = std.Io.Threaded.init(allocator, .{});
    defer io_provider.deinit();

    var runtime = try JsRuntime.init(allocator, io_provider.io());
    defer runtime.deinit();

    var instance = try runtime.instantiate(&js_module);
    defer instance.deinit();

    // Test exportsWithTypes
    const exports = try instance.exportsWithTypes(allocator);
    defer instance.deinitExportsWithTypes(allocator, exports);

    try std.testing.expectEqual(@as(usize, 1), exports.len);
    try std.testing.expectEqualStrings("add", exports[0].name);
    try std.testing.expect(exports[0].kind == .function);
    try std.testing.expect(exports[0].function_type != null);

    const func_type = exports[0].function_type.?;
    try std.testing.expectEqual(@as(usize, 2), func_type.parameters.len);
    try std.testing.expectEqual(@as(usize, 1), func_type.results.len);
    try std.testing.expectEqual(JsValueType.i32, func_type.parameters[0]);
    try std.testing.expectEqual(JsValueType.i32, func_type.parameters[1]);
    try std.testing.expectEqual(JsValueType.i32, func_type.results[0]);

    // Test getFunctionType
    const direct_func_type = try instance.getFunctionType("add", allocator);
    defer instance.deinitFunctionType(allocator, direct_func_type);

    try std.testing.expectEqual(@as(usize, 2), direct_func_type.parameters.len);
    try std.testing.expectEqual(@as(usize, 1), direct_func_type.results.len);
}

test "deinitFunctionType properly frees memory" {
    const allocator = std.testing.allocator;

    var js_module = try JsModule.fromBytes(allocator, &[_]u8{
        0x00, 0x61, 0x73, 0x6D, 0x01, 0x00, 0x00, 0x00,
        0x01, 0x07, 0x01, 0x60, 0x02, 0x7F, 0x7F, 0x01, 0x7F,
        0x03, 0x02, 0x01, 0x00,
        0x07, 0x0A, 0x01, 0x04, 0x61, 0x64, 0x64, 0x00, 0x00,
        0x0A, 0x09, 0x01, 0x07, 0x00, 0x20, 0x00, 0x20, 0x01, 0x6A, 0x0B,
    });
    defer js_module.deinit();

    var io_provider = std.Io.Threaded.init(allocator, .{});
    defer io_provider.deinit();

    var runtime = try JsRuntime.init(allocator, io_provider.io());
    defer runtime.deinit();

    var instance = try runtime.instantiate(&js_module);
    defer instance.deinit();

    const func_type = try instance.getFunctionType("add", allocator);

    // Call deinitFunctionType which frees the memory
    instance.deinitFunctionType(allocator, func_type);

    // Testing allocator will ensure no leaks occurred and no double-frees
}
