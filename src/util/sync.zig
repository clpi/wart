const std = @import("std");

pub const Mutex = struct {
    state: std.Thread.Mutex = .{},

    pub fn lock(self: *Mutex) void {
        while (!self.state.tryLock()) {
            std.Thread.yield() catch {};
        }
    }

    pub fn unlock(self: *Mutex) void {
        self.state.unlock();
    }
};

pub const Condition = struct {
    pub fn wait(_: *Condition, mutex: *Mutex) void {
        mutex.unlock();
        std.Thread.yield() catch {};
        mutex.lock();
    }

    pub fn timedwait(self: *Condition, mutex: *Mutex, timeout_ns: u64) !void {
        mutex.unlock();
        _ = timeout_ns;
        std.Thread.yield() catch {};
        mutex.lock();
        _ = self;
    }

    pub fn signal(_: *Condition) void {}

    pub fn broadcast(_: *Condition) void {}
};
