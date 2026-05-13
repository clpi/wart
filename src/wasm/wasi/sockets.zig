const std = @import("std");
const net = std.net;
const posix = std.posix;

/// WASI Preview 2 Sockets Implementation
/// Provides TCP/UDP socket support per wasi:sockets spec
pub const ShutdownHow = enum {
    recv,
    send,
    both,

    fn toC(self: ShutdownHow) c_int {
        return switch (self) {
            .recv => std.c.SHUT.RD,
            .send => std.c.SHUT.WR,
            .both => std.c.SHUT.RDWR,
        };
    }
};

pub const SocketError = error{
    ConnectionRefused,
    NetworkUnreachable,
    AddressInUse,
    AddressNotAvailable,
    Timeout,
    InvalidAddress,
    SocketClosed,
    WouldBlock,
    AlreadyConnected,
    NotConnected,
};

pub const AddressFamily = enum(u8) {
    ipv4 = 0,
    ipv6 = 1,

    pub fn toOsFamily(self: AddressFamily) u32 {
        return switch (self) {
            .ipv4 => 2, // AF_INET
            .ipv6 => 10, // AF_INET6
        };
    }
};

pub const IpAddress = union(AddressFamily) {
    ipv4: [4]u8,
    ipv6: [16]u8,

    pub fn parse(s: []const u8) !IpAddress {
        // Try IPv4 first
        if (std.mem.indexOf(u8, s, ":") == null) {
            var octets: [4]u8 = undefined;
            var iter = std.mem.splitScalar(u8, s, '.');
            var i: usize = 0;
            while (iter.next()) |part| : (i += 1) {
                if (i >= 4) return error.InvalidAddress;
                octets[i] = try std.fmt.parseInt(u8, part, 10);
            }
            if (i != 4) return error.InvalidAddress;
            return IpAddress{ .ipv4 = octets };
        }

        // Parse IPv6
        const addr = try net.Address.parseIp6(s, 0);
        return IpAddress{ .ipv6 = addr.in6.sa.addr };
    }
};

pub const IpSocketAddress = struct {
    address: IpAddress,
    port: u16,

    pub fn format(self: IpSocketAddress, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        switch (self.address) {
            .ipv4 => |octets| {
                try writer.print("{d}.{d}.{d}.{d}:{d}", .{
                    octets[0], octets[1], octets[2], octets[3], self.port,
                });
            },
            .ipv6 => |octets| {
                try writer.print("[", .{});
                var i: usize = 0;
                while (i < 8) : (i += 1) {
                    const word = @as(u16, octets[i * 2]) << 8 | octets[i * 2 + 1];
                    if (i > 0) try writer.print(":", .{});
                    try writer.print("{x}", .{word});
                }
                try writer.print("]:{d}", .{self.port});
            },
        }
    }
};

/// TCP Socket supporting WASI Preview 2 operations
pub const TcpSocket = struct {
    fd: posix.socket_t,
    allocator: std.mem.Allocator,
    family: AddressFamily,
    connected: bool = false,
    listening: bool = false,

    pub fn init(allocator: std.mem.Allocator, family: AddressFamily) !TcpSocket {
        const domain = family.toOsFamily();
        const fd = try posix.socket(domain, posix.SOCK.STREAM, posix.IPPROTO.TCP);

        return TcpSocket{
            .fd = fd,
            .allocator = allocator,
            .family = family,
        };
    }

    pub fn connect(self: *TcpSocket, address: IpSocketAddress) !void {
        if (self.connected) return SocketError.AlreadyConnected;

        const sockaddr = try addressToSockaddr(address);
        try posix.connect(self.fd, &sockaddr.any, sockaddr.getOsSockLen());
        self.connected = true;
    }

    pub fn bind(self: *TcpSocket, address: IpSocketAddress) !void {
        const sockaddr = try addressToSockaddr(address);
        try posix.bind(self.fd, &sockaddr.any, sockaddr.getOsSockLen());
    }

    pub fn listen(self: *TcpSocket, backlog: u31) !void {
        try posix.listen(self.fd, backlog);
        self.listening = true;
    }

    pub fn accept(self: *TcpSocket) !TcpSocket {
        if (!self.listening) return SocketError.NotConnected;

        var addr: posix.sockaddr = undefined;
        var addrlen: posix.socklen_t = @sizeOf(posix.sockaddr);

        const accepted_fd = std.c.accept(self.fd, @ptrCast(&addr), &addrlen);
        if (accepted_fd < 0) return SocketError.SocketClosed;

        return TcpSocket{
            .fd = accepted_fd,
            .allocator = self.allocator,
            .family = self.family,
            .connected = true,
            .listening = false,
        };
    }

    pub fn send(self: *TcpSocket, data: []const u8) !usize {
        if (!self.connected) return SocketError.NotConnected;
        const result = std.c.send(self.fd, data.ptr, data.len, 0);
        if (result < 0) return SocketError.SocketClosed;
        return @intCast(result);
    }

    pub fn receive(self: *TcpSocket, buffer: []u8) !usize {
        if (!self.connected) return SocketError.NotConnected;
        const result = std.c.recv(self.fd, buffer.ptr, buffer.len, 0);
        if (result < 0) return SocketError.SocketClosed;
        return @intCast(result);
    }

    pub fn setNonBlocking(self: *TcpSocket, non_blocking: bool) !void {
        const flags = try posix.fcntl(self.fd, posix.F.GETFL, 0);
        const new_flags = if (non_blocking)
            flags | @as(u32, posix.O.NONBLOCK)
        else
            flags & ~@as(u32, posix.O.NONBLOCK);
        _ = try posix.fcntl(self.fd, posix.F.SETFL, new_flags);
    }

    pub fn setReuseAddr(self: *TcpSocket, reuse: bool) !void {
        const value: c_int = if (reuse) 1 else 0;
        try posix.setsockopt(
            self.fd,
            posix.SOL.SOCKET,
            posix.SO.REUSEADDR,
            std.mem.asBytes(&value),
        );
    }

    pub fn shutdown(self: *TcpSocket, how: ShutdownHow) !void {
        if (std.c.shutdown(self.fd, how.toC()) != 0) return SocketError.SocketClosed;
    }

    pub fn close(self: *TcpSocket) void {
        _ = posix.system.close(self.fd);
        self.connected = false;
        self.listening = false;
    }
};

