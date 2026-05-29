const std = @import("std");
const common = @import("common.zig");
const execution = @import("execution.zig");
const fmt = @import("../util/fmt.zig");
const Color = common.Color;
const print = common.print;

pub const Options = execution.RunOptions;

pub fn parse(cfg: common.Config, positional: []const [:0]const u8) common.CliError!Options {
    const flagged_file = cfg.cppfile_path orelse cfg.cfile_path;
    const using_flagged_file = flagged_file != null;
    const wasm_file_const: [:0]const u8 = if (using_flagged_file)
        flagged_file.?
    else blk: {
        if (positional.len == 0) return common.CliError.MissingArgument;
        break :blk positional[0];
    };

    const args_slice = if (using_flagged_file) positional else positional[1..];

    return Options{
        .wasm_file = wasm_file_const,
        .args = args_slice,
        .config = cfg,
    };
}

pub fn run(allocator: std.mem.Allocator, io: std.Io, opts: Options) !void {
    fmt.setLogEnabled(opts.config.debug);
    fmt.setColorEnabled(opts.config.color);
    try execution.executeRun(allocator, io, opts);
}

pub fn help(program_name: []const u8) void {
    print("{s}wart run{s}", .{ Color.bright_cyan, Color.reset }, Color.reset);
    print("Usage: {s} run <module.wasm> [args...]", .{program_name}, Color.reset);
    print("       {s} <module.wasm> [args...]", .{program_name}, Color.reset);
    print("Options: global flags such as --debug, --jit, --aot, --wat", .{}, Color.reset);
}
