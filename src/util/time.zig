const std = @import("std");

pub fn nanoTimestamp() i64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.REALTIME, &ts);
    return @as(i64, ts.sec) * std.time.ns_per_s + @as(i64, ts.nsec);
}

pub fn secondTimestamp() i64 {
    return @divFloor(nanoTimestamp(), std.time.ns_per_s);
}
