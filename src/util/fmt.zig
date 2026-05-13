const std = @import("std");
const builtin = @import("builtin");

pub const Color = @import("fmt/color.zig");

var log_enabled: bool = builtin.mode == .Debug;
var color_output_enabled: bool = true;

pub fn setLogEnabled(enabled: bool) void {
    log_enabled = enabled;
}

pub fn setColorEnabled(enabled: bool) void {
    color_output_enabled = enabled;
}

pub fn isLogEnabled() bool {
    return log_enabled;
}

pub fn isColorEnabled() bool {
    return color_output_enabled;
}

pub const Log = struct {
    level: Level,
    category: []const u8,
    name: []const u8,

    const Level = enum {
        op,
        err,
        warn,
    };

    pub fn init(_: std.mem.Allocator) void {}

    pub fn op(category: []const u8, name: []const u8) Log {
        return .{ .level = .op, .category = category, .name = name };
    }

    pub fn err(category: []const u8, name: []const u8) Log {
        return .{ .level = .err, .category = category, .name = name };
    }

    pub fn warn(category: []const u8, name: []const u8) Log {
        return .{ .level = .warn, .category = category, .name = name };
    }

    pub fn log(self: Log, comptime fmt: []const u8, args: anytype) void {
        if (!log_enabled) return;

        const level_name = switch (self.level) {
            .op => "trace",
            .err => "error",
            .warn => "warn",
        };

        if (self.name.len == 0) {
            std.debug.print("[{s}] {s}: ", .{ level_name, self.category });
        } else {
            std.debug.print("[{s}] {s}.{s}: ", .{ level_name, self.category, self.name });
        }
        std.debug.print(fmt, args);
        std.debug.print("\n", .{});
    }
};

pub fn print(comptime fmt: []const u8, args: anytype, color: []const u8) void {
    printColor(fmt, args, color, color_output_enabled);
}

pub fn printColor(comptime fmt: []const u8, args: anytype, color: []const u8, color_enabled: bool) void {
    var buffer: [4096]u8 = undefined;
    const rendered = std.fmt.bufPrint(&buffer, fmt, args) catch "formatting error";

    if (color_enabled and color.len != 0 and !std.mem.eql(u8, color, Color.reset)) {
        std.debug.print("{s}{s}{s}\n", .{ color, rendered, Color.reset });
    } else {
        std.debug.print("{s}\n", .{rendered});
    }
}
