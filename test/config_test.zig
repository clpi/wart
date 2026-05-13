const std = @import("std");
const cmd_root = @import("cmd_root");
const common = cmd_root.common_cmd;
const config_cmd = cmd_root.config_module;

test "config key validation handles bool and numeric values" {
    var threaded_io = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded_io.deinit();

    var cfg = common.Config.init(threaded_io.io());
    try cfg.applyKeyValueStrict("color", "false");
    try std.testing.expect(!cfg.color);

    try cfg.applyKeyValueStrict("verbose", "2");
    try std.testing.expectEqual(@as(u8, 2), cfg.verbose);

    try std.testing.expectError(
        cmd_root.ConfigKeyError.InvalidValue,
        cfg.applyKeyValueStrict("color", "off"),
    );
    try std.testing.expectError(
        cmd_root.ConfigKeyError.UnknownKey,
        cfg.applyKeyValueStrict("does_not_exist", "true"),
    );
}

test "config command parser accepts set key=value syntax" {
    var threaded_io = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded_io.deinit();
    const base_cfg = common.Config.init(threaded_io.io());

    var args = [_][:0]u8{
        @constCast("set"),
        @constCast("color=false"),
    };

    const opts = try config_cmd.parse(base_cfg, &args);
    try std.testing.expectEqual(config_cmd.Action.set, opts.action);
    try std.testing.expectEqualStrings("color", opts.key.?);
    try std.testing.expectEqualStrings("false", opts.value.?);
}
