const std = @import("std");
const posix = std.posix;

/// WASI Preview 2 Poll Implementation
/// Provides async I/O primitives per wasi:io/poll spec
pub const PollError = error{
    InvalidHandle,
    Timeout,
    Interrupted,
};

pub const PollEvents = packed struct(u16) {
    read: bool = false,
    write: bool = false,
    @"error": bool = false,
    hangup: bool = false,
    _padding: u12 = 0,

    pub fn toOsEvents(self: PollEvents) i16 {
        var events: i16 = 0;
        if (self.read) events |= posix.POLL.IN;
        if (self.write) events |= posix.POLL.OUT;
        if (self.@"error") events |= posix.POLL.ERR;
        if (self.hangup) events |= posix.POLL.HUP;
        return events;
    }

    pub fn fromOsEvents(os_events: i16) PollEvents {
        return PollEvents{
            .read = (os_events & posix.POLL.IN) != 0,
            .write = (os_events & posix.POLL.OUT) != 0,
            .@"error" = (os_events & posix.POLL.ERR) != 0,
            .hangup = (os_events & posix.POLL.HUP) != 0,
        };
    }
};

pub const PollableHandle = u32;

pub const Pollable = struct {
    fd: posix.fd_t,
    events: PollEvents,
    ready: bool = false,
};

pub const PollResult = struct {
    handle: PollableHandle,
    events: PollEvents,
};

pub const PollManager = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    pollables: std.AutoHashMap(PollableHandle, Pollable),
    next_handle: PollableHandle,

    pub fn init(allocator: std.mem.Allocator) !Self {
        return Self{
            .allocator = allocator,
            .pollables = std.AutoHashMap(PollableHandle, Pollable).init(allocator),
            .next_handle = 1,
        };
    }

    pub fn deinit(self: *Self) void {
        self.pollables.deinit();
    }

    /// Create a new pollable from a file descriptor
    pub fn createPollable(self: *Self, fd: posix.fd_t, events: PollEvents) !PollableHandle {
        const handle = self.next_handle;
        self.next_handle += 1;

        try self.pollables.put(handle, Pollable{
            .fd = fd,
            .events = events,
            .ready = false,
        });

        return handle;
    }

    /// Remove a pollable
    pub fn dropPollable(self: *Self, handle: PollableHandle) void {
        _ = self.pollables.remove(handle);
    }

    /// Check if a pollable is ready (non-blocking)
    pub fn checkReady(self: *Self, handle: PollableHandle) !bool {
        const pollable = self.pollables.getPtr(handle) orelse return PollError.InvalidHandle;

        var fds = [_]posix.pollfd{
            .{
                .fd = pollable.fd,
                .events = pollable.events.toOsEvents(),
                .revents = 0,
            },
        };

        // Non-blocking check (timeout = 0)
        const ready_count = try posix.poll(&fds, 0);

        if (ready_count > 0) {
            pollable.ready = true;
            pollable.events = PollEvents.fromOsEvents(fds[0].revents);
            return true;
        }

        return false;
    }

    /// Poll a single pollable (blocking)
    pub fn pollOne(self: *Self, handle: PollableHandle, timeout_ms: ?i32) !PollResult {
        const pollable = self.pollables.getPtr(handle) orelse return PollError.InvalidHandle;

        var fds = [_]posix.pollfd{
            .{
                .fd = pollable.fd,
                .events = pollable.events.toOsEvents(),
                .revents = 0,
            },
        };

        const ready_count = try posix.poll(&fds, timeout_ms orelse -1);

        if (ready_count == 0) return PollError.Timeout;

        pollable.ready = true;
        const result_events = PollEvents.fromOsEvents(fds[0].revents);
        pollable.events = result_events;

        return PollResult{
            .handle = handle,
            .events = result_events,
        };
    }

    /// Poll multiple pollables at once
    pub fn pollList(
        self: *Self,
        handles: []const PollableHandle,
        timeout_ms: ?i32,
    ) ![]PollResult {
        if (handles.len == 0) return &[_]PollResult{};

        // Prepare pollfd array
        var fds = try self.allocator.alloc(posix.pollfd, handles.len);
        defer self.allocator.free(fds);

        for (handles, 0..) |handle, i| {
            const pollable = self.pollables.get(handle) orelse return PollError.InvalidHandle;
            fds[i] = posix.pollfd{
                .fd = pollable.fd,
                .events = pollable.events.toOsEvents(),
                .revents = 0,
            };
        }

        // Perform poll
        const ready_count = try posix.poll(fds, timeout_ms orelse -1);

        if (ready_count == 0) return PollError.Timeout;

        // Collect results
        var results = try self.allocator.alloc(PollResult, ready_count);
        var result_idx: usize = 0;

        for (handles, 0..) |handle, i| {
            if (fds[i].revents != 0) {
                const result_events = PollEvents.fromOsEvents(fds[i].revents);

                // Update pollable state
                if (self.pollables.getPtr(handle)) |pollable| {
                    pollable.ready = true;
                    pollable.events = result_events;
                }

                results[result_idx] = PollResult{
                    .handle = handle,
                    .events = result_events,
                };
                result_idx += 1;
            }
        }

        return results[0..result_idx];
    }

    /// Block until any pollable is ready
    pub fn blockUntilAny(
        self: *Self,
        handles: []const PollableHandle,
    ) ![]PollResult {
        return self.pollList(handles, null);
    }

    /// Block until any pollable is ready or timeout
    pub fn blockUntilAnyTimeout(
        self: *Self,
        handles: []const PollableHandle,
        timeout_ns: u64,
    ) ![]PollResult {
        const timeout_ms: i32 = @intCast(@min(timeout_ns / 1_000_000, std.math.maxInt(i32)));
        return self.pollList(handles, timeout_ms);
    }

    /// Poll multiple pollables (alias for WASI Preview 2 compatibility)
    pub fn pollMultiple(
        self: *Self,
        handles: []const PollableHandle,
        timeout_ms: ?i32,
    ) ![]usize {
        const results = try self.pollList(handles, timeout_ms);
        // Convert PollResult array to indices
        const indices = try self.allocator.alloc(usize, results.len);
        for (results, 0..) |result, i| {
            // Find the index of this handle in the original array
            for (handles, 0..) |h, j| {
                if (h == result.handle) {
                    indices[i] = j;
                    break;
                }
            }
        }
        return indices;
    }
};

