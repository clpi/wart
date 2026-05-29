const std = @import("std");
const common = @import("common.zig");
const capabilities = @import("../wasm/capabilities.zig");

pub const Options = struct {
    config: common.Config,
    format: common.ReportFormat = .json,
};

pub fn parse(cfg: common.Config, positional: []const [:0]const u8) common.CliError!Options {
    var opts = Options{ .config = cfg };
    var i: usize = 0;
    while (i < positional.len) {
        const arg = positional[i];
        if (std.mem.eql(u8, arg, "--format")) {
            i += 1;
            if (i >= positional.len) return common.CliError.MissingArgument;
            opts.format = common.parseReportFormat(positional[i]) orelse return common.CliError.InvalidArgument;
        } else {
            return common.CliError.InvalidArgument;
        }
        i += 1;
    }
    return opts;
}

pub fn run(allocator: std.mem.Allocator, _: std.Io, opts: Options) !void {
    _ = opts.config;
    const rendered = switch (opts.format) {
        .json => try capabilities.renderJsonAlloc(allocator),
        .markdown => try capabilities.renderMarkdownAlloc(allocator),
    };
    defer allocator.free(rendered);

    if (std.mem.endsWith(u8, rendered, "\n")) {
        std.debug.print("{s}", .{rendered});
    } else {
        std.debug.print("{s}\n", .{rendered});
    }
}
