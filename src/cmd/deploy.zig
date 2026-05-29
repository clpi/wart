const std = @import("std");
const common = @import("common.zig");
const Color = common.Color;
const print = common.print;

pub const Access = enum {
    public,
    private,
    restricted,
};

pub const Options = struct {
    registry: []const u8 = "https://registry.wapm.io",
    package_path: ?[]const u8 = null,
    dry_run: bool = false,
    access: Access = .public,
    config: common.Config,
};

pub fn parse(cfg: common.Config, positional: []const [:0]const u8) common.CliError!Options {
    var options = Options{ .config = cfg };

    var i: usize = 0;
    while (i < positional.len) : (i += 1) {
        const arg = positional[i];

        if (std.mem.eql(u8, arg, "--registry") or std.mem.eql(u8, arg, "-r")) {
            if (i + 1 >= positional.len) return common.CliError.MissingArgument;
            i += 1;
            options.registry = std.mem.sliceTo(positional[i], 0);
        } else if (std.mem.eql(u8, arg, "--dry-run") or std.mem.eql(u8, arg, "-n")) {
            options.dry_run = true;
        } else if (std.mem.eql(u8, arg, "--access") or std.mem.eql(u8, arg, "-a")) {
            if (i + 1 >= positional.len) return common.CliError.MissingArgument;
            i += 1;
            const access_name = std.mem.sliceTo(positional[i], 0);
            if (std.mem.eql(u8, access_name, "public")) {
                options.access = .public;
            } else if (std.mem.eql(u8, access_name, "private")) {
                options.access = .private;
            } else if (std.mem.eql(u8, access_name, "restricted")) {
                options.access = .restricted;
            } else {
                return common.CliError.InvalidArgument;
            }
        } else if (arg[0] != '-') {
            options.package_path = std.mem.sliceTo(arg, 0);
        }
    }

    return options;
}

pub fn run(allocator: std.mem.Allocator, io: std.Io, opts: Options) !void {
    _ = allocator;
    _ = io;
    _ = opts;
    print("Deploy command not yet implemented", .{}, Color.reset);
}

pub fn help(program_name: []const u8) void {
    print("{s}wart deploy{s}", .{ Color.bright_cyan, Color.reset }, Color.reset);
    print("Usage: {s} deploy [--registry <url>] [--dry-run] [--access <level>] [package]", .{program_name}, Color.reset);
    print("Access levels: public | private | restricted", .{}, Color.reset);
}
