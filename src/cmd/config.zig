const std = @import("std");
const common = @import("common.zig");
const config_store = @import("../config.zig");
const Config = common.Config;
const Color = common.Color;
const print = common.print;

fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

pub const Action = enum(u3) { get, set, list, init, reset };

pub const Options = struct {
    action: Action,
    key: ?[]const u8 = null,
    value: ?[]const u8 = null,
};

pub fn parse(cfg: Config, w: []const [:0]const u8) common.CliError!Action {
    _ = cfg;
    const aw: []const u8 = std.mem.sliceAsBytes(w);
    if (aw.len == 0 or eq(aw, "list")) return .list;
    if (eq(aw, "get")) return .get;
    if (eq(aw, "set")) return .set;
    if (eq(aw, "init")) return .init;
    if (eq(aw, "reset")) return .reset;
    return common.CliError.InvalidCommand;
}

pub fn exec(cfg: Config, action: Action, positional: []const [:0]const u8) common.CliError!Options {
    _ = cfg;

    if (positional.len == 0)
        return .{ .action = .list };
    var key: ?[]const u8 = null;
    var value: ?[]const u8 = null;
    switch (action) {
        .list, .init, .reset => {
            if (positional.len > 1) return common.CliError.InvalidArgument;
        },
        .get => {
            if (positional.len < 2) return common.CliError.MissingArgument;
            if (positional.len > 2) return common.CliError.InvalidArgument;
            key = std.mem.trim(u8, std.mem.sliceTo(positional[1], 0), &std.ascii.whitespace);
            if (key.?.len == 0) return common.CliError.InvalidArgument;
        },
        .set => {
            if (positional.len < 2) return common.CliError.MissingArgument;
            if (positional.len > 3) return common.CliError.InvalidArgument;

            const first_arg = std.mem.trim(u8, std.mem.sliceTo(positional[1], 0), &std.ascii.whitespace);
            if (first_arg.len == 0) return common.CliError.InvalidArgument;

            if (positional.len == 2) {
                const eq_pos = std.mem.indexOfScalar(u8, first_arg, '=') orelse return common.CliError.MissingArgument;
                const parsed_key = std.mem.trim(u8, first_arg[0..eq_pos], &std.ascii.whitespace);

                const parsed_value = std.mem.trim(u8, first_arg[eq_pos + 1 ..], &std.ascii.whitespace);
                if (parsed_key.len == 0 or parsed_value.len == 0) return common.CliError.InvalidArgument;
                key = parsed_key;
                value = parsed_value;
            } else {
                const second_arg = std.mem.trim(u8, std.mem.sliceTo(positional[2], 0), &std.ascii.whitespace);
                if (second_arg.len == 0) return common.CliError.InvalidArgument;
                key = first_arg;
                value = second_arg;
            }
        },
    }

    return .{
        .action = action,
        .key = key,
        .value = value,
    };
}

pub fn run(allocator: std.mem.Allocator, io: std.Io, opts: Options) !void {
    const config_file = try config_store.defaultConfigFilePath(allocator);
    defer allocator.free(config_file);

    switch (opts.action) {
        .init => {
            const default_cfg = Config.init(io);
            try config_store.saveToDisk(allocator, io, default_cfg);
            print("Initialized config at {s}", .{config_file}, Color.reset);
        },
        .list => {
            const config_content = try config_store.readRawConfig(allocator, io);
            defer allocator.free(config_content);

            print("Config file: {s}", .{config_file}, Color.reset);
            std.debug.print("{s}", .{config_content});
            if (config_content.len == 0 or config_content[config_content.len - 1] != '\n') {
                std.debug.print("\n", .{});
            }
        },
        .get => {
            const key = opts.key orelse return;
            const cfg = config_store.loadFromDisk(allocator, io);
            var integer_buffer: [16]u8 = undefined;

            const rendered_value = cfg.valueForKey(key, integer_buffer[0..]) catch |err| switch (err) {
                error.UnknownKey => {
                    print("error: unknown config key '{s}'", .{key}, Color.red);
                    return;
                },
                else => return err,
            };
            print("{s} = {s}", .{ key, rendered_value }, Color.reset);
        },
        .set => {
            const key = opts.key orelse return;
            const value = opts.value orelse return;
            var cfg = config_store.loadFromDisk(allocator, io);

            cfg.applyKeyValueStrict(key, value) catch |err| switch (err) {
                error.UnknownKey => {
                    print("error: unknown config key '{s}'", .{key}, Color.red);
                    return;
                },
                error.InvalidValue => {
                    print("error: invalid value '{s}' for key '{s}'", .{ value, key }, Color.red);
                    return;
                },
            };

            try config_store.saveToDisk(allocator, io, cfg);
            print("Set {s} = {s} in {s}", .{ key, value, config_file }, Color.reset);
        },
        .reset => {
            try config_store.resetConfig(allocator, io);
            print("Deleted config file {s}", .{config_file}, Color.reset);
        },
    }
}

pub fn help(program_name: []const u8) void {
    print("{s}wart config{s}", .{ Color.bright_cyan, Color.reset }, Color.reset);
    print("Usage: {s} config [list|get|set|init|reset] [key] [value]", .{program_name}, Color.reset);
    print("       {s} config set <key>=<value>", .{program_name}, Color.reset);
}
