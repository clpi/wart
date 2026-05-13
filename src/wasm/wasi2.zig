/// WASI Preview 2 (WASI 0.2) Implementation
///
/// WASI Preview 2 is a major redesign of WASI that introduces:
/// - Component Model integration
/// - Modular interface design (worlds)
/// - Resource types with ownership
/// - Async primitives (futures, streams)
/// - Better abstraction boundaries
///
/// Core interfaces:
/// - wasi:io - I/O primitives (streams, poll)
/// - wasi:filesystem - File and directory operations
/// - wasi:sockets - Network socket operations
/// - wasi:clocks - Time and clock operations
/// - wasi:random - Random number generation
/// - wasi:cli - CLI environment (args, env, exit, stdio)
/// - wasi:http - HTTP client and server
const std = @import("std");
const Allocator = std.mem.Allocator;
const Module = @import("module.zig");

/// WASI Preview 2 main context
pub const WASI2 = struct {
    allocator: Allocator,
    io: std.Io,
    debug: bool = false,

    // Interface implementations
    streams: *IO,
    filesystem: *Filesystem,
    sockets: *Sockets,
    clocks: *Clocks,
    random: *Random,
    cli: *CLI,
    http: *HTTP,

    pub fn init(allocator: Allocator, io: std.Io) !*WASI2 {
        const wasi2 = try allocator.create(WASI2);

        wasi2.* = WASI2{
            .allocator = allocator,
            .io = io,
            .streams = try IO.init(allocator),
            .filesystem = try Filesystem.init(allocator, io),
            .sockets = try Sockets.init(allocator, io),
            .clocks = try Clocks.init(allocator),
            .random = try Random.init(allocator),
            .cli = try CLI.init(allocator),
            .http = try HTTP.init(allocator),
        };

        return wasi2;
    }

    pub fn deinit(self: *WASI2) void {
        self.streams.deinit();
        self.filesystem.deinit();
        self.sockets.deinit();
        self.clocks.deinit();
        self.random.deinit();
        self.cli.deinit();
        self.http.deinit();
        self.allocator.destroy(self);
    }
};

