const std = @import("std");

pub const Mutex = struct {
    state: std.atomic.Mutex = .unlocked,

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

test "Condition wait releases and reacquires mutex" {
    var mutex = Mutex{};
    var cond = Condition{};
    var shared_state: u32 = 0;

    const TestThread = struct {
        fn worker(m: *Mutex, c: *Condition, state: *u32) void {
            // Give the main thread time to lock the mutex and enter wait
            std.time.sleep(10 * std.time.ns_per_ms);

            m.lock();
            state.* = 1;
            c.signal();
            m.unlock();
        }
    };

    mutex.lock();

    const thread = try std.Thread.spawn(.{}, TestThread.worker, .{ &mutex, &cond, &shared_state });

    // While waiting, the mutex is unlocked, allowing the worker thread to acquire it
    while (shared_state == 0) {
        cond.wait(&mutex);
    }

    // When wait returns, the mutex must be locked by the calling thread
    try std.testing.expectEqual(@as(u32, 1), shared_state);

    mutex.unlock();
    thread.join();
}
