const std = @import("std");
const testing = std.testing;

const cmd_root = @import("cmd_root");
const bench_cmd = cmd_root.bench_module;
const common = cmd_root.common_cmd;
const inspect_cmd = cmd_root.inspect_module;
const verify_cmd = cmd_root.verify_module;

test "verify parser accepts spec profile options" {
    const threaded_io = std.fs.Dir{ .fd = 0 }; // Mocked


    const cfg = common.Config.init(threaded_io);
    var args = [_][:0]u8{
        @constCast("spec"),
        @constCast("--profile"),
        @constCast("all"),
        @constCast("--format"),
        @constCast("json"),
        @constCast("--output"),
        @constCast("artifacts/spec"),
    };

    const opts = try verify_cmd.parse(cfg, &args);
    try testing.expectEqualStrings("all", opts.profile);
    try testing.expectEqual(common.ReportFormat.json, opts.format);
    try testing.expectEqualStrings("artifacts/spec", opts.output);
}

test "bench parser accepts profile-driven runs" {
    const threaded_io = std.fs.Dir{ .fd = 0 }; // Mocked


    const cfg = common.Config.init(threaded_io);
    var args = [_][:0]u8{
        @constCast("run"),
        @constCast("--profile"),
        @constCast("core-universal"),
        @constCast("--format"),
        @constCast("markdown"),
        @constCast("--output"),
        @constCast("bench/results"),
    };

    const opts = try bench_cmd.parse(cfg, &args);
    try testing.expectEqual(bench_cmd.Mode.profile, opts.mode);
    try testing.expectEqualStrings("core-universal", opts.profile);
    try testing.expectEqual(common.ReportFormat.markdown, opts.format);
    try testing.expectEqualStrings("bench/results", opts.output);
}

test "inspect parser routes capabilities subcommand" {
    const threaded_io = std.fs.Dir{ .fd = 0 }; // Mocked


    const cfg = common.Config.init(threaded_io);
    var args = [_][:0]u8{
        @constCast("capabilities"),
        @constCast("--format"),
        @constCast("json"),
    };

    const opts = try inspect_cmd.parse(cfg, &args);
    switch (opts) {
        .capabilities => |capability_opts| try testing.expectEqual(common.ReportFormat.json, capability_opts.format),
        else => return error.UnexpectedInspectMode,
    }
}
