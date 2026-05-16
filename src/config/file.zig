const std = @import("std");
const builtin = @import("builtin");
const Config = @import("types.zig").Config;

pub const config_filename = "config.toml";
const max_config_file_bytes: usize = 1024 * 1024;

pub fn defaultConfigDir(allocator: std.mem.Allocator) ![]u8 {
    if (builtin.os.tag == .windows) {
        if (try getEnvVarOwnedOrNull(allocator, "APPDATA")) |appdata| {
            defer allocator.free(appdata);
            return try std.fs.path.join(allocator, &[_][]const u8{ appdata, "wart" });
        }

        if (try getEnvVarOwnedOrNull(allocator, "LOCALAPPDATA")) |local_app_data| {
            defer allocator.free(local_app_data);
            return try std.fs.path.join(allocator, &[_][]const u8{ local_app_data, "wart" });
        }

        if (try getEnvVarOwnedOrNull(allocator, "USERPROFILE")) |user_profile| {
            defer allocator.free(user_profile);
            return try std.fs.path.join(allocator, &[_][]const u8{ user_profile, "AppData", "Roaming", "wart" });
        }

        return try allocator.dupe(u8, "wart");
    }

    if (try getEnvVarOwnedOrNull(allocator, "HOME")) |home| {
        defer allocator.free(home);
        return try std.fs.path.join(allocator, &[_][]const u8{ home, ".config", "wart" });
    }

    return try allocator.dupe(u8, ".wart");
}

pub fn defaultConfigFilePath(allocator: std.mem.Allocator) ![]u8 {
    const dir = try defaultConfigDir(allocator);
    defer allocator.free(dir);
    return try std.fs.path.join(allocator, &[_][]const u8{ dir, config_filename });
}

pub fn ensureDefaultConfig(allocator: std.mem.Allocator, io: std.Io) !void {
    const config_path = try defaultConfigFilePath(allocator);
    defer allocator.free(config_path);

    const default_cfg = Config.init(io);
    try ensureConfigFileExists(allocator, io, config_path, default_cfg);
}

pub fn readRawConfig(allocator: std.mem.Allocator, io: std.Io) ![]u8 {
    const config_path = try defaultConfigFilePath(allocator);
    defer allocator.free(config_path);

    const default_cfg = Config.init(io);
    try ensureConfigFileExists(allocator, io, config_path, default_cfg);
    return try std.Io.Dir.cwd().readFileAlloc(io, config_path, allocator, .limited(max_config_file_bytes));
}

/// Load configuration from disk, creating a default config file when missing.
pub fn loadFromDisk(allocator: std.mem.Allocator, io: std.Io) Config {
    var cfg = Config.init(io);
    const config_path = defaultConfigFilePath(allocator) catch return cfg;
    defer allocator.free(config_path);

    ensureConfigFileExists(allocator, io, config_path, cfg) catch return cfg;

    const content = std.Io.Dir.cwd().readFileAlloc(io, config_path, allocator, .limited(max_config_file_bytes)) catch return cfg;
    defer allocator.free(content);

    parseTomlIntoConfig(&cfg, content);
    return cfg;
}

pub fn saveToDisk(allocator: std.mem.Allocator, io: std.Io, cfg: Config) !void {
    const config_path = try defaultConfigFilePath(allocator);
    defer allocator.free(config_path);

    try ensureConfigDir(allocator, io);
    try writeConfigContent(allocator, io, config_path, cfg);
}

pub fn resetConfig(allocator: std.mem.Allocator, io: std.Io) !void {
    const config_path = try defaultConfigFilePath(allocator);
    defer allocator.free(config_path);

    std.Io.Dir.cwd().deleteFile(io, config_path) catch |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    };
}

fn ensureConfigFileExists(
    allocator: std.mem.Allocator,
    io: std.Io,
    config_path: []const u8,
    default_cfg: Config,
) !void {
    if (std.Io.Dir.cwd().access(io, config_path, .{})) |_| {
        return;
    } else |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    }

    try ensureConfigDir(allocator, io);
    try writeConfigContent(allocator, io, config_path, default_cfg);
}

fn ensureConfigDir(allocator: std.mem.Allocator, io: std.Io) !void {
    const config_dir = try defaultConfigDir(allocator);
    defer allocator.free(config_dir);
    try std.Io.Dir.cwd().createDirPath(io, config_dir);
}

fn writeConfigContent(
    allocator: std.mem.Allocator,
    io: std.Io,
    config_path: []const u8,
    cfg: Config,
) !void {
    var allocating_writer = std.Io.Writer.Allocating.init(allocator);
    defer allocating_writer.deinit();

    try cfg.writeToml(&allocating_writer.writer);
    const content = try allocating_writer.toOwnedSlice();
    defer allocator.free(content);

    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = config_path,
        .data = content,
    });
}

fn parseTomlIntoConfig(cfg: *Config, content: []const u8) void {
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        const eq_pos = std.mem.indexOfScalar(u8, trimmed, '=') orelse continue;
        const key = std.mem.trim(u8, trimmed[0..eq_pos], &std.ascii.whitespace);
        var value = std.mem.trim(u8, trimmed[eq_pos + 1 ..], &std.ascii.whitespace);
        value = stripInlineComment(value);
        value = std.mem.trim(u8, value, &std.ascii.whitespace);
        if (value.len == 0) continue;

        cfg.applyKeyValue(key, stripOptionalQuotes(value));
    }
}

fn stripInlineComment(value: []const u8) []const u8 {
    var in_quotes = false;
    var escaped = false;

    for (value, 0..) |char, idx| {
        if (escaped) {
            escaped = false;
            continue;
        }

        if (in_quotes and char == '\\') {
            escaped = true;
            continue;
        }

        if (char == '"') {
            in_quotes = !in_quotes;
            continue;
        }

        if (!in_quotes and char == '#') {
            return value[0..idx];
        }
    }

    return value;
}

fn stripOptionalQuotes(value: []const u8) []const u8 {
    if (value.len >= 2 and value[0] == '"' and value[value.len - 1] == '"') {
        return value[1 .. value.len - 1];
    }

    return value;
}

fn getEnvVarOwnedOrNull(allocator: std.mem.Allocator, name: []const u8) !?[]u8 {
    const name_z = try allocator.dupeZ(u8, name);
    defer allocator.free(name_z);

    const value = std.c.getenv(name_z.ptr) orelse return null;
    return try allocator.dupe(u8, std.mem.span(value));
}

extern "c" fn unsetenv(name: [*:0]const u8) c_int;
extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;

test "defaultConfigDir falls back to .wart if HOME is not set" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;
    const allocator = std.testing.allocator;
    const old_home = std.c.getenv("HOME");

    defer if (old_home) |h| {
        _ = setenv("HOME", h, 1);
    };

    _ = unsetenv("HOME");

    const dir = try defaultConfigDir(allocator);
    defer allocator.free(dir);
    try std.testing.expectEqualStrings(".wart", dir);
}

test "defaultConfigDir uses HOME when set" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;
    const allocator = std.testing.allocator;
    const old_home = std.c.getenv("HOME");

    defer if (old_home) |h| {
        _ = setenv("HOME", h, 1);
    } else {
        _ = unsetenv("HOME");
    };

    _ = setenv("HOME", "/custom/home/path", 1);

    const dir = try defaultConfigDir(allocator);
    defer allocator.free(dir);
    try std.testing.expectEqualStrings("/custom/home/path/.config/wart", dir);
}
