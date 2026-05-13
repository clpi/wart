const std = @import("std");
const builtin = @import("builtin");
const cwd = std.Io.Dir.cwd;
const Color = @import("../util/fmt/color.zig");
const print = @import("../util/fmt.zig").print;
const ModuleExportType = @import("../wasm/module/export.zig").Type;
const Runtime = @import("../wasm/runtime.zig");
const Config = @import("../config.zig").Config;

pub const RunOptions = struct {
    wasm_file: [:0]u8,
    args: []const [:0]u8,
    config: Config,
};

pub const InspectOptions = struct {
    wasm_file: [:0]u8,
    config: Config,
};

fn kindLabel(kind: ModuleExportType) []const u8 {
    return switch (kind) {
        .function => "function",
        .table => "table",
        .memory => "memory",
        .global => "global",
    };
}

fn isNativeExecutable(io: std.Io, path: []const u8) !bool {
    const file = cwd().openFile(io, path, .{}) catch return false;
    defer file.close(io);

    const stat = file.stat(io) catch return false;
    const is_executable = blk: {
        if (@hasDecl(std.Io.File.Stat, "mode")) {
            const mode = stat.mode;
            break :blk (mode & 0o111) != 0;
        } else {
            break :blk true;
        }
    };
    if (!is_executable) return false;

    var magic: [4]u8 = undefined;
    var buf: [256]u8 = undefined;
    var reader = file.reader(io, &buf);
    var slices = [_][]u8{&magic};
    const bytes_read = reader.interface.readVec(&slices) catch return false;
    if (bytes_read < 4) return false;

    if (builtin.os.tag == .linux or builtin.os.tag == .macos) {
        if (magic[0] == 0x7f and magic[1] == 'E' and magic[2] == 'L' and magic[3] == 'F') return true;
    }
    if (builtin.os.tag == .macos) {
        if (magic[0] == 0xcf and magic[1] == 0xfa and magic[2] == 0xed and magic[3] == 0xfe) return true;
        if (magic[0] == 0xca and magic[1] == 0xfe and magic[2] == 0xba and magic[3] == 0xbe) return true;
        if (magic[0] == 0xbe and magic[1] == 0xba and magic[2] == 0xfe and magic[3] == 0xca) return true;
    }
    if (builtin.os.tag == .windows) {
        if (magic[0] == 'M' and magic[1] == 'Z') return true;
    }
    return false;
}

fn executeNativeBinary(allocator: std.mem.Allocator, io: std.Io, opts: RunOptions) !void {
    _ = allocator;
    _ = io;
    _ = opts;
    return error.NativeExecutionNotSupported;
}

fn isComponent(bytes: []const u8) bool {
    const component_magic = [_]u8{ 0x00, 0x61, 0x73, 0x6d, 0x0d, 0x00, 0x01, 0x00 };
    return bytes.len >= 8 and std.mem.eql(u8, bytes[0..8], &component_magic);
}

fn isValidWasm(bytes: []const u8) bool {
    const wasm_magic = [_]u8{ 0x00, 0x61, 0x73, 0x6d };
    const wasm_version = [_]u8{ 0x01, 0x00, 0x00, 0x00 };
    return bytes.len >= 8 and
        std.mem.eql(u8, bytes[0..4], &wasm_magic) and
        std.mem.eql(u8, bytes[4..8], &wasm_version);
}

