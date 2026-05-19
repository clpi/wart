const std = @import("std");
const testing = std.testing;
const env = @import("env");

test "hasEnvVarConstant checks environment variable existence" {
    // Non-existing variable should return false
    try testing.expect(!env.hasEnvVarConstant("WART_TEST_VAR_NONEXISTENT_XYZ_12345"));
}
