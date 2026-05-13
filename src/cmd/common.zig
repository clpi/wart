const std = @import("std");

pub const Config = @import("../config.zig").Config;
pub const Color = @import("../util/fmt/color.zig");
pub const print = @import("../util/fmt.zig").print;

pub const version_string = "0.1.0";

fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

pub const Command: type = enum {
    run,
    bench,
    verify,
    help,
    version,
    completion,
    inspect,
    config,
    init,
    package,
    build,
    deploy,
    compile,
    shell,

    pub fn parse(c: []const u8) ?Command {
        if (eq(c, "run")) return .run;
        if (eq(c, "bench")) return .bench;
        if (eq(c, "verify")) return .verify;
        if (eq(c, "inspect")) return .inspect;
        if (eq(c, "completion")) return .completion;
        if (eq(c, "config")) return .config;
        if (eq(c, "help")) return .help;
        if (eq(c, "version")) return .version;
        if (eq(c, "init")) return .init;
        if (eq(c, "package") or eq(c, "pkg") or eq(c, "workspace") or eq(c, "ws")) return .package;
        if (eq(c, "build") or eq(c, "pack")) return .build;
        if (eq(c, "deploy") or eq(c, "publish") or eq(c, "pub")) return .deploy;
        if (eq(c, "compile")) return .compile;
        if (eq(c, "shell") or eq(c, "repl") or eq(c, "sh")) return .shell;
        return null;
    }
};

pub const ReportFormat: type = union(enum) {
    json,
    markdown,

    pub fn parse(w: []const u8) ?ReportFormat {
        if (eq(w, "json")) return .json else if ((eq(w, "markdown") or eq(w, "md"))) return .markdown else return null;
    }

    pub fn format(self: @This()) []const u8 {
        return switch (self) {
            .json => "json",
            .markdown => "markdown",
        };
    }
};

pub fn parseReportFormat(c: []const u8) ?ReportFormat {
    return ReportFormat.parse(c);
}

pub const CliError: type = error{
    InvalidCommand,
    MissingArgument,
    InvalidArgument,
    UnsupportedShell,
};

pub fn parseCommand(c: []const u8) ?Command {
    return Command.parse(c);
}

pub fn reportFormatString(format: ReportFormat) []const u8 {
    return format.format();
}

pub fn runPassthroughCommand(
    allocator: std.mem.Allocator,
    io: std.Io,
    argv: []const []const u8,
    cwd: []const u8,
) !void {
    const result = try std.process.run(allocator, io, .{
        .argv = argv,
        .cwd = .{ .path = cwd },
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.stdout.len > 0) {
        std.debug.print("{s}", .{result.stdout});
    }
    if (result.stderr.len > 0) {
        std.debug.print("{s}", .{result.stderr});
    }

    if (result.term != .exited or result.term.exited != 0) {
        return error.ChildProcessFailed;
    }
}
