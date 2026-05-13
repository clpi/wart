const std = @import("std");
const WIT = @This();
const Array: fn (comptime type) type = std.ArrayList;
const timestamp = std.time.timestamp;
const Allocator: type = std.mem.Allocator;
const Functions: type = Array(Component.Function);
const Components: type = Array(Component);
const Interfaces: type = Array(Component.Interface);
const Io: type = std.Io;
const json = std.json;

allocator: Allocator,
io: Io,
components: Components,

pub const Component: type = struct {
    name: []const u8,
    interfaces: Interfaces,

    pub const Function: type = struct {
        name: []const u8,
        params: []Type,
        returns: ?Type,
        is_async: bool = false,

        pub fn init(name: []const u8, params: []Type, returns: ?Type, is_async: bool) Function {
            return .{
                .name = name,
                .params = params,
                .returns = returns,
                .is_async = is_async,
            };
        }
    };

    pub const Interface: type = struct {
        name: []const u8,
        functions: Functions,

        pub fn init(name: []const u8, functions: Functions) Interface {
            return .{
                .name = name,
                .functions = functions,
            };
        }

        pub fn deinit(self: *@This()) void {
            self.functions.deinit();
        }

        pub fn appendFunction(self: *Interface, func: Function) !void {
            try self.appendFunction(func);
        }
    };

    /// Component instantiation with interface binding
    pub fn init(wit: *WIT, data: []const u8) !*Component {
        _ = data;
        const component = try wit.allocator.create(Component);
        component.* = .{ .name = try wit.allocator.dupe(u8, "test-component"), .interfaces = .init(wit.allocator) };
        // Add sample interface
        var interface = .init(try wit.allocator.dupe(u8, "test-interface"), .init(wit.allocator));
        try interface.appendFunction(.init(try wit.allocator.dupe(u8, "async-test"), &[_]Type{}, .string, true));
        try component.appendInterface(interface);
        try wit.appendComponent(component.*);
        return component;
    }

    pub fn deinit(self: *@This()) void {
        inline for (self.interfaces.items) |*interface|
            interface.deinit();
        self.interfaces.deinit();
    }

    pub fn appendInterface(self: *Component, interface: Interface) !void {
        try self.interfaces.append(interface);
    }
};

pub const Type: type = union(enum(u4)) {
    u8,
    u16,
    u32,
    u64,
    i8,
    i16,
    i32,
    i64,
    f32,
    f64,
    bool,
    string,
    list: *Type,
    record: []Field,
    variant: []Case,

    pub const Field: type = struct {
        name: []const u8,
        type: Type,

        pub inline fn init(name: []const u8, @"type": Type) @This() {
            return .{ .name = name, .type = @"type" };
        }
    };

    pub const Case: type = struct {
        name: []const u8,
        type: ?Type,

        pub inline fn init(name: []const u8, @"type": Type) @This() {
            return .{ .name = name, .type = @"type" };
        }
    };
};

pub fn init(allocator: std.mem.Allocator, io: std.Io) !WIT {
    return .{
        .allocator = allocator,
        .io = io,
        .components = .init(allocator),
    };
}

pub fn deinit(self: *WIT) void {
    inline for (self.components.items) |*component|
        component.deinit();
    self.components.deinit();
}

pub fn appendComponent(self: *WIT, component: Component) !void {
    try self.components.append(component);
}

pub fn err(code: i32) anyerror {
    return switch (code) {
        1 => .Timeout,
        else => .AsyncError,
    };
}

/// Async function call with future/promise support
pub const Future: type = struct {
    result: ?[]u8 = null,
    completed: bool = false,
    error_code: ?i32 = null,

    pub fn await(self: *Future) anyerror![]u8 {
        while (!self.completed) : (std.Thread.yield()) {}
        if (self.error_code) |code|
            return err(code);
        return self.result orelse .NoResult;
    }

    pub fn complete(self: *Future, result: []u8) void {
        self.result = result;
        self.completed = true;
    }

    pub fn fail(self: *Future, code: i32) void {
        self.error_code = code;
        self.completed = true;
    }
};

/// Call async function and return future
pub fn callAsync(self: *WIT, component: []const u8, interface: []const u8, function: []const u8, args: []const u8) !*Future {
    _ = component;
    _ = interface;
    _ = function;
    _ = args;

    const future = try self.allocator.create(Future);
    future.* = .{};
    // Simulate async operation
    const result = try self.allocator.dupe(u8, "async_result");
    future.complete(result);
    return future;
}

/// Resource management with automatic cleanup
pub const Resource = struct {
    id: u32,
    data: []u8,
    allocator: Allocator,

    pub fn init(wit: *WIT, data: []const u8) !*@This() {
        const res = try wit.allocator.create(@This());
        const now = timestamp() & 0xFFFFFFFF;
        res.* = .{
            .id = @intCast(now),
            .data = try wit.allocator.dupe(u8, data),
            .allocator = wit.allocator,
        };
        return res;
    }

    pub fn deinit(self: *Resource) void {
        self.allocator.free(self.data);
    }
};

pub fn initResource(self: *WIT, data: []const u8) !*Resource {
    return Resource.init(self, data);
}

/// Component instantiation with interface binding
pub fn initComponent(self: *WIT, wasm_bytes: []const u8) !*Component {
    _ = wasm_bytes;
    const component = try self.allocator.create(Component);
    component.* = .{
        .name = try self.allocator.dupe(u8, "test-component"),
        .interfaces = .init(self.allocator),
    };

    // Add sample interface
    var interface: Component.Interface = .init(try self.allocator.dupe(u8, "test-interface"), .init(self.allocator));
    try interface.appendFunction(.init(try self.allocator.dupe(u8, "async-test"), &[_]Type{}, .string, true));
    try component.appendInterface(interface);
    try self.appendComponent(component.*);
    return component;
}

/// Type serialization/deserialization for component model
pub fn serialize(self: *WIT, value: anytype, vtype: Type) ![]u8 {
    _ = vtype;
    return try json.stringifyAlloc(self.allocator, value, .{});
}

pub fn deserialize(self: *WIT, data: []const u8, comptime T: type) !T {
    const parsed = try json.parseFromSlice(T, self.allocator, data, .{});
    defer parsed.deinit();
    return parsed.value;
}