/// UDP Socket supporting WASI Preview 2 operations
pub const UdpSocket = struct {
    fd: posix.socket_t,
    allocator: std.mem.Allocator,
    family: AddressFamily,
    bound: bool = false,

    pub fn init(allocator: std.mem.Allocator, family: AddressFamily) !UdpSocket {
        const domain = family.toOsFamily();
        const fd = try posix.socket(domain, posix.SOCK.DGRAM, posix.IPPROTO.UDP);

        return UdpSocket{
            .fd = fd,
            .allocator = allocator,
            .family = family,
        };
    }

    pub fn bind(self: *UdpSocket, address: IpSocketAddress) !void {
        const sockaddr = try addressToSockaddr(address);
        try posix.bind(self.fd, &sockaddr.any, sockaddr.getOsSockLen());
        self.bound = true;
    }

    pub fn sendTo(self: *UdpSocket, data: []const u8, dest: IpSocketAddress) !usize {
        const sockaddr = try addressToSockaddr(dest);
        const result = std.c.sendto(self.fd, data.ptr, data.len, 0, &sockaddr.any, sockaddr.getOsSockLen());
        if (result < 0) return SocketError.SocketClosed;
        return @intCast(result);
    }

    pub fn receiveFrom(self: *UdpSocket, buffer: []u8) !struct { usize, IpSocketAddress } {
        var addr: posix.sockaddr = undefined;
        var addrlen: posix.socklen_t = @sizeOf(posix.sockaddr);

        const len = std.c.recvfrom(self.fd, buffer.ptr, buffer.len, 0, @ptrCast(&addr), &addrlen);
        if (len < 0) return SocketError.SocketClosed;
        const ip_addr = try sockaddrToAddress(&addr);

        return .{ @as(usize, @intCast(len)), ip_addr };
    }

    pub fn setNonBlocking(self: *UdpSocket, non_blocking: bool) !void {
        const flags = try posix.fcntl(self.fd, posix.F.GETFL, 0);
        const new_flags = if (non_blocking)
            flags | @as(u32, posix.O.NONBLOCK)
        else
            flags & ~@as(u32, posix.O.NONBLOCK);
        _ = try posix.fcntl(self.fd, posix.F.SETFL, new_flags);
    }

    pub fn setBroadcast(self: *UdpSocket, broadcast: bool) !void {
        const value: c_int = if (broadcast) 1 else 0;
        try posix.setsockopt(
            self.fd,
            posix.SOL.SOCKET,
            posix.SO.BROADCAST,
            std.mem.asBytes(&value),
        );
    }

    pub fn close(self: *UdpSocket) void {
        _ = posix.system.close(self.fd);
        self.bound = false;
    }
};

/// Convert IpSocketAddress to OS sockaddr
fn addressToSockaddr(address: IpSocketAddress) !posix.sockaddr {
    return switch (address.address) {
        .ipv4 => |octets| blk: {
            const addr = posix.sockaddr.in{
                .family = posix.AF.INET,
                .port = std.mem.nativeToBig(u16, address.port),
                .addr = @as(u32, octets[0]) << 24 |
                    @as(u32, octets[1]) << 16 |
                    @as(u32, octets[2]) << 8 |
                    @as(u32, octets[3]),
                .zero = [_]u8{0} ** 8,
            };
            break :blk posix.sockaddr{ .in = addr };
        },
        .ipv6 => |octets| blk: {
            const addr = posix.sockaddr.in6{
                .family = posix.AF.INET6,
                .port = std.mem.nativeToBig(u16, address.port),
                .flowinfo = 0,
                .addr = octets,
                .scope_id = 0,
            };
            break :blk posix.sockaddr{ .in6 = addr };
        },
    };
}

