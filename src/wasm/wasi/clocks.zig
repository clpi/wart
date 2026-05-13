const std = @import("std");

/// WASI Preview 2 Clocks Implementation
/// Implements wasi:clocks/monotonic-clock@0.2.0, wall-clock@0.2.0, and timezone@0.2.0
pub const Duration = u64; // nanoseconds
pub const Instant = u64; // nanoseconds since epoch (monotonic)
pub const Datetime = struct {
    seconds: u64,
    nanoseconds: u32,
};

pub const ClockError = error{
    SystemClockUnavailable,
    InvalidTimezone,
};

/// Monotonic Clock - never decreases, unaffected by system time changes
pub const MonotonicClock = struct {
    const Self = @This();

    /// Get current monotonic time instant
    pub fn now() !Instant {
        return @intCast(@import("../../util/time.zig").nanoTimestamp());
    }

    /// Get clock resolution (smallest measurable duration)
    pub fn resolution() Duration {
        return 1; // 1 nanosecond resolution
    }

    /// Subscribe to clock for async/await
    pub fn subscribe(_: Instant, _: bool) !u32 {
        // Returns a pollable handle
        return 0; // Simplified - would return actual pollable
    }
};

/// Wall Clock - real-world time, can jump forward/backward
pub const WallClock = struct {
    const Self = @This();

    /// Get current wall clock time
    pub fn now() !Datetime {
        const timestamp = @import("../../util/time.zig").nanoTimestamp();
        const seconds = @divFloor(timestamp, std.time.ns_per_s);
        const nanoseconds = @mod(timestamp, std.time.ns_per_s);

        return Datetime{
            .seconds = @intCast(seconds),
            .nanoseconds = @intCast(nanoseconds),
        };
    }

    /// Get clock resolution
    pub fn resolution() !Datetime {
        return Datetime{
            .seconds = 0,
            .nanoseconds = 1, // 1 nanosecond resolution
        };
    }
};

/// Timezone information
pub const Timezone = struct {
    const Self = @This();

    pub const TimezoneDisplay = struct {
        utc_offset: i32, // seconds
        name: []const u8,
        in_daylight_saving_time: bool,
    };

    /// Get timezone display information for a given datetime
    pub fn display(when: ?Datetime) !TimezoneDisplay {
        _ = when;

        // Get local timezone offset
        // This is simplified - proper implementation would use system timezone database
        const utc_offset = getUtcOffset();

        return TimezoneDisplay{
            .utc_offset = utc_offset,
            .name = "UTC", // Simplified
            .in_daylight_saving_time = false,
        };
    }

    /// Get UTC offset in seconds for current timezone
    fn getUtcOffset() i32 {
        // Simplified - would query system timezone
        return 0; // UTC
    }

    /// Get timezone from IANA timezone database
    pub fn fromIana(name: []const u8) !Self {
        _ = name;
        return Self{};
    }
};

/// High-resolution timer for benchmarking
pub const Timer = struct {
    start_time: Instant,

    pub fn start() !Timer {
        return Timer{
            .start_time = try MonotonicClock.now(),
        };
    }

    pub fn read(self: *const Timer) !Duration {
        const now = try MonotonicClock.now();
        return now - self.start_time;
    }

    pub fn lap(self: *Timer) !Duration {
        const elapsed = try self.read();
        self.start_time = try MonotonicClock.now();
        return elapsed;
    }

    pub fn reset(self: *Timer) !void {
        self.start_time = try MonotonicClock.now();
    }
};

/// Sleep for specified duration
pub fn sleep(duration: Duration) !void {
    const seconds = duration / std.time.ns_per_s;
    const nanoseconds = duration % std.time.ns_per_s;
    std.time.sleep(seconds * std.time.ns_per_s + nanoseconds);
}

/// Sleep until specific instant
pub fn sleepUntil(instant: Instant) !void {
    const now = try MonotonicClock.now();
    if (instant > now) {
        const duration = instant - now;
        try sleep(duration);
    }
}

// Tests
test "MonotonicClock.now" {
    const t1 = try MonotonicClock.now();
    std.time.sleep(1 * std.time.ns_per_ms);
    const t2 = try MonotonicClock.now();

    try std.testing.expect(t2 > t1);
}

test "WallClock.now" {
    const datetime = try WallClock.now();
    try std.testing.expect(datetime.seconds > 0);
    try std.testing.expect(datetime.nanoseconds < std.time.ns_per_s);
}

test "Timer" {
    var timer = try Timer.start();
    std.time.sleep(5 * std.time.ns_per_ms);
    const elapsed = try timer.read();

    try std.testing.expect(elapsed >= 5 * std.time.ns_per_ms);
}
