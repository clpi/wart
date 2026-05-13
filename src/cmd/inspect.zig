const std = @import("std");
const common = @import("common.zig");
const execution = @import("execution.zig");
const inspect_capabilities = @import("inspect_capabilities.zig");
const fmt = @import("../util/fmt.zig");
const Color = common.Color;
const print = common.print;

pub const Options = union(enum) {
    module: execution.InspectOptions,
    capabilities: inspect_capabilities.Options,
};

pub fn parse(cfg: common.Config, positional: []const [:0]u8) common.CliError!Options {
    if (positional.len == 0) return common.CliError.MissingArgument;
    if (std.mem.eql(u8, positional[0], "capabilities")) {
        return Options{ .capabilities = try inspect_capabilities.parse(cfg, positional[1..]) };
    }
    if (positional.len > 1) return common.CliError.InvalidArgument;

    return Options{ .module = .{
        .wasm_file = positional[0],
        .config = cfg,
    } };
}

pub fn run(allocator: std.mem.Allocator, io: std.Io, opts: Options) !void {
    switch (opts) {
        .module => |module_opts| {
            fmt.setLogEnabled(module_opts.config.debug);
            try execution.executeInspect(allocator, io, module_opts);
        },
        .capabilities => |capability_opts| try inspect_capabilities.run(allocator, io, capability_opts),
    }
}

pub fn help(program_name: []const u8) void {
    print("{s}wart inspect{s}", .{ Color.bright_cyan, Color.reset }, Color.reset);
    print("Usage: {s} inspect <wasm_file>", .{program_name}, Color.reset);
    print("       {s} inspect capabilities [--format json|markdown]", .{program_name}, Color.reset);
}
