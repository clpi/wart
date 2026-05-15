const std = @import("std");
const testing = std.testing;
const env = @import("env");

test "hasEnvVarConstant checks environment variable existence" {
    // Existing variable should return true. PATH is universally available.
    try testing.expect(env.hasEnvVarConstant("PATH"));

    // Non-existing variable should return false
    try testing.expect(!env.hasEnvVarConstant("WART_TEST_VAR_NONEXISTENT_XYZ_12345"));
}
