const std = @import("std");
const common = @import("common.zig");
const Color = common.Color;
const print = common.print;

pub const Options = struct {
    output: ?[]const u8 = null,
    include_source: bool = false,
    workspace: bool = false,
    config: common.Config,
};

pub fn parse(cfg: common.Config, positional: []const [:0]const u8) common.CliError!Options {
    var options = Options{ .config = cfg };

    var i: usize = 0;
    while (i < positional.len) : (i += 1) {
        const arg = positional[i];

        if (std.mem.eql(u8, arg, "--output") or std.mem.eql(u8, arg, "-o")) {
            if (i + 1 >= positional.len) return common.CliError.MissingArgument;
            i += 1;
            options.output = std.mem.sliceTo(positional[i], 0);
        } else if (std.mem.eql(u8, arg, "--source") or std.mem.eql(u8, arg, "-s")) {
            options.include_source = true;
        } else if (std.mem.eql(u8, arg, "--workspace") or std.mem.eql(u8, arg, "-w")) {
            options.workspace = true;
        }
    }

    return options;
}

pub fn run(allocator: std.mem.Allocator, io: std.Io, opts: Options) !void {
    _ = allocator;
    _ = io;
    _ = opts;
    print("Build command not yet implemented", .{}, Color.reset);
}

pub fn help(program_name: []const u8) void {
    print("{s}wart build{s}", .{ Color.bright_cyan, Color.reset }, Color.reset);
    print("Usage: {s} build [--output <path>] [--source] [--workspace]", .{program_name}, Color.reset);
}