/// Convert OS sockaddr to IpSocketAddress
fn sockaddrToAddress(addr: *const posix.sockaddr) !IpSocketAddress {
    return switch (addr.family) {
        posix.AF.INET => blk: {
            const in = &addr.in;
            const addr_int = in.addr;
            const octets: [4]u8 = .{
                @truncate(addr_int >> 24),
                @truncate(addr_int >> 16),
                @truncate(addr_int >> 8),
                @truncate(addr_int),
            };
            break :blk IpSocketAddress{
                .address = .{ .ipv4 = octets },
                .port = std.mem.bigToNative(u16, in.port),
            };
        },
        posix.AF.INET6 => blk: {
            const in6 = &addr.in6;
            break :blk IpSocketAddress{
                .address = .{ .ipv6 = in6.addr },
                .port = std.mem.bigToNative(u16, in6.port),
            };
        },
        else => SocketError.InvalidAddress,
    };
}

/// Socket Manager for WASI runtime
pub const SocketManager = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    tcp_sockets: std.AutoHashMap(u32, TcpSocket),
    udp_sockets: std.AutoHashMap(u32, UdpSocket),
    next_handle: u32,

    pub fn init(allocator: std.mem.Allocator) !Self {
        return Self{
            .allocator = allocator,
            .tcp_sockets = std.AutoHashMap(u32, TcpSocket).init(allocator),
            .udp_sockets = std.AutoHashMap(u32, UdpSocket).init(allocator),
            .next_handle = 1000, // Start at 1000 to avoid conflicts with file descriptors
        };
    }

    pub fn deinit(self: *Self) void {
        // Close all TCP sockets
        {
            var it = self.tcp_sockets.iterator();
            while (it.next()) |entry| {
                entry.value_ptr.close();
            }
        }
        self.tcp_sockets.deinit();

        // Close all UDP sockets
        {
            var it = self.udp_sockets.iterator();
            while (it.next()) |entry| {
                entry.value_ptr.close();
            }
        }
        self.udp_sockets.deinit();
    }

    pub fn addTcpSocket(self: *Self, socket: TcpSocket) !u32 {
        const handle = self.next_handle;
        self.next_handle += 1;
        try self.tcp_sockets.put(handle, socket);
        return handle;
    }

    pub fn getTcpSocket(self: *Self, handle: u32) ?*TcpSocket {
        return self.tcp_sockets.getPtr(handle);
    }

    pub fn removeTcpSocket(self: *Self, handle: u32) ?TcpSocket {
        return self.tcp_sockets.fetchRemove(handle);
    }

    pub fn addUdpSocket(self: *Self, socket: UdpSocket) !u32 {
        const handle = self.next_handle;
        self.next_handle += 1;
        try self.udp_sockets.put(handle, socket);
        return handle;
    }

    pub fn getUdpSocket(self: *Self, handle: u32) ?*UdpSocket {
        return self.udp_sockets.getPtr(handle);
    }

    pub fn removeUdpSocket(self: *Self, handle: u32) ?UdpSocket {
        return self.udp_sockets.fetchRemove(handle);
    }
};

// Tests
test "IpAddress parse IPv4" {
    const addr = try IpAddress.parse("192.168.1.1");
    try std.testing.expectEqual(AddressFamily.ipv4, std.meta.activeTag(addr));
    try std.testing.expectEqualSlices(u8, &[_]u8{ 192, 168, 1, 1 }, &addr.ipv4);
}

test "TcpSocket creation" {
    const allocator = std.testing.allocator;
    var socket = try TcpSocket.init(allocator, .ipv4);
    defer socket.close();

    try std.testing.expect(socket.fd >= 0);
    try std.testing.expectEqual(false, socket.connected);
}

test "UdpSocket creation" {
    const allocator = std.testing.allocator;
    var socket = try UdpSocket.init(allocator, .ipv4);
    defer socket.close();

    try std.testing.expect(socket.fd >= 0);
    try std.testing.expectEqual(false, socket.bound);
}

test "SocketManager" {
    const allocator = std.testing.allocator;
    var manager = try SocketManager.init(allocator);
    defer manager.deinit();

    const tcp = try TcpSocket.init(allocator, .ipv4);
    const handle = try manager.addTcpSocket(tcp);
    try std.testing.expect(handle >= 1000);

    const retrieved = manager.getTcpSocket(handle);
    try std.testing.expect(retrieved != null);
}
