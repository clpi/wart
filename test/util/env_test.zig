const std = @import("std");
const testing = std.testing;
const env = @import("env");

test "hasEnvVarConstant checks environment variable existence" {
    // Existing variable should return true. PATH is universally available.
    // Test with a variable we set ourselves to ensure it exists
    const allocator = std.heap.page_allocator;
    try std.process.getEnvMap(allocator).put("WART_TEST_VAR_EXISTS_XYZ_12345", "test_value");
    try testing.expect(env.hasEnvVarConstant("WART_TEST_VAR_EXISTS_XYZ_12345"));

    // Non-existing variable should return false
    try testing.expect(!env.hasEnvVarConstant("WART_TEST_VAR_NONEXISTENT_XYZ_12345"));
}
