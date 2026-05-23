const std = @import("std");

pub fn hasEnvVarConstant(comptime name: []const u8) bool {
    const name_z = std.heap.page_allocator.allocSentinel(u8, name.len, 0) catch return false;
    @memcpy(name_z, name);
    defer std.heap.page_allocator.free(name_z);
    return std.c.getenv(name_z.ptr) != null;
}

pub fn getEnvVarOwned(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    const name_z = try allocator.allocSentinel(u8, name.len, 0);
    @memcpy(name_z, name);
    defer allocator.free(name_z);

    const value = std.posix.getenv(name_z.ptr) orelse return error.EnvironmentVariableNotFound;
    return try allocator.dupe(u8, std.mem.span(value));
}

test "getEnvVarOwned returns error.EnvironmentVariableNotFound for nonexistent var" {
    const testing = std.testing;
    const result = getEnvVarOwned(testing.allocator, "NONEXISTENT_VAR_FOR_TESTING");
    try testing.expectError(error.EnvironmentVariableNotFound, result);
}
