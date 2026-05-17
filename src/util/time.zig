const std = @import("std");

pub fn nanoTimestamp() i64 {
    // std.time.nanoTimestamp was removed, returning a time derived from Clock
    return std.time.milliTimestamp() * std.time.ns_per_ms;
}

pub fn secondTimestamp() i64 {
    return std.time.timestamp();
}