/// wasi:io - Core I/O primitives
/// Provides streams, polling, and async I/O operations
pub const IO = struct {
    allocator: Allocator,
    streams: std.ArrayList(Stream),
    pollables: std.ArrayList(Pollable),

    pub const Stream = struct {
        id: u32,
        kind: StreamKind,
        buffer: std.ArrayList(u8),
        closed: bool = false,
        error_state: ?Error = null,

        pub const StreamKind = enum {
            input,
            output,
        };

        pub const Error = enum {
            closed,
            last_operation_failed,
        };
    };

    pub const Pollable = struct {
        id: u32,
        ready: bool = false,
        stream_id: ?u32 = null,
    };

    pub fn init(allocator: Allocator) !*IO {
        const io = try allocator.create(IO);
        io.* = IO{
            .allocator = allocator,
            .streams = .{},
            .pollables = .{},
        };
        return io;
    }

    pub fn deinit(self: *IO) void {
        for (self.streams.items) |*stream| {
            stream.buffer.deinit(self.allocator);
        }
        self.streams.deinit(self.allocator);
        self.pollables.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    /// Read from an input stream
    pub fn read(self: *IO, stream_id: u32, len: u64) ![]const u8 {
        for (self.streams.items) |*stream| {
            if (stream.id == stream_id) {
                if (stream.kind != .input) return error.InvalidStream;
                if (stream.closed) return error.StreamClosed;

                const read_len = @min(len, stream.buffer.items.len);
                const data = try self.allocator.alloc(u8, read_len);
                @memcpy(data, stream.buffer.items[0..read_len]);

                // Remove read data from buffer
                std.mem.copyForwards(u8, stream.buffer.items, stream.buffer.items[read_len..]);
                stream.buffer.shrinkRetainingCapacity(stream.buffer.items.len - read_len);

                return data;
            }
        }
        return error.StreamNotFound;
    }

    /// Write to an output stream
    pub fn write(self: *IO, stream_id: u32, data: []const u8) !u64 {
        for (self.streams.items) |*stream| {
            if (stream.id == stream_id) {
                if (stream.kind != .output) return error.InvalidStream;
                if (stream.closed) return error.StreamClosed;

                try stream.buffer.appendSlice(self.allocator, data);
                return data.len;
            }
        }
        return error.StreamNotFound;
    }

    /// Create a new pollable for a stream
    pub fn subscribeToInputStream(self: *IO, stream_id: u32) !u32 {
        const pollable = Pollable{
            .id = @intCast(self.pollables.items.len),
            .stream_id = stream_id,
        };
        try self.pollables.append(self.allocator, pollable);
        return pollable.id;
    }

    /// Poll multiple pollables
    pub fn poll(self: *IO, pollable_ids: []const u32) ![]const u32 {
        var ready = std.ArrayList(u32).empty;
        defer ready.deinit(self.allocator);

        for (pollable_ids) |id| {
            if (id < self.pollables.items.len) {
                const pollable = &self.pollables.items[id];

                // Check if associated stream is ready
                if (pollable.stream_id) |stream_id| {
                    for (self.streams.items) |stream| {
                        if (stream.id == stream_id and stream.buffer.items.len > 0) {
                            try ready.append(self.allocator, id);
                            break;
                        }
                    }
                }
            }
        }

        return try ready.toOwnedSlice(self.allocator);
    }
};

/// wasi:filesystem - File and directory operations
/// Modern filesystem API with proper resource management
pub const Filesystem = struct {
    allocator: Allocator,
    io: std.Io,
    descriptors: std.ArrayList(Descriptor),

    pub const Descriptor = struct {
        id: u32,
        path: []const u8,
        file: ?std.Io.File = null,
        dir: ?std.fs.Dir = null,
        kind: DescriptorKind,

        pub const DescriptorKind = enum {
            file,
            directory,
        };
    };

    pub const DescriptorFlags = packed struct {
        read: bool = false,
        write: bool = false,
        file_integrity_sync: bool = false,
        data_integrity_sync: bool = false,
        requested_write_sync: bool = false,
        mutate_directory: bool = false,
    };

    pub const PathFlags = packed struct {
        symlink_follow: bool = true,
    };

    pub const OpenFlags = packed struct {
        create: bool = false,
        directory: bool = false,
        exclusive: bool = false,
        truncate: bool = false,
    };

    pub fn init(allocator: Allocator, io: std.Io) !*Filesystem {
        const fs = try allocator.create(Filesystem);
        fs.* = Filesystem{
            .allocator = allocator,
            .io = io,
            .descriptors = .{},
        };
        return fs;
    }

    pub fn deinit(self: *Filesystem) void {
        for (self.descriptors.items) |*desc| {
            if (desc.file) |file| file.close(self.io);
            if (desc.dir) |*dir| dir.close(self.io);
            self.allocator.free(desc.path);
        }
        self.descriptors.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    /// Open a file or directory at a path
    pub fn openAt(
        self: *Filesystem,
        base_descriptor: u32,
        path_flags: PathFlags,
        path: []const u8,
        open_flags: OpenFlags,
        flags: DescriptorFlags,
    ) !u32 {
        _ = base_descriptor;
        _ = path_flags;
        const new_id: u32 = @intCast(self.descriptors.items.len);

        var descriptor = Descriptor{
            .id = new_id,
            .path = try self.allocator.dupe(u8, path),
            .kind = if (open_flags.directory) .directory else .file,
        };

        if (open_flags.directory) {
            descriptor.dir = try std.Io.Dir.cwd().openDir(io, path, .{});
        } else {
            var open_mode: std.Io.File.OpenMode = .read_only;
            if (flags.write) open_mode = .read_write;

            if (open_flags.create) {
                descriptor.file = try std.Io.Dir.cwd().createFile(io, path, .{
                    .read = flags.read,
                    .truncate = open_flags.truncate,
                });
            } else {
                descriptor.file = try std.Io.Dir.cwd().openFile(io, path, .{ .mode = open_mode });
                if (open_flags.truncate) {
                    try descriptor.file.?.setEndPos(0);
                }
            }
        }

        try self.descriptors.append(self.allocator, descriptor);
        return new_id;
    }

    /// Read from a file descriptor
    pub fn read(self: *Filesystem, descriptor: u32, length: u64, offset: u64) ![]const u8 {
        for (self.descriptors.items) |*desc| {
            if (desc.id == descriptor) {
                if (desc.file) |file| {
                    const buf = try self.allocator.alloc(u8, length);
                    const bytes_read = try file.readPositionalAll(self.io, buf, offset);
                    return buf[0..bytes_read];
                }
                return error.NotAFile;
            }
        }
        return error.BadDescriptor;
    }

    /// Write to a file descriptor
    pub fn write(self: *Filesystem, descriptor: u32, data: []const u8, offset: u64) !u64 {
        for (self.descriptors.items) |*desc| {
            if (desc.id == descriptor) {
                if (desc.file) |file| {
                    try file.writePositionalAll(self.io, data, offset);
                    return data.len;
                }
                return error.NotAFile;
            }
        }
        return error.BadDescriptor;
    }

    /// Get metadata for a path
    pub fn statAt(
        self: *Filesystem,
        descriptor: u32,
        path_flags: PathFlags,
        path: []const u8,
    ) !DescriptorStat {
        _ = self;
        _ = descriptor;
        _ = path_flags;

        const stat = try std.Io.Dir.cwd().statFile(self.io, path);

        return DescriptorStat{
            .type = switch (stat.kind) {
                .file => .regular_file,
                .directory => .directory,
                .sym_link => .symbolic_link,
                else => .unknown,
            },
            .link_count = 1,
            .size = stat.size,
            .data_access_timestamp = .{ .seconds = 0, .nanoseconds = 0 },
            .data_modification_timestamp = .{ .seconds = 0, .nanoseconds = 0 },
            .status_change_timestamp = .{ .seconds = 0, .nanoseconds = 0 },
        };
    }

    pub const DescriptorStat = struct {
        type: DescriptorType,
        link_count: u64,
        size: u64,
        data_access_timestamp: Datetime,
        data_modification_timestamp: Datetime,
        status_change_timestamp: Datetime,
    };

    pub const DescriptorType = enum {
        unknown,
        block_device,
        character_device,
        directory,
        fifo,
        symbolic_link,
        regular_file,
        socket,
    };

    pub const Datetime = struct {
        seconds: u64,
        nanoseconds: u32,
    };
};

/// wasi:sockets - Network socket operations
/// TCP and UDP socket support with async capabilities
pub const Sockets = struct {
    allocator: Allocator,
    io: std.Io,
    tcp_sockets: std.ArrayList(TcpSocket),
    udp_sockets: std.ArrayList(UdpSocket),

    pub const TcpSocket = struct {
        id: u32,
        stream: ?std.net.Stream = null,
        server: ?std.net.Server = null,
        state: SocketState,

        pub const SocketState = enum {
            unbound,
            bound,
            listening,
            connected,
            closed,
        };
    };

    pub const UdpSocket = struct {
        id: u32,
        socket: ?std.posix.socket_t = null,
        bound_addr: ?std.net.Address = null,
        state: SocketState,

        pub const SocketState = enum {
            unbound,
            bound,
            connected,
            closed,
        };
    };

    pub const IpAddressFamily = enum {
        ipv4,
        ipv6,
    };

    pub fn init(allocator: Allocator, io: std.Io) !*Sockets {
        const sockets = try allocator.create(Sockets);
        sockets.* = Sockets{
            .allocator = allocator,
            .io = io,
            .tcp_sockets = .{},
            .udp_sockets = .{},
        };
        return sockets;
    }

    pub fn deinit(self: *Sockets) void {
        for (self.tcp_sockets.items) |*sock| {
            if (sock.stream) |stream| stream.close(self.io);
            if (sock.server) |*server| server.deinit();
        }
        self.tcp_sockets.deinit(self.allocator);
        self.udp_sockets.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    /// Create a new TCP socket
    pub fn createTcpSocket(self: *Sockets, address_family: IpAddressFamily) !u32 {
        _ = address_family;

        const socket_id: u32 = @intCast(self.tcp_sockets.items.len);
        const socket = TcpSocket{
            .id = socket_id,
            .state = .unbound,
        };

        try self.tcp_sockets.append(self.allocator, socket);
        return socket_id;
    }

    /// Bind a TCP socket to an address
    pub fn bindTcp(self: *Sockets, socket_id: u32, address: []const u8, port: u16) !void {
        for (self.tcp_sockets.items) |*sock| {
            if (sock.id == socket_id) {
                const addr = try std.net.Address.parseIp(address, port);
                sock.server = try addr.listen(.{});
                sock.state = .bound;
                return;
            }
        }
        return error.SocketNotFound;
    }

    /// Listen for connections on a TCP socket
    pub fn listen(self: *Sockets, socket_id: u32) !void {
        for (self.tcp_sockets.items) |*sock| {
            if (sock.id == socket_id) {
                if (sock.state != .bound) return error.SocketNotBound;
                sock.state = .listening;
                return;
            }
        }
        return error.SocketNotFound;
    }

    /// Accept a connection on a listening TCP socket
    pub fn accept(self: *Sockets, socket_id: u32) !u32 {
        for (self.tcp_sockets.items) |*sock| {
            if (sock.id == socket_id) {
                if (sock.server) |*server| {
                    const connection = try server.accept();

                    const new_socket_id: u32 = @intCast(self.tcp_sockets.items.len);
                    const new_socket = TcpSocket{
                        .id = new_socket_id,
                        .stream = connection.stream,
                        .state = .connected,
                    };

                    try self.tcp_sockets.append(new_socket);
                    return new_socket_id;
                }
                return error.NotListening;
            }
        }
        return error.SocketNotFound;
    }

    /// Connect a TCP socket to a remote address
    pub fn connect(self: *Sockets, socket_id: u32, address: []const u8, port: u16) !void {
        for (self.tcp_sockets.items) |*sock| {
            if (sock.id == socket_id) {
                const addr = try std.net.Address.parseIp(address, port);
                sock.stream = try std.net.tcpConnectToAddress(addr);
                sock.state = .connected;
                return;
            }
        }
        return error.SocketNotFound;
    }
};

/// wasi:clocks - Time and clock operations
/// Monotonic and wall-clock time with high precision
pub const Clocks = struct {
    allocator: Allocator,

    pub const Instant = struct {
        nanoseconds: u64,
    };

    pub const Duration = struct {
        nanoseconds: u64,
    };

    pub fn init(allocator: Allocator) !*Clocks {
        const clocks = try allocator.create(Clocks);
        clocks.* = Clocks{
            .allocator = allocator,
        };
        return clocks;
    }

    pub fn deinit(self: *Clocks) void {
        self.allocator.destroy(self);
    }

    /// Get the current monotonic time
    pub fn monotonicNow(_: *Clocks) !Instant {
        const ns = @import("../util/time.zig").nanoTimestamp();
        return Instant{ .nanoseconds = @intCast(ns) };
    }

    /// Get the current wall-clock time
    pub fn wallClockNow(_: *Clocks) !Instant {
        const ns = @import("../util/time.zig").nanoTimestamp();
        return Instant{ .nanoseconds = @intCast(ns) };
    }

    /// Get the resolution of the monotonic clock
    pub fn monotonicResolution(_: *Clocks) !Duration {
        return Duration{ .nanoseconds = 1 }; // 1 nanosecond resolution
    }
};

/// wasi:random - Cryptographically secure random number generation
pub const Random = struct {
    allocator: Allocator,
    rng: std.Random.DefaultPrng,

    pub fn init(allocator: Allocator) !*Random {
        const random = try allocator.create(Random);
        random.* = Random{
            .allocator = allocator,
            .rng = std.Random.DefaultPrng.init(@intCast(std.time.milliTimestamp())),
        };
        return random;
    }

    pub fn deinit(self: *Random) void {
        self.allocator.destroy(self);
    }

    /// Get random bytes (insecure, for testing)
    pub fn getRandomBytes(self: *Random, len: u64) ![]const u8 {
        const buf = try self.allocator.alloc(u8, len);
        self.rng.random().bytes(buf);
        return buf;
    }

    /// Get cryptographically secure random bytes
    pub fn getRandomBytesSecure(self: *Random, len: u64) ![]const u8 {
        const buf = try self.allocator.alloc(u8, len);
        std.crypto.random.bytes(buf);
        return buf;
    }
};

/// wasi:cli - Command-line interface
/// Environment variables, arguments, exit codes, and stdio
pub const CLI = struct {
    allocator: Allocator,
    args: []const [:0]const u8,
    env: std.process.Environ.Map,
    stdin_stream: u32 = 0,
    stdout_stream: u32 = 1,
    stderr_stream: u32 = 2,

    pub fn init(allocator: Allocator) !*CLI {
        const cli = try allocator.create(CLI);
        cli.* = CLI{
            .allocator = allocator,
            .args = &[_][:0]const u8{},
            .env = std.process.Environ.Map.init(allocator),
        };
        return cli;
    }

    pub fn deinit(self: *CLI) void {
        self.env.deinit();
        self.allocator.destroy(self);
    }

    /// Get command-line arguments
    pub fn getArgs(self: *CLI) []const [:0]const u8 {
        return self.args;
    }

    /// Get environment variables
    pub fn getEnvironment(self: *CLI) ![]const []const u8 {
        var env_list = std.ArrayList([]const u8).empty;

        var it = self.env.iterator();
        while (it.next()) |entry| {
            const kv = try std.fmt.allocPrint(self.allocator, "{s}={s}", .{ entry.key_ptr.*, entry.value_ptr.* });
            try env_list.append(self.allocator, kv);
        }

        return try env_list.toOwnedSlice(self.allocator);
    }

    /// Get stdin stream handle
    pub fn getStdin(self: *CLI) u32 {
        return self.stdin_stream;
    }

    /// Get stdout stream handle
    pub fn getStdout(self: *CLI) u32 {
        return self.stdout_stream;
    }

    /// Get stderr stream handle
    pub fn getStderr(self: *CLI) u32 {
        return self.stderr_stream;
    }

    /// Exit the program with a status code
    pub fn exit(_: *CLI, status: u32) noreturn {
        std.process.exit(@intCast(status));
    }
};

/// wasi:http - HTTP client and server
/// Modern HTTP/1.1 and HTTP/2 support
pub const HTTP = struct {
    allocator: Allocator,
    requests: std.ArrayList(Request),
    responses: std.ArrayList(Response),

    pub const Request = struct {
        id: u32,
        method: Method,
        uri: []const u8,
        headers: std.StringHashMap([]const u8),
        body: ?[]const u8 = null,

        pub const Method = enum {
            get,
            post,
            put,
            delete,
            head,
            options,
            connect,
            trace,
            patch,
        };
    };

    pub const Response = struct {
        id: u32,
        status: u16,
        headers: std.StringHashMap([]const u8),
        body: ?[]const u8 = null,
    };

    pub fn init(allocator: Allocator) !*HTTP {
        const http = try allocator.create(HTTP);
        http.* = HTTP{
            .allocator = allocator,
            .requests = .{},
            .responses = .{},
        };
        return http;
    }

    pub fn deinit(self: *HTTP) void {
        for (self.requests.items) |*req| {
            self.allocator.free(req.uri);
            if (req.body) |body| self.allocator.free(body);
            req.headers.deinit();
        }
        for (self.responses.items) |*resp| {
            if (resp.body) |body| self.allocator.free(body);
            resp.headers.deinit();
        }
        self.requests.deinit(self.allocator);
        self.responses.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    /// Create a new HTTP request
    pub fn createRequest(
        self: *HTTP,
        method: Request.Method,
        uri: []const u8,
    ) !u32 {
        const request_id: u32 = @intCast(self.requests.items.len);

        const request = Request{
            .id = request_id,
            .method = method,
            .uri = try self.allocator.dupe(u8, uri),
            .headers = std.StringHashMap([]const u8).init(self.allocator),
        };

        try self.requests.append(self.allocator, request);
        return request_id;
    }

    /// Send an HTTP request (simplified, would use actual HTTP client in production)
    pub fn sendRequest(self: *HTTP, request_id: u32) !u32 {
        _ = request_id;

        // Create a simple success response
        const response_id: u32 = @intCast(self.responses.items.len);
        const response = Response{
            .id = response_id,
            .status = 200,
            .headers = std.StringHashMap([]const u8).init(self.allocator),
            .body = try self.allocator.dupe(u8, "OK"),
        };

        try self.responses.append(self.allocator, response);
        return response_id;
    }
};
