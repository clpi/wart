const std = @import("std");
const common = @import("common.zig");
const Color = common.Color;
const print = common.print;

pub const Action = enum {
    list,
    add,
    remove,
    create,
    info,
};

pub const Options = struct {
    action: Action,
    name: ?[]const u8 = null,
    path: ?[]const u8 = null,
    config: common.Config,
};

pub fn parse(cfg: common.Config, positional: []const [:0]u8) common.CliError!Options {
    if (positional.len == 0) {
        return Options{ .action = .list, .config = cfg };
    }

    const action_word = positional[0];
    const action = if (std.mem.eql(u8, action_word, "list") or std.mem.eql(u8, action_word, "ls"))
        Action.list
    else if (std.mem.eql(u8, action_word, "add"))
        Action.add
    else if (std.mem.eql(u8, action_word, "remove") or std.mem.eql(u8, action_word, "rm"))
        Action.remove
    else if (std.mem.eql(u8, action_word, "create") or std.mem.eql(u8, action_word, "new"))
        Action.create
    else if (std.mem.eql(u8, action_word, "info"))
        Action.info
    else
        return common.CliError.InvalidCommand;

    var name: ?[]const u8 = null;
    var path: ?[]const u8 = null;

    if (action == .add or action == .create or action == .remove or action == .info) {
        if (positional.len >= 2) {
            name = std.mem.sliceTo(positional[1], 0);
        }
        if (positional.len >= 3) {
            path = std.mem.sliceTo(positional[2], 0);
        }
    }

    return Options{
        .action = action,
        .name = name,
        .path = path,
        .config = cfg,
    };
}

pub fn run(allocator: std.mem.Allocator, io: std.Io, opts: Options) !void {
    _ = allocator;
    _ = io;
    _ = opts;
    print("Package command not yet implemented", .{}, Color.reset);
}

pub fn help(program_name: []const u8) void {
    print("{s}wart package{s}", .{ Color.bright_cyan, Color.reset }, Color.reset);
    print("Usage: {s} package [list|add|remove|create|info] [name] [path]", .{program_name}, Color.reset);
    print("Aliases: pkg | workspace | ws", .{}, Color.reset);
}