pub fn executeRun(allocator: std.mem.Allocator, io: std.Io, opts: RunOptions) !void {
    const Value = Runtime.Value;
    const ComponentParser = @import("../wasm/component.zig").ComponentParser;
    const ComponentInstance = @import("../wasm/component.zig").ComponentInstance;
    const ComponentValue = @import("../wasm/component.zig").ComponentValue;
    const WatParser = @import("../wasm/wat.zig");
    const CCompiler = @import("../wasm/c_compiler.zig");

    if (try isNativeExecutable(io, opts.wasm_file)) {
        if (opts.config.verbose >= 1) {
            print("Detected native executable", .{}, if (opts.config.color) Color.cyan else Color.reset);
            print("Executing: {s}", .{opts.wasm_file}, if (opts.config.color) Color.white else Color.reset);
        }
        return executeNativeBinary(allocator, io, opts);
    }

    const file_bytes = cwd().readFileAlloc(io, opts.wasm_file, allocator, .limited(1024 * 1024 * 10)) catch |err| {
        switch (err) {
            error.FileNotFound => {
                print("Error: File '{s}' not found", .{opts.wasm_file}, Color.red);
                return;
            },
            error.AccessDenied => {
                print("Error: Permission denied reading '{s}'", .{opts.wasm_file}, Color.red);
                return;
            },
            else => return err,
        }
    };
    defer allocator.free(file_bytes);

    const wasm_bytes = blk: {
        const is_cpp_file = std.mem.endsWith(u8, opts.wasm_file, ".cpp") or std.mem.endsWith(u8, opts.wasm_file, ".cc") or std.mem.endsWith(u8, opts.wasm_file, ".cxx") or (opts.config.cppfile_path != null);
        const is_c_file = std.mem.endsWith(u8, opts.wasm_file, ".c") or (opts.config.cfile_path != null);
        const is_wat_file = std.mem.endsWith(u8, opts.wasm_file, ".wat") or opts.config.wast;
        const is_wasm_magic = file_bytes.len >= 4 and std.mem.eql(u8, file_bytes[0..4], "\x00asm");

        if (is_cpp_file and !is_wasm_magic) {
            if (opts.config.verbose >= 1) {
                print("Compiling C++ to WASM", .{}, if (opts.config.color) Color.cyan else Color.reset);
            }
            break :blk try CCompiler.compileCppToWasm(allocator, io, file_bytes);
        } else if (is_c_file and !is_wasm_magic) {
            if (opts.config.verbose >= 1) {
                print("Compiling C to WASM", .{}, if (opts.config.color) Color.cyan else Color.reset);
            }
            break :blk try CCompiler.compileCToWasm(allocator, io, file_bytes);
        } else if (is_wat_file and !is_wasm_magic) {
            if (opts.config.verbose >= 1) {
                print("Converting WAT to WASM", .{}, if (opts.config.color) Color.cyan else Color.reset);
            }
            break :blk try WatParser.convertWatToWasm(allocator, io, file_bytes);
        } else {
            break :blk try allocator.dupe(u8, file_bytes);
        }
    };
    defer allocator.free(wasm_bytes);

    if (opts.config.verbose >= 1) {
        print("Execution configuration:", .{}, if (opts.config.color) Color.yellow else Color.reset);
        print("   File: {s} ({d} bytes)", .{ opts.wasm_file, wasm_bytes.len }, if (opts.config.color) Color.white else Color.reset);
        print("   Args: {any}", .{opts.args}, if (opts.config.color) Color.white else Color.reset);
        print("   Debug: {}", .{opts.config.debug}, if (opts.config.color) Color.white else Color.reset);
        print("   Validate: {}", .{opts.config.validate}, if (opts.config.color) Color.white else Color.reset);
        print("   JIT: {}", .{opts.config.jit}, if (opts.config.color) Color.white else Color.reset);
        print("   AOT: {}", .{opts.config.aot}, if (opts.config.color) Color.white else Color.reset);
        if (opts.config.function) |func| {
            print("   Function: {s}", .{func}, if (opts.config.color) Color.white else Color.reset);
        } else {
            print("   Function: _start (default)", .{}, if (opts.config.color) Color.white else Color.reset);
        }
    }

    var runtime = try Runtime.init(allocator, io);
    defer runtime.deinit();

    runtime.debug = opts.config.debug;
    runtime.validate = opts.config.validate;
    runtime.jit_enabled = opts.config.jit;

    if (opts.config.verbose >= 1) {
        print("Runtime initialization:", .{}, if (opts.config.color) Color.yellow else Color.reset);
        print("   Debug mode: {}", .{runtime.debug}, if (opts.config.color) Color.white else Color.reset);
        print("   Validation: {}", .{runtime.validate}, if (opts.config.color) Color.white else Color.reset);
        print("   JIT enabled: {}", .{runtime.jit_enabled}, if (opts.config.color) Color.white else Color.reset);
    }

    if (runtime.jit_enabled) {
        if (opts.config.verbose >= 2) std.debug.print("Initializing JIT...", .{});
        const jitCallback = struct {
            fn callback(ctx: *anyopaque, func_index: u32, args: []Value) Value {
                _ = ctx;
                _ = func_index;
                _ = args;
                return Value{ .i32 = 0 };
            }
        }.callback;
        runtime.jit = Runtime.JIT.init(allocator, jitCallback) catch |err| blk: {
            if (opts.config.verbose >= 1) std.debug.print("JIT initialization failed: {s}", .{@errorName(err)});
            break :blk null;
        };
        if (runtime.jit) |_| {
            if (opts.config.verbose >= 2) std.debug.print("JIT initialized successfully", .{});
        }
    }

    if (isComponent(wasm_bytes)) {
        if (opts.config.verbose >= 1) {
            print("Detected WebAssembly Component", .{}, if (opts.config.color) Color.cyan else Color.reset);
        }

        if (wasm_bytes.len >= 8 and wasm_bytes[4] == 0x0d and wasm_bytes[5] == 0x00 and wasm_bytes[6] == 0x01) {
            if (opts.config.verbose >= 1) {
                print("Executing Component Model Layer 1 with WASI Preview 2", .{}, if (opts.config.color) Color.cyan else Color.reset);
            }

            const ComponentLayer1 = @import("../wasm/component_parser_layer1.zig");
            var parser = ComponentLayer1.ComponentLayer1Parser.init(allocator, io, wasm_bytes);
            defer parser.deinit();
            try parser.parse();

            if (opts.config.verbose >= 1) {
                print("Component parsed: {d} modules, {d} imports, {d} exports", .{
                    parser.core_modules.items.len,
                    parser.imports.items.len,
                    parser.exports.items.len,
                }, if (opts.config.color) Color.green else Color.reset);
            }

            var instance = try ComponentLayer1.ComponentLayer1Instance.init(allocator, io, runtime);
            defer instance.deinit();

            var wasi_args = try std.ArrayList([:0]u8).initCapacity(allocator, opts.args.len + 1);
            defer wasi_args.deinit(allocator);

            var basename_buf: [256]u8 = undefined;
            const full_basename = if (std.mem.lastIndexOfScalar(u8, opts.wasm_file, '/')) |idx|
                opts.wasm_file[idx + 1 ..]
            else
                opts.wasm_file;

            const basename_slice = if (std.mem.endsWith(u8, full_basename, ".wasm"))
                full_basename[0 .. full_basename.len - 5]
            else
                full_basename;

            @memcpy(basename_buf[0..basename_slice.len], basename_slice);
            basename_buf[basename_slice.len] = 0;
            const basename_z: [:0]u8 = basename_buf[0..basename_slice.len :0];

            try wasi_args.append(allocator, @constCast(basename_z));
            for (opts.args) |arg| {
                try wasi_args.append(allocator, @constCast(arg));
            }

            try runtime.setupWASI(wasi_args.items);

            instance.instantiate(&parser) catch |err| {
                if (opts.config.verbose >= 1) {
                    print("Component instantiation encountered: {s}, using fallback execution", .{@errorName(err)}, Color.yellow);
                }
            };

            if (opts.config.verbose >= 1) {
                print("Executing component with WASI Preview 2...", .{}, if (opts.config.color) Color.green else Color.reset);
            }

            _ = instance.callExport("", &[_]Value{}) catch |err| {
                if (opts.config.verbose >= 1) {
                    print("Component execution completed with status: {s}", .{@errorName(err)}, Color.yellow);
                }
            };

            return;
        } else {
            var parser = ComponentParser.init(allocator, io, wasm_bytes);
            var component = try parser.parseComponent(allocator);
            defer component.deinit();

            if (opts.config.validate) {
                try component.validate();
                if (opts.config.verbose >= 1) {
                    print("Component validation successful", .{}, if (opts.config.color) Color.green else Color.reset);
                }
            }

            var instance = try ComponentInstance.init(allocator, io, &component);
            defer instance.deinit();

            var imports = std.StringHashMap(ComponentValue).init(allocator);
            defer imports.deinit();
            try instance.instantiate(imports);

            if (opts.config.verbose >= 1) {
                print("Component instantiated successfully", .{}, if (opts.config.color) Color.green else Color.reset);
            }

            if (component.start) |_| {
                try instance.callStart();
            }

            return;
        }
    }

    var module_load_err: ?anyerror = null;
    var module: *Runtime.Module = undefined;
    if (runtime.validate) {
        module = runtime.loadModule(wasm_bytes) catch |e| blk: {
            module_load_err = e;
            runtime.validate = false;
            const m2 = runtime.loadModule(wasm_bytes) catch |e2| {
                runtime.validate = opts.config.validate;
                return e2;
            };
            break :blk m2;
        };
        if (module_load_err) |_| {}
    } else {
        module = try runtime.loadModule(wasm_bytes);
    }

    if (opts.config.aot) {
        const AOT = @import("../wasm/aot.zig").AOT;
        var aot_compiler = try AOT.init(allocator, io, module);
        defer aot_compiler.deinit();

        if (opts.config.verbose >= 1) {
            print("Starting AOT compilation...", .{}, if (opts.config.color) Color.cyan else Color.reset);
        }

        const compiled = try aot_compiler.compileModule();
        defer allocator.free(compiled.native_code);
        defer allocator.free(compiled.function_table);

        if (opts.config.verbose >= 1) {
            print("AOT compilation complete. Generated {d} bytes of native code", .{compiled.native_code.len}, if (opts.config.color) Color.green else Color.reset);
        }

        if (opts.config.aot_output) |output_path| {
            try aot_compiler.saveExecutable(compiled, output_path);
            print("Native executable saved to: {s}", .{output_path}, Color.green);
        } else {
            print("AOT compilation successful. Use -o to save native executable.", .{}, Color.green);
        }
        return;
    }

    var wasi_args = try std.ArrayList([:0]u8).initCapacity(allocator, opts.args.len + 1);
    defer wasi_args.deinit(allocator);

    const basename_with_ext = if (std.mem.lastIndexOfScalar(u8, opts.wasm_file, '/')) |idx|
        opts.wasm_file[idx + 1 ..]
    else
        opts.wasm_file;

    const basename_slice = if (std.mem.endsWith(u8, basename_with_ext, ".wasm"))
        basename_with_ext[0 .. basename_with_ext.len - 5]
    else
        basename_with_ext;

    var basename_buf: [256]u8 = undefined;
    @memcpy(basename_buf[0..basename_slice.len], basename_slice);
    basename_buf[basename_slice.len] = 0;
    const basename: [:0]u8 = basename_buf[0..basename_slice.len :0];

    try wasi_args.append(allocator, @constCast(basename));
    for (opts.args) |arg| {
        try wasi_args.append(allocator, @constCast(arg));
    }

    try runtime.setupWASI(wasi_args.items);

    const dump_stdio = @import("../util/env.zig").hasEnvVarConstant("WX_DUMP_STDIO");
    const dump_table = @import("../util/env.zig").hasEnvVarConstant("WX_DUMP_TABLE");
    if (dump_table) {
        if (module.table) |table| {
            std.debug.print("[wart debug] table size {d}\n", .{table.items.len});
            const limit = @min(table.items.len, 8);
            for (table.items[0..limit], 0..) |entry, idx| {
                std.debug.print("[wart debug] table[{d}] = {any}\n", .{ idx, entry });
            }
        } else {
            std.debug.print("[wart debug] no table present\n", .{});
        }
    }
    if (dump_stdio) {
        if (module.memory) |mem| {
            const dump_off: usize = 3408;
            const dump_len: usize = 128;
            if (dump_off + dump_len <= mem.len) {
                const slice = mem[dump_off .. dump_off + dump_len];
                std.debug.print("[wart debug] pre-run memory[{d}..{d}] = {any}\n", .{
                    dump_off,
                    dump_off + dump_len,
                    slice,
                });
                if (3656 <= mem.len) {
                    const errno_slice = mem[3652..3656];
                    std.debug.print("[wart debug] pre-run errno bytes = {any}\n", .{errno_slice});
                }
            } else {
                std.debug.print("[wart debug] memory length {d} too small for dump at {d}\n", .{ mem.len, dump_off });
            }
        }
    }

    if (runtime.findExportedFunction("__wasm_call_ctors")) |ctors_func| {
        _ = runtime.executeFunction(ctors_func, &[_]Value{}) catch |e| {
            std.debug.print("wart error: __wasm_call_ctors failed: {s}\n", .{@errorName(e)});
            return e;
        };
    }

    if (module.start_function_index) |start_idx| {
        if (opts.config.verbose >= 2) {
            print("Executing start function (index: {d})...", .{start_idx}, if (opts.config.color) Color.cyan else Color.reset);
        }
        _ = runtime.executeFunction(start_idx, &[_]Value{}) catch |e| {
            std.debug.print("wart error: start function (index {d}) failed: {s}\n", .{ start_idx, @errorName(e) });
            return e;
        };
    }

    const function_name = opts.config.function orelse "_start";
    const target_func = runtime.findExportedFunction(function_name) orelse {
        print("Function '{s}' not found", .{function_name}, if (opts.config.color) Color.red else Color.reset);
        if (opts.config.verbose >= 1) {
            print("Available exported functions:", .{}, if (opts.config.color) Color.yellow else Color.reset);
            for (module.exports.items) |export_item| {
                if (export_item.kind == .function) {
                    print("   - {s}", .{export_item.name}, if (opts.config.color) Color.white else Color.reset);
                }
            }
        }
        return;
    };

    if (opts.config.verbose >= 1) {
        print("Function execution:", .{}, if (opts.config.color) Color.yellow else Color.reset);
        print("   Function: {s} (index: {d})", .{ function_name, target_func }, if (opts.config.color) Color.white else Color.reset);
        print("   Type index: {d}", .{module.functions.items[target_func].type_index}, if (opts.config.color) Color.white else Color.reset);
        const func_type = module.types.items[module.functions.items[target_func].type_index];
        print("   Parameters: {d}", .{func_type.params.len}, if (opts.config.color) Color.white else Color.reset);
        print("   Returns: {d}", .{func_type.results.len}, if (opts.config.color) Color.white else Color.reset);
        print("Running function", .{}, if (opts.config.color) Color.cyan else Color.reset);
    }

    runtime.validate = opts.config.validate;
    const exec = runtime.executeFunction(target_func, &[_]Value{});
    if (exec) |_| {} else |e| {
        std.debug.print("wart error: {s} at opcode 0x{X:0>2} pos {d}", .{ @errorName(e), runtime.last_opcode, runtime.last_pos });
        return e;
    }

    if (runtime.wasi != null) {
        if (runtime.findExportedFunction("__stdio_exit")) |flush_idx| {
            _ = runtime.executeFunction(flush_idx, &[_]Value{}) catch {};
        }
    }

    if (dump_stdio) {
        if (module.memory) |mem| {
            const dump_off: usize = 3408;
            const dump_len: usize = 128;
            if (dump_off + dump_len <= mem.len) {
                const slice = mem[dump_off .. dump_off + dump_len];
                std.debug.print("[wart debug] post-run memory[{d}..{d}] = {any}\n", .{
                    dump_off,
                    dump_off + dump_len,
                    slice,
                });
                if (3656 <= mem.len) {
                    const errno_slice = mem[3652..3656];
                    std.debug.print("[wart debug] post-run errno bytes = {any}\n", .{errno_slice});
                }
            }
        }
    }
}

