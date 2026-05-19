const std = @import("std");

pub fn nanoTimestamp() i64 {
    return @as(i64, @intCast(std.time.nanoTimestamp()));
}

pub fn secondTimestamp() i64 {
    return @divFloor(nanoTimestamp(), std.time.ns_per_s);
}