/// Subscription type for WASI Preview 1 poll_oneoff compatibility
pub const Subscription = struct {
    userdata: u64,
    event_type: EventType,
    fd: posix.fd_t,
    events: PollEvents,
    timeout_ns: u64 = 0,

    pub const EventType = enum(u8) {
        clock = 0,
        fd_read = 1,
        fd_write = 2,
    };
};

/// Event result for WASI Preview 1 poll_oneoff compatibility
pub const Event = struct {
    userdata: u64,
    errno: u16,
    event_type: Subscription.EventType,
};

/// WASI Preview 1 compatible poll_oneoff implementation
pub fn pollOneoff(
    allocator: std.mem.Allocator,
    subscriptions: []const Subscription,
) ![]Event {
    if (subscriptions.len == 0) return &[_]Event{};

    var fds = try allocator.alloc(posix.pollfd, subscriptions.len);
    defer allocator.free(fds);

    var min_timeout_ns: ?u64 = null;

    // Prepare poll fds
    for (subscriptions, 0..) |sub, i| {
        fds[i] = posix.pollfd{
            .fd = sub.fd,
            .events = sub.events.toOsEvents(),
            .revents = 0,
        };

        // Track minimum timeout
        if (sub.event_type == .clock) {
            if (min_timeout_ns) |current_min| {
                min_timeout_ns = @min(current_min, sub.timeout_ns);
            } else {
                min_timeout_ns = sub.timeout_ns;
            }
        }
    }

    // Convert timeout to milliseconds
    const timeout_ms: i32 = if (min_timeout_ns) |ns|
        @intCast(@min(ns / 1_000_000, std.math.maxInt(i32)))
    else
        -1;

    // Perform poll
    const ready_count = try posix.poll(fds, timeout_ms);

    // Build event results
    var events = try allocator.alloc(Event, ready_count);
    var event_idx: usize = 0;

    for (subscriptions, 0..) |sub, i| {
        if (fds[i].revents != 0 or (ready_count == 0 and sub.event_type == .clock)) {
            events[event_idx] = Event{
                .userdata = sub.userdata,
                .errno = 0,
                .event_type = sub.event_type,
            };
            event_idx += 1;
        }
    }

    return events[0..event_idx];
}

// Tests
test "PollEvents to OS events" {
    const events = PollEvents{ .read = true, .write = true };
    const os_events = events.toOsEvents();
    try std.testing.expect((os_events & posix.POLL.IN) != 0);
    try std.testing.expect((os_events & posix.POLL.OUT) != 0);
}

test "PollEvents from OS events" {
    const os_events: i16 = posix.POLL.IN | posix.POLL.ERR;
    const events = PollEvents.fromOsEvents(os_events);
    try std.testing.expect(events.read);
    try std.testing.expect(events.@"error");
    try std.testing.expect(!events.write);
}

test "PollManager creation" {
    const allocator = std.testing.allocator;
    var manager = try PollManager.init(allocator);
    defer manager.deinit();

    try std.testing.expectEqual(@as(PollableHandle, 1), manager.next_handle);
}

test "Create and drop pollable" {
    const allocator = std.testing.allocator;
    var manager = try PollManager.init(allocator);
    defer manager.deinit();

    const handle = try manager.createPollable(0, .{ .read = true });
    try std.testing.expect(handle >= 1);

    manager.dropPollable(handle);
    try std.testing.expectEqual(@as(?*Pollable, null), manager.pollables.getPtr(handle));
}
