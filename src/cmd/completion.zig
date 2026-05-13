const std = @import("std");
const common = @import("common.zig");
const Color = common.Color;
const print = common.print;
const cwd = std.Io.Dir.cwd;

pub const Shell = enum {
    bash,
    zsh,
    fish,
    powershell,
    elvish,
    nu,
    xonsh,
    tcsh,
};

pub const Options = struct {
    shell: ?Shell = null,
};

pub fn parse(args: []const [:0]u8) common.CliError!Options {
    if (args.len == 0) return Options{};
    if (args.len > 1) return common.CliError.InvalidArgument;
    return Options{ .shell = try parseShell(args[0]) };
}

pub fn run(allocator: std.mem.Allocator, io: std.Io, opts: Options) !void {
    if (opts.shell == null) {
        print("Available shells: bash, zsh, fish, powershell, elvish, nu, xonsh, tcsh", .{}, Color.reset);
        print("Example: wart completion bash > ~/.local/share/bash-completion/completions/wart", .{}, Color.reset);
        return;
    }

    const file_name = switch (opts.shell.?) {
        .bash => "wart.bash",
        .zsh => "wart.zsh",
        .fish => "wart.fish",
        .powershell => "wart.ps1",
        .elvish => "wart.elv",
        .nu => "wart.nu",
        .xonsh => "wart.xsh",
        .tcsh => "wart.tcsh",
    };

    const completion_path = try std.fs.path.join(allocator, &[_][]const u8{ "assets", "completions", file_name });
    defer allocator.free(completion_path);

    const content = try cwd().readFileAlloc(io, completion_path, allocator, .unlimited);

    defer allocator.free(content);
    std.debug.print("{s}", .{content});
}

pub fn help(program_name: []const u8) void {
    print("{s}wart completion{s}", .{ Color.bright_cyan, Color.reset }, Color.reset);
    print("Usage: {s} completion [shell]", .{program_name}, Color.reset);
    print("Shells: bash | zsh | fish | powershell | elvish | nu | xonsh | tcsh", .{}, Color.reset);
}

fn parseShell(arg: []const u8) common.CliError!Shell {
    if (std.ascii.eqlIgnoreCase(arg, "bash")) return .bash;
    if (std.ascii.eqlIgnoreCase(arg, "zsh")) return .zsh;
    if (std.ascii.eqlIgnoreCase(arg, "fish")) return .fish;
    if (std.ascii.eqlIgnoreCase(arg, "powershell") or std.ascii.eqlIgnoreCase(arg, "pwsh")) return .powershell;
    if (std.ascii.eqlIgnoreCase(arg, "elvish")) return .elvish;
    if (std.ascii.eqlIgnoreCase(arg, "nu") or std.ascii.eqlIgnoreCase(arg, "nushell")) return .nu;
    if (std.ascii.eqlIgnoreCase(arg, "xonsh")) return .xonsh;
    if (std.ascii.eqlIgnoreCase(arg, "tcsh")) return .tcsh;
    return common.CliError.UnsupportedShell;
}
