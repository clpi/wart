const std = @import("std");

pub fn hasEnvVarConstant(comptime name: []const u8) bool {
    const name_z = std.fmt.allocPrintZ(std.heap.c_allocator, "{s}", .{name}) catch return false;
    defer std.heap.c_allocator.free(name_z);
    return std.c.getenv(name_z.ptr) != null;
}

pub fn getEnvVarOwned(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    const name_z = try std.fmt.allocPrintZ(allocator, "{s}", .{name});
    defer allocator.free(name_z);

    const value = std.c.getenv(name_z.ptr) orelse return error.EnvironmentVariableNotFound;
    return try allocator.dupe(u8, std.mem.span(value));
}
