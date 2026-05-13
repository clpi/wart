const std = @import("std");

pub fn main() !void {
    const stdout = std.Io.File.stdout();
    try stdout.writeAll("Test 1: Simple loop\n");
    
    // Simple test loop
    var sum: i32 = 0;
    var i: i32 = 0;
    while (i < 10) : (i += 1) {
        sum += 1;
    }
    
    var buf: [100]u8 = undefined;
    const msg = try std.fmt.bufPrint(&buf, "Sum: {d}\n", .{sum});
    try stdout.writeAll(msg);
}
