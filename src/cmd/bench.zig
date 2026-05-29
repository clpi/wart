const std = @import("std");
const common = @import("common.zig");
const Config = common.Config;
const Color = common.Color;
const print = common.print;
const run_cmd = @import("run.zig");

pub const Mode = enum {
    suite,
    wasm,
    profile,
};

pub const Options = struct {
    config: Config,
    mode: Mode = .suite,
    wasm_file: ?[:0]const u8 = null,
    args: []const [:0]const u8 = &[_][:0]const u8{},
    profile: []const u8 = "core-universal",
    format: common.ReportFormat = .markdown,
    output: []const u8 = "bench/results",
};

pub fn parse(base_cfg: Config, positional: []const [:0]const u8) common.CliError!Options {
    var cfg = base_cfg;
    cfg.bench = true;

    if (positional.len == 0) {
        return Options{ .config = cfg };
    }

    if (std.mem.eql(u8, positional[0], "run")) {
        var opts = Options{
            .config = cfg,
            .mode = .profile,
        };
        var i: usize = 1;
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

    return Options{
        .config = cfg,
        .mode = .wasm,
        .wasm_file = positional[0],
        .args = positional[1..],
    };
}

pub fn run(allocator: std.mem.Allocator, io: std.Io, opts: Options) !void {
    switch (opts.mode) {
        .suite => {
            try common.runPassthroughCommand(allocator, io, &[_][]const u8{ "bash", "bench.sh" }, ".");
        },
        .wasm => {
            const target = opts.wasm_file orelse return common.CliError.MissingArgument;
            const run_opts = run_cmd.Options{
                .wasm_file = target,
                .args = opts.args,
                .config = opts.config,
            };
            try run_cmd.run(allocator, io, run_opts);
        },
        .profile => {
            try common.runPassthroughCommand(allocator, io, &[_][]const u8{
                "bash",
                "scripts/run-benchmarks.sh",
                "--profile",
                opts.profile,
                "--format",
                common.reportFormatString(opts.format),
                "--output",
                opts.output,
            }, ".");
        },
    }
}

pub fn help(program_name: []const u8) void {
    print("{s}wart bench{s}", .{ Color.bright_cyan, Color.reset }, Color.reset);
    print("Usage: {s} bench [wasm_file] [args...]", .{program_name}, Color.reset);
    print("       {s} bench run [--profile <name>] [--format json|markdown] [--output <dir>]", .{program_name}, Color.reset);
}