pub fn executeInspect(allocator: std.mem.Allocator, io: std.Io, opts: InspectOptions) !void {
    const wasm_path = opts.wasm_file;

    const wasm_bytes = cwd().readFileAlloc(io, opts.wasm_file, allocator, .limited(1024 * 1024 * 10)) catch |err| {
        switch (err) {
            error.FileNotFound => {
                print("{s}Error:{s} WASM file '{s}' not found", .{ Color.bright_red ++ Color.bold, Color.reset, wasm_path }, Color.red);
                return;
            },
            error.AccessDenied => {
                print("{s}Error:{s} Permission denied reading '{s}'", .{ Color.bright_red ++ Color.bold, Color.reset, wasm_path }, Color.red);
                return;
            },
            error.FileTooBig => {
                print("{s}Error:{s} WASM file '{s}' is too large (max 10MB)", .{ Color.bright_red ++ Color.bold, Color.reset, wasm_path }, Color.red);
                return;
            },
            else => {
                print("{s}Error:{s} Failed to read file '{s}': {s}", .{ Color.bright_red ++ Color.bold, Color.reset, wasm_path, @errorName(err) }, Color.red);
                return err;
            },
        }
    };
    defer allocator.free(wasm_bytes);

    if (!isValidWasm(wasm_bytes)) {
        print("{s}Error:{s} '{s}' is not a valid WASM file", .{ Color.bright_red ++ Color.bold, Color.reset, wasm_path }, Color.red);
        print("{s}   Expected magic bytes \\x00asm with valid version", .{Color.dim}, Color.reset);
        return;
    }

    print("", .{}, Color.reset);
    print("{s}Inspecting: {s}{s}{s}", .{ Color.bright_cyan ++ Color.bold, Color.bright_white, wasm_path, Color.reset }, Color.reset);
    print("{s}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━{s}", .{ Color.dim, Color.reset }, Color.reset);
    print("", .{}, Color.reset);

    if (isComponent(wasm_bytes)) {
        const component_mod = @import("../wasm/component.zig");
        var parser = component_mod.ComponentParser.init(allocator, io, wasm_bytes);
        var component = try parser.parseComponent(allocator);
        defer component.deinit();

        if (opts.config.validate) {
            try component.validate();
        }

        print("{s}Component Model Module{s}", .{ Color.bright_magenta ++ Color.bold, Color.reset }, Color.reset);
        print("", .{}, Color.reset);
        print("{s}Summary:{s}", .{ Color.bright_yellow, Color.reset }, Color.reset);
        print("  {s}•{s} Interface types : {s}{d}{s}", .{ Color.bright_blue, Color.reset, Color.bright_green, component.types.items.len, Color.reset }, Color.reset);
        print("  {s}•{s} Functions       : {s}{d}{s}", .{ Color.bright_blue, Color.reset, Color.bright_green, component.functions.items.len, Color.reset }, Color.reset);
        print("  {s}•{s} Imports         : {s}{d}{s}", .{ Color.bright_blue, Color.reset, Color.bright_green, component.imports.items.len, Color.reset }, Color.reset);
        print("  {s}•{s} Exports         : {s}{d}{s}", .{ Color.bright_blue, Color.reset, Color.bright_green, component.exports.items.len, Color.reset }, Color.reset);
        print("  {s}•{s} Core modules    : {s}{d}{s}", .{ Color.bright_blue, Color.reset, Color.bright_green, component.core_modules.items.len, Color.reset }, Color.reset);
        if (component.start) |start_idx| {
            print("  {s}•{s} Start function  : {s}#{d}{s}", .{ Color.bright_blue, Color.reset, Color.bright_yellow, start_idx, Color.reset }, Color.reset);
        }
        print("", .{}, Color.reset);

        const max_preview: usize = 6;
        if (component.imports.items.len == 0) {
            print("{s}Imports:{s} {s}none{s}", .{ Color.bright_yellow, Color.reset, Color.dim, Color.reset }, Color.reset);
        } else {
            print("{s}Imports:{s}", .{ Color.bright_yellow, Color.reset }, Color.reset);
            const preview = @min(component.imports.items.len, max_preview);
            for (component.imports.items[0..preview]) |imp| {
                print("  {s}→{s} {s}{s}{s}", .{ Color.bright_cyan, Color.reset, Color.white, imp.name, Color.reset }, Color.reset);
            }
            if (component.imports.items.len > max_preview) {
                print("  {s}... ({d} more){s}", .{ Color.dim, component.imports.items.len - max_preview, Color.reset }, Color.reset);
            }
        }
        print("", .{}, Color.reset);

        if (component.exports.items.len == 0) {
            print("{s}Exports:{s} {s}none{s}", .{ Color.bright_yellow, Color.reset, Color.dim, Color.reset }, Color.reset);
        } else {
            print("{s}Exports:{s}", .{ Color.bright_yellow, Color.reset }, Color.reset);
            const preview = @min(component.exports.items.len, max_preview);
            for (component.exports.items[0..preview]) |exp| {
                print("  {s}→{s} {s}{s}{s}", .{ Color.bright_green, Color.reset, Color.white, exp.name, Color.reset }, Color.reset);
            }
            if (component.exports.items.len > max_preview) {
                print("  {s}... ({d} more){s}", .{ Color.dim, component.exports.items.len - max_preview, Color.reset }, Color.reset);
            }
        }
        print("", .{}, Color.reset);

        return;
    }

    var runtime = try Runtime.init(allocator, io);
    defer runtime.deinit();

    runtime.validate = opts.config.validate;
    runtime.debug = opts.config.debug;
    runtime.jit_enabled = opts.config.jit;

    const module = runtime.loadModule(wasm_bytes) catch |err| {
        print("{s}Failed to load module:{s} {s}", .{ Color.bright_red ++ Color.bold, Color.reset, @errorName(err) }, Color.red);
        return err;
    };

    var imported_funcs: usize = 0;
    for (module.functions.items) |func| {
        if (func.imported) imported_funcs += 1;
    }
    const total_functions = module.functions.items.len;

    var import_fn: usize = 0;
    var import_tables: usize = 0;
    var import_memory: usize = 0;
    var import_globals: usize = 0;
    for (module.imports.items) |import| {
        switch (import.kind) {
            .function => import_fn += 1,
            .table => import_tables += 1,
            .memory => import_memory += 1,
            .global => import_globals += 1,
        }
    }

    var export_fn: usize = 0;
    var export_tables: usize = 0;
    var export_memory: usize = 0;
    var export_globals: usize = 0;
    for (module.exports.items) |exp| {
        switch (exp.kind) {
            .function => export_fn += 1,
            .table => export_tables += 1,
            .memory => export_memory += 1,
            .global => export_globals += 1,
        }
    }

    print("{s}WebAssembly Module{s}", .{ Color.bright_magenta ++ Color.bold, Color.reset }, Color.reset);
    print("", .{}, Color.reset);
    print("{s}Summary:{s}", .{ Color.bright_yellow, Color.reset }, Color.reset);
    print("  {s}•{s} Types           : {s}{d}{s}", .{ Color.bright_blue, Color.reset, Color.bright_green, module.types.items.len, Color.reset }, Color.reset);
    print("  {s}•{s} Functions       : {s}{d}{s} total ({s}{d}{s} imported)", .{ Color.bright_blue, Color.reset, Color.bright_green, total_functions, Color.reset, Color.bright_cyan, imported_funcs, Color.reset }, Color.reset);
    print("  {s}•{s} Globals         : {s}{d}{s}", .{ Color.bright_blue, Color.reset, Color.bright_green, module.globals.items.len, Color.reset }, Color.reset);
    print("  {s}•{s} Imports         : {s}{d}{s}", .{ Color.bright_blue, Color.reset, Color.bright_green, module.imports.items.len, Color.reset }, Color.reset);
    print("  {s}•{s} Exports         : {s}{d}{s}", .{ Color.bright_blue, Color.reset, Color.bright_green, module.exports.items.len, Color.reset }, Color.reset);
    print("", .{}, Color.reset);
    print("{s}Breakdown:{s}", .{ Color.bright_yellow, Color.reset }, Color.reset);
    print("  {s}Imports:{s} {s}{d}{s} functions {s}|{s} {s}{d}{s} tables {s}|{s} {s}{d}{s} memories {s}|{s} {s}{d}{s} globals", .{ Color.bright_cyan, Color.reset, Color.bright_green, import_fn, Color.reset, Color.dim, Color.reset, Color.bright_green, import_tables, Color.reset, Color.dim, Color.reset, Color.bright_green, import_memory, Color.reset, Color.dim, Color.reset, Color.bright_green, import_globals, Color.reset }, Color.reset);
    print("  {s}Exports:{s} {s}{d}{s} functions {s}|{s} {s}{d}{s} tables {s}|{s} {s}{d}{s} memories {s}|{s} {s}{d}{s} globals", .{ Color.bright_cyan, Color.reset, Color.bright_green, export_fn, Color.reset, Color.dim, Color.reset, Color.bright_green, export_tables, Color.reset, Color.dim, Color.reset, Color.bright_green, export_memory, Color.reset, Color.dim, Color.reset, Color.bright_green, export_globals, Color.reset }, Color.reset);
    if (module.start_function_index) |start_idx| {
        print("  {s}•{s} Start function  : {s}index {d}{s}", .{ Color.bright_blue, Color.reset, Color.bright_yellow, start_idx, Color.reset }, Color.reset);
    }
    print("", .{}, Color.reset);

    const max_preview: usize = 6;
    if (module.imports.items.len == 0) {
        print("{s}Imports:{s} {s}none{s}", .{ Color.bright_yellow, Color.reset, Color.dim, Color.reset }, Color.reset);
    } else {
        print("{s}Imports:{s}", .{ Color.bright_yellow, Color.reset }, Color.reset);
        const preview = @min(module.imports.items.len, max_preview);
        for (module.imports.items[0..preview]) |import| {
            const kind_color = switch (import.kind) {
                .function => Color.bright_green,
                .table => Color.bright_blue,
                .memory => Color.bright_magenta,
                .global => Color.bright_yellow,
            };
            print("  {s}→{s} {s}{s}{s}.{s}{s} {s}({s}{s}{s})", .{ Color.bright_cyan, Color.reset, Color.white, import.module, Color.reset, Color.bright_white, import.name, Color.dim, kind_color, kindLabel(import.kind), Color.reset }, Color.reset);
        }
        if (module.imports.items.len > max_preview) {
            print("  {s}... ({d} more){s}", .{ Color.dim, module.imports.items.len - max_preview, Color.reset }, Color.reset);
        }
    }
    print("", .{}, Color.reset);

    if (module.exports.items.len == 0) {
        print("{s}Exports:{s} {s}none{s}", .{ Color.bright_yellow, Color.reset, Color.dim, Color.reset }, Color.reset);
    } else {
        print("{s}Exports:{s}", .{ Color.bright_yellow, Color.reset }, Color.reset);
        const preview = @min(module.exports.items.len, max_preview);
        for (module.exports.items[0..preview]) |exp| {
            const kind_color = switch (exp.kind) {
                .function => Color.bright_green,
                .table => Color.bright_blue,
                .memory => Color.bright_magenta,
                .global => Color.bright_yellow,
            };
            print("  {s}→{s} {s}{s}{s} {s}({s}{s}{s}) {s}→ index {s}{d}{s}", .{ Color.bright_green, Color.reset, Color.bright_white, exp.name, Color.reset, Color.dim, kind_color, kindLabel(exp.kind), Color.reset, Color.dim, Color.bright_cyan, exp.index, Color.reset }, Color.reset);
        }
        if (module.exports.items.len > max_preview) {
            print("  {s}... ({d} more){s}", .{ Color.dim, module.exports.items.len - max_preview, Color.reset }, Color.reset);
        }
    }
    print("", .{}, Color.reset);
}
