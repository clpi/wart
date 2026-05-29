const std = @import("std");
const common = @import("common.zig");
const Color = common.Color;
const Config = common.Config;
const print = common.print;

pub const Options = struct {
    config: Config,
    profile: []const u8 = "all",
    format: common.ReportFormat = .markdown,
    output: []const u8 = "artifacts/spec",
};

pub fn parse(base_cfg: Config, positional: []const [:0]const u8) common.CliError!Options {
    var opts = Options{ .config = base_cfg };
    var i: usize = 0;

    if (i < positional.len) {
        if (!std.mem.eql(u8, positional[i], "spec")) return common.CliError.InvalidArgument;
        i += 1;
    }

    while (i < positional.len) {
        const arg = positional[i];
        if (std.mem.eql(u8, arg, "--profile")) {
            i += 1;
            if (i >= positional.len) return common.CliError.MissingArgument;
            opts.profile = positional[i];
        } else if (std.mem.eql(u8, arg, "--format")) {
            i += 1;
            if (i >= positional.len) return common.CliError.MissingArgument;
            opts.format = common.parseReportFormat(positional[i]) orelse return common.CliError.InvalidArgument;
        } else if (std.mem.eql(u8, arg, "--output")) {
            i += 1;
            if (i >= positional.len) return common.CliError.MissingArgument;
            opts.output = positional[i];
        } else {
            return common.CliError.InvalidArgument;
        }
        i += 1;
    }

    return opts;
}

pub fn run(allocator: std.mem.Allocator, io: std.Io, opts: Options) !void {
    try common.runPassthroughCommand(allocator, io, &[_][]const u8{
        "bash",
        "scripts/run-spec-tests.sh",
        "--profile",
        opts.profile,
        "--format",
        common.reportFormatString(opts.format),
        "--output",
        opts.output,
    }, ".");
}

pub fn help(program_name: []const u8) void {
    print("{s}wart verify{s}", .{ Color.bright_cyan, Color.reset }, Color.reset);
    print("Usage: {s} verify spec [--profile <name>] [--format json|markdown] [--output <dir>]", .{program_name}, Color.reset);
}
