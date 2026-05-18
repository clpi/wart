const std = @import("std");

pub fn nanoTimestamp() i64 {
    // In Zig 0.17+, milliTimestamp, microTimestamp, nanoTimestamp, and timestamp functions were removed from std.time.
    // However, they can be implemented using std.time.epoch.EpochSeconds or getting time using std.posix.clock_gettime if necessary.
    // For compatibility across the runtime, returning time via std.time.Timer or clock based structures is standard now.
    // The most compatible fallback for nanoTimestamp() returning i64 currently is using clock_gettime where posix is available:
    var ts: std.posix.timespec = undefined;
    std.posix.clock_gettime(std.posix.CLOCK.REALTIME, &ts) catch return 0;
    return @as(i64, ts.tv_sec) * std.time.ns_per_s + ts.tv_nsec;
}

pub fn secondTimestamp() i64 {
    return @divFloor(nanoTimestamp(), std.time.ns_per_s);
}
