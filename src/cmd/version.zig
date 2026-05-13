const common = @import("common.zig");
const print = common.print;
const Color = common.Color;

pub const Options = struct {};

pub fn run() void {
    print("{s}", .{common.version_string}, Color.reset);
}

pub fn help(program_name: []const u8) void {
    print("{s}wart version{s}", .{ Color.bright_cyan, Color.reset }, Color.reset);
    print("Usage: {s} version", .{program_name}, Color.reset);
}
