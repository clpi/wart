const std = @import("std");

pub fn nanoTimestamp() i64 {
    var ts: std.c.timespec = undefined;
    if (std.c.clock_gettime(.REALTIME, &ts) != 0) return 0;

    return @as(i64, @intCast(ts.sec)) * std.time.ns_per_s + @as(i64, @intCast(ts.nsec));
}

pub fn secondTimestamp() i64 {
    return @divFloor(nanoTimestamp(), std.time.ns_per_s);
}
