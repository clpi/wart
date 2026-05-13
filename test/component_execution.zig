const std = @import("std");
const testComponentExecution = @import("../src/wasm/component.zig").testComponentExecution;

test "component execution" {
    const allocator = std.testing.allocator;
    try testComponentExecution(allocator);
}
