const std = @import("std");
const common = @import("common.zig");
const Config = common.Config;
const Color = common.Color;
const print = common.print;
const fmt = @import("../util/fmt.zig");
const Runtime = @import("../wasm/runtime.zig");
const AOT = @import("../wasm/aot.zig").AOT;
const cwd = std.Io.Dir.cwd;

pub const Options = struct {
    wasm_file: [:0]u8,
    output: ?[]const u8 = null,
    optimize: AOT.OptimizeLevel = .Aggressive,
    target_arch: ?std.Target.Cpu.Arch = null,
    config: Config,
};

pub fn parse(base_cfg: Config, args: []const [:0]u8) common.CliError!Options {
    if (args.len == 0) return common.CliError.MissingArgument;

    var wasm_file: ?[:0]u8 = null;
    var output = base_cfg.aot_output;
    var optimize: AOT.OptimizeLevel = .Aggressive;
    var target_arch: ?std.Target.Cpu.Arch = null;
    var cfg = base_cfg;
    cfg.aot = true;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--output") or std.mem.eql(u8, arg, "-o")) {
            if (i + 1 >= args.len) return common.CliError.MissingArgument;
            i += 1;
            output = args[i];
            continue;
        }

        if (std.mem.eql(u8, arg, "--optimize") or std.mem.eql(u8, arg, "-O")) {
            if (i + 1 >= args.len) return common.CliError.MissingArgument;
            i += 1;
            const level_name = args[i];
            if (std.ascii.eqlIgnoreCase(level_name, "debug")) {
                optimize = .Debug;
            } else if (std.ascii.eqlIgnoreCase(level_name, "fast")) {
                optimize = .Fast;
            } else if (std.ascii.eqlIgnoreCase(level_name, "aggressive") or std.ascii.eqlIgnoreCase(level_name, "release")) {
                optimize = .Aggressive;
            } else {
                return common.CliError.InvalidArgument;
            }
            continue;
        }

        if (std.mem.eql(u8, arg, "--target")) {
            if (i + 1 >= args.len) return common.CliError.MissingArgument;
            i += 1;
            target_arch = std.meta.stringToEnum(std.Target.Cpu.Arch, std.mem.sliceTo(args[i], 0)) orelse return common.CliError.InvalidArgument;
            continue;
        }

        if (arg.len > 0 and arg[0] == '-') return common.CliError.InvalidArgument;

        if (wasm_file == null) {
            wasm_file = arg;
        } else {
            return common.CliError.InvalidArgument;
        }
    }

    if (wasm_file == null) return common.CliError.MissingArgument;

    return Options{
        .wasm_file = wasm_file.?,
        .output = output,
        .optimize = optimize,
        .target_arch = target_arch,
        .config = cfg,
    };
}

pub fn run(allocator: std.mem.Allocator, io: std.Io, opts: Options) !void {
    const color_enabled = opts.config.color;
    fmt.setLogEnabled(opts.config.debug);

    print("Compiling {s}", .{opts.wasm_file}, if (color_enabled) Color.bright_cyan else Color.reset);

    const wasm_bytes = cwd().readFileAlloc(io, opts.wasm_file, allocator, .limited(1024 * 1024 * 10)) catch |err| {
        switch (err) {
            error.FileNotFound => {
                print("error: module '{s}' not found", .{opts.wasm_file}, if (color_enabled) Color.red else Color.reset);
                return;
            },
            error.AccessDenied => {
                print("error: permission denied reading '{s}'", .{opts.wasm_file}, if (color_enabled) Color.red else Color.reset);
                return;
            },
            else => return err,
        }
    };
    defer allocator.free(wasm_bytes);

    if (opts.config.verbose >= 1) {
        print("  size: {d} bytes", .{wasm_bytes.len}, Color.reset);
        if (opts.target_arch) |arch| {
            print("  optimize: {s}, target: {s}", .{ @tagName(opts.optimize), @tagName(arch) }, Color.reset);
        } else {
            print("  optimize: {s}", .{@tagName(opts.optimize)}, Color.reset);
        }
    }

    var runtime = try Runtime.init(allocator, io);
    defer runtime.deinit();

    runtime.debug = opts.config.debug;
    runtime.validate = opts.config.validate;

    const module = runtime.loadModule(wasm_bytes) catch |err| {
        print("error: failed to load module: {s}", .{@errorName(err)}, if (color_enabled) Color.red else Color.reset);
        return err;
    };

    var aot_compiler = try AOT.init(allocator, io, module);
    defer aot_compiler.deinit();

    if (opts.target_arch) |arch| {
        aot_compiler.target_arch = arch;
    }
    aot_compiler.optimize = opts.optimize;

    const compiled = try aot_compiler.compileModule();
    defer allocator.free(compiled.native_code);
    defer allocator.free(compiled.function_table);

    const output_path = opts.output orelse blk: {
        const base_name = if (std.mem.endsWith(u8, opts.wasm_file, ".wasm"))
            opts.wasm_file[0 .. opts.wasm_file.len - 5]
        else
            opts.wasm_file;

        const ext = if (@import("builtin").os.tag == .windows) ".exe" else "";
        break :blk try std.fmt.allocPrint(allocator, "{s}{s}", .{ base_name, ext });
    };
    if (opts.output == null) {
        defer allocator.free(output_path);
    }

    try aot_compiler.saveExecutable(compiled, output_path);

    print("Generated {d} bytes of native code", .{compiled.native_code.len}, if (color_enabled) Color.green else Color.reset);
    print("Output: {s}", .{output_path}, Color.reset);
}

pub fn help(program_name: []const u8) void {
    print("{s}wart compile{s}", .{ Color.bright_cyan, Color.reset }, Color.reset);
    print("Usage: {s} compile [options] <module.wasm>", .{program_name}, Color.reset);
    print("Options:", .{}, Color.reset);
    print("  -o, --output <path>      Output path for the native binary", .{}, Color.reset);
    print("  -O, --optimize <level>   Optimization level: debug, fast, aggressive", .{}, Color.reset);
    print("      --target <arch>      Target CPU architecture (e.g. x86_64, aarch64)", .{}, Color.reset);
}
