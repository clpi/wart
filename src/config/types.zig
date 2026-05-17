const std = @import("std");

pub const ConfigKeyError = error{
    UnknownKey,
    InvalidValue,
};

pub const persisted_keys = [_][]const u8{
    "debug",
    "validate",
    "jit",
    "aot",
    "bench",
    "wast",
    "dump_objc",
    "color",
    "verbose",
};

/// Global configuration derived from config files and CLI flags.
pub const Config = struct {
    debug: bool = false,
    validate: bool = true,
    help: bool = false,
    jit: bool = false,
    aot: bool = false,
    aot_output: ?[]const u8 = null,
    bench: bool = false,
    wast: bool = false,
    io: std.Io,
    cfile_path: ?[:0]const u8 = null,
    cppfile_path: ?[:0]const u8 = null,
    function: ?[]const u8 = null,
    dump_objc: bool = false,
    version: []const u8 = "0.1.0",
    color: bool = true,
    verbose: u8 = 0,
    generate_config: bool = false,

    pub fn init(io: std.Io) Config {
        return .{ .io = io };
    }

    /// Apply a key/value pair read from a config file.
    pub fn applyKeyValue(self: *Config, key: []const u8, value: []const u8) void {
        self.applyKeyValueStrict(key, value) catch {};
    }

    /// Apply a key/value pair and return an error for unsupported keys or invalid values.
    pub fn applyKeyValueStrict(self: *Config, key: []const u8, value: []const u8) ConfigKeyError!void {
        if (std.mem.eql(u8, key, "debug")) {
            self.debug = parseBool(value) orelse return error.InvalidValue;
        } else if (std.mem.eql(u8, key, "jit")) {
            self.jit = parseBool(value) orelse return error.InvalidValue;
        } else if (std.mem.eql(u8, key, "aot")) {
            self.aot = parseBool(value) orelse return error.InvalidValue;
        } else if (std.mem.eql(u8, key, "bench")) {
            self.bench = parseBool(value) orelse return error.InvalidValue;
        } else if (std.mem.eql(u8, key, "wast") or std.mem.eql(u8, key, "wat")) {
            self.wast = parseBool(value) orelse return error.InvalidValue;
        } else if (std.mem.eql(u8, key, "validate")) {
            self.validate = parseBool(value) orelse return error.InvalidValue;
        } else if (std.mem.eql(u8, key, "dump_objc")) {
            self.dump_objc = parseBool(value) orelse return error.InvalidValue;
        } else if (std.mem.eql(u8, key, "color")) {
            self.color = parseBool(value) orelse return error.InvalidValue;
        } else if (std.mem.eql(u8, key, "verbose")) {
            self.verbose = std.fmt.parseInt(u8, value, 10) catch return error.InvalidValue;
        } else {
            return error.UnknownKey;
        }
    }

    pub fn valueForKey(self: Config, key: []const u8, integer_buffer: []u8) ConfigKeyError![]const u8 {
        if (std.mem.eql(u8, key, "debug")) return boolString(self.debug);
        if (std.mem.eql(u8, key, "validate")) return boolString(self.validate);
        if (std.mem.eql(u8, key, "jit")) return boolString(self.jit);
        if (std.mem.eql(u8, key, "aot")) return boolString(self.aot);
        if (std.mem.eql(u8, key, "bench")) return boolString(self.bench);
        if (std.mem.eql(u8, key, "wast") or std.mem.eql(u8, key, "wat")) return boolString(self.wast);
        if (std.mem.eql(u8, key, "dump_objc")) return boolString(self.dump_objc);
        if (std.mem.eql(u8, key, "color")) return boolString(self.color);
        if (std.mem.eql(u8, key, "verbose")) return std.fmt.bufPrint(integer_buffer, "{d}", .{self.verbose}) catch unreachable;
        return error.UnknownKey;
    }

    pub fn writeToml(self: Config, writer: anytype) !void {
        try writer.writeAll("# wart global configuration\n");
        try writer.writeAll("# CLI flags override these values at runtime.\n\n");
        try writer.print("debug = {}\n", .{self.debug});
        try writer.print("validate = {}\n", .{self.validate});
        try writer.print("jit = {}\n", .{self.jit});
        try writer.print("aot = {}\n", .{self.aot});
        try writer.print("bench = {}\n", .{self.bench});
        try writer.print("wast = {}\n", .{self.wast});
        try writer.print("dump_objc = {}\n", .{self.dump_objc});
        try writer.print("color = {}\n", .{self.color});
        try writer.print("verbose = {d}\n", .{self.verbose});
    }

    fn parseBool(value: []const u8) ?bool {
        if (std.mem.eql(u8, value, "true")) return true;
        if (std.mem.eql(u8, value, "false")) return false;
        return null;
    }

    fn boolString(value: bool) []const u8 {
        return if (value) "true" else "false";
    }
};

test "Config.writeToml correctly formats output" {
    var buffer: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    var writer = fbs.writer();

    // Create a basic Io instance for the config
    const io = std.Io{
        .in = std.io.getStdIn(),
        .out = std.io.getStdOut(),
        .err = std.io.getStdErr(),
    };

    var config = Config.init(io);
    config.debug = true;
    config.validate = false;
    config.jit = true;
    config.aot = false;
    config.bench = true;
    config.wast = false;
    config.dump_objc = true;
    config.color = false;
    config.verbose = 3;

    try config.writeToml(fbs.writer());

    const expected =
        \\# wart global configuration
        \\# CLI flags override these values at runtime.
        \\
        \\debug = true
        \\validate = false
        \\jit = true
        \\aot = false
        \\bench = true
        \\wast = false
        \\dump_objc = true
        \\color = false
        \\verbose = 3
        \\
    ;

    const items = fbs.getWritten();
    try std.testing.expectEqualStrings(expected, items);
}
