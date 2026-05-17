const std = @import("std");
const Streams = @import("io.zig").Streams;
const builtin = @import("builtin");

pub const CommandHandle = u32;

pub const ExitStatus = union(enum) {
    success,
    terminated: u8,
    signaled: u8,
};

pub const RunError = enum {
    not_found,
    permission_denied,
    invalid_command,
    out_of_memory,
    unsupported,
    io,
};

pub const RunResult = union(enum) {
    ok: ExitStatus,
    err: RunError,
};

pub const StdinBinding = union(enum) {
    inherit,
    null,
    stream: Streams.InputStreamHandle,
};

pub const StdoutBinding = union(enum) {
    inherit,
    null,
    stream: Streams.OutputStreamHandle,
};

/// Enhanced WASI CLI interface with full argument parsing and environment support
pub const Environment = struct {
    args: std.ArrayList([]const u8),
    env: std.StringHashMap([]const u8),
    working_dir: []const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Environment {
        return Environment{
            .args = std.ArrayList([]const u8).init(allocator),
            .env = std.StringHashMap([]const u8).init(allocator),
            .working_dir = allocator.dupe(u8, "/") catch @panic("out of memory"),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Environment) void {
        for (self.args.items) |arg| {
            self.allocator.free(arg);
        }
        self.args.deinit();

        var env_iter = self.env.iterator();
        while (env_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.env.deinit();

        self.allocator.free(self.working_dir);
    }

    pub fn setArg(self: *Environment, index: usize, arg: []const u8) !void {
        const owned_arg = try self.allocator.dupe(u8, arg);
        errdefer self.allocator.free(owned_arg);

        while (self.args.items.len <= index) {
            const empty_arg = try self.allocator.dupe(u8, "");
            errdefer self.allocator.free(empty_arg);
            try self.args.append(empty_arg);
        }

        self.allocator.free(self.args.items[index]);
        self.args.items[index] = owned_arg;
    }

    pub fn setEnv(self: *Environment, key: []const u8, value: []const u8) !void {
        if (self.env.fetchRemove(key)) |previous| {
            self.allocator.free(previous.key);
            self.allocator.free(previous.value);
        }

        const owned_key = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(owned_key);
        const owned_value = try self.allocator.dupe(u8, value);
        errdefer self.allocator.free(owned_value);
        try self.env.put(owned_key, owned_value);
    }

    pub fn getEnv(self: *Environment, key: []const u8) ?[]const u8 {
        return self.env.get(key);
    }
};

pub const CLI = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    streams: *Streams,
    commands: std.AutoHashMap(CommandHandle, Command),
    next_handle: CommandHandle,

    const Command = struct {
        allocator: std.mem.Allocator,
        program: []u8,
        args: std.ArrayListUnmanaged([]const u8),
        env: std.ArrayListUnmanaged(EnvPair),
        cwd: ?[]u8,
        inherit_env: bool,
        stdin_binding: StdinBinding,
        stdout_binding: StdoutBinding,
        stderr_binding: StdoutBinding,

        const EnvPair = struct {
            key: []const u8,
            value: []const u8,
        };

        pub fn init(allocator: std.mem.Allocator, program: []const u8) !Command {
            var command = Command{
                .allocator = allocator,
                .program = try allocator.dupe(u8, program),
                .args = undefined,
                .env = undefined,
                .cwd = null,
                .inherit_env = true,
                .stdin_binding = .inherit,
                .stdout_binding = .inherit,
                .stderr_binding = .inherit,
            };
            command.args = std.ArrayListUnmanaged([]const u8){ .items = &[_][]const u8{}, .capacity = 0 };
            command.env = std.ArrayListUnmanaged(EnvPair){ .items = &[_]EnvPair{}, .capacity = 0 };
            return command;
        }

        pub fn deinit(self: *Command) void {
            self.allocator.free(self.program);
            if (self.cwd) |dir| {
                self.allocator.free(dir);
            }
            for (self.args.items) |argument| {
                self.allocator.free(@constCast(argument));
            }
            self.args.deinit();
            for (self.env.items) |entry| {
                self.allocator.free(@constCast(entry.key));
                self.allocator.free(@constCast(entry.value));
            }
            self.env.deinit(self.allocator);
        }

        pub fn pushArg(self: *Command, arg: []const u8) !void {
            const copy = try self.allocator.dupe(u8, arg);
            errdefer self.allocator.free(copy);
            try self.args.append(self.allocator, copy);
        }

        pub fn clearArgs(self: *Command) void {
            for (self.args.items) |argument| {
                self.allocator.free(@constCast(argument));
            }
            self.args.clearRetainingCapacity();
        }

        pub fn setCwd(self: *Command, cwd: ?[]const u8) !void {
            if (self.cwd) |existing| {
                self.allocator.free(existing);
            }
            if (cwd) |value| {
                self.cwd = try self.allocator.dupe(u8, value);
            } else {
                self.cwd = null;
            }
        }

        pub fn setInheritEnv(self: *Command, inherit: bool) void {
            self.inherit_env = inherit;
        }

        pub fn upsertEnv(self: *Command, key: []const u8, value: []const u8) !void {
            for (self.env.items) |*entry| {
                if (std.mem.eql(u8, entry.key, key)) {
                    const new_value = try self.allocator.dupe(u8, value);
                    self.allocator.free(@constCast(entry.value));
                    entry.value = new_value;
                    return;
                }
            }
            const key_copy = try self.allocator.dupe(u8, key);
            errdefer self.allocator.free(key_copy);
            const value_copy = try self.allocator.dupe(u8, value);
            errdefer self.allocator.free(value_copy);
            try self.env.append(self.allocator, .{ .key = key_copy, .value = value_copy });
        }

        pub fn removeEnv(self: *Command, key: []const u8) void {
            var i: usize = 0;
            while (i < self.env.items.len) {
                if (std.mem.eql(u8, self.env.items[i].key, key)) {
                    const removed = self.env.swapRemove(i);
                    self.allocator.free(@constCast(removed.key));
                    self.allocator.free(@constCast(removed.value));
                } else {
                    i += 1;
                }
            }
        }
    };

    pub fn init(allocator: std.mem.Allocator, streams: *Streams) !CLI {
        return CLI{
            .allocator = allocator,
            .streams = streams,
            .commands = std.AutoHashMap(CommandHandle, Command).init(allocator),
            .next_handle = 1,
        };
    }

    pub fn deinit(self: *CLI) void {
        var it = self.commands.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.commands.deinit();
    }

    pub fn createCommand(self: *CLI, program: []const u8) !CommandHandle {
        const handle = self.next_handle;
        self.next_handle += 1;

        var command = try Command.init(self.allocator, program);
        errdefer command.deinit();

        try self.commands.putNoClobber(handle, command);
        return handle;
    }

    fn getCommand(self: *CLI, handle: CommandHandle) !*Command {
        return self.commands.getPtr(handle) orelse return error.InvalidCommandHandle;
    }

    pub fn dropCommand(self: *CLI, handle: CommandHandle) void {
        if (self.commands.fetchRemove(handle)) |kv| {
            var cmd = kv.value;
            cmd.deinit();
        }
    }

    pub fn commandPushArg(self: *CLI, handle: CommandHandle, arg: []const u8) !void {
        const cmd = try self.getCommand(handle);
        try cmd.pushArg(arg);
    }

    pub fn commandClearArgs(self: *CLI, handle: CommandHandle) !void {
        const cmd = try self.getCommand(handle);
        cmd.clearArgs();
    }

    pub fn commandSetCwd(self: *CLI, handle: CommandHandle, cwd: ?[]const u8) !void {
        const cmd = try self.getCommand(handle);
        try cmd.setCwd(cwd);
    }

    pub fn commandSetInheritEnv(self: *CLI, handle: CommandHandle, inherit: bool) !void {
        const cmd = try self.getCommand(handle);
        cmd.setInheritEnv(inherit);
    }

    pub fn commandSetEnv(self: *CLI, handle: CommandHandle, key: []const u8, value: []const u8) !void {
        const cmd = try self.getCommand(handle);
        try cmd.upsertEnv(key, value);
    }

    pub fn commandRemoveEnv(self: *CLI, handle: CommandHandle, key: []const u8) !void {
        const cmd = try self.getCommand(handle);
        cmd.removeEnv(key);
    }

    pub fn commandSetStdin(self: *CLI, handle: CommandHandle, binding: StdinBinding) !void {
        const cmd = try self.getCommand(handle);
        cmd.stdin_binding = binding;
    }

    pub fn commandSetStdout(self: *CLI, handle: CommandHandle, binding: StdoutBinding) !void {
        const cmd = try self.getCommand(handle);
        cmd.stdout_binding = binding;
    }

    pub fn commandSetStderr(self: *CLI, handle: CommandHandle, binding: StdoutBinding) !void {
        const cmd = try self.getCommand(handle);
        cmd.stderr_binding = binding;
    }

    pub fn run(self: *CLI, handle: CommandHandle) RunResult {
        const cmd = self.commands.getPtr(handle) orelse return .{ .err = .invalid_command };

        const argv_len = cmd.args.items.len + 1;
        const argv = self.allocator.alloc([]const u8, argv_len) catch {
            return .{ .err = .out_of_memory };
        };
        defer self.allocator.free(argv);

        argv[0] = cmd.program;
        for (cmd.args.items, 0..) |argument, idx| {
            argv[idx + 1] = argument;
        }

        // Simulate command execution (in real implementation, this would spawn a process)
        if (std.mem.eql(u8, cmd.program, "echo")) {
            // Simple echo implementation for testing
            for (cmd.args.items) |arg| {
                std.debug.print("{s} ", .{arg});
            }
            std.debug.print("\n", .{});
            return .{ .ok = .success };
        } else if (std.mem.eql(u8, cmd.program, "exit")) {
            const code: u8 = if (cmd.args.items.len > 0)
                std.fmt.parseInt(u8, cmd.args.items[0], 10) catch 1
            else
                0;
            return .{ .ok = .{ .terminated = code } };
        }

        return .{ .err = .not_found };
    }
};
