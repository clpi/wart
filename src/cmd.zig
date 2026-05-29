const std = @import("std");
const common = @import("cmd/common.zig");
const config_loader = @import("config.zig");
const help_cmd = @import("cmd/help.zig");
const run_cmd = @import("cmd/run.zig");
const bench_cmd = @import("cmd/bench.zig");
const verify_cmd = @import("cmd/verify.zig");
const completion_cmd = @import("cmd/completion.zig");
const config_cmd = @import("cmd/config.zig");
const init_cmd = @import("cmd/init.zig");
const package_cmd = @import("cmd/package.zig");
const build_cmd = @import("cmd/build.zig");
const deploy_cmd = @import("cmd/deploy.zig");
const compile_cmd = @import("cmd/compile.zig");
const inspect_cmd = @import("cmd/inspect.zig");
const shell_cmd = @import("cmd/shell.zig");
const version_cmd = @import("cmd/version.zig");

pub const common_cmd = common;
pub const bench_module = bench_cmd;
pub const inspect_module = inspect_cmd;
pub const verify_module = verify_cmd;

pub const Command = common.Command;
pub const CliError = common.CliError;
pub const Config = common.Config;
pub const HelpOptions = help_cmd.Options;

pub const CliResult = union(enum) {
    run: run_cmd.Options,
    bench: bench_cmd.Options,
    verify: verify_cmd.Options,
    help: help_cmd.Options,
    version: version_cmd.Options,
    completion: completion_cmd.Options,
    inspect: inspect_cmd.Options,
    config: config_cmd.Options,
    init: init_cmd.Options,
    package: package_cmd.Options,
    build: build_cmd.Options,
    deploy: deploy_cmd.Options,
    compile: compile_cmd.Options,
    shell: shell_cmd.Options,
};

pub fn parseArgs(io: std.Io, args: []const [:0]const u8) CliError!CliResult {
    if (args.len == 0) return CliResult{ .help = .{} };

    var cfg = config_loader.loadFromDisk(std.heap.c_allocator, io);

    var command: ?Command = null;
    var first_positional_index: ?usize = null;

    var i: usize = 0;
    while (i < args.len) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--")) {
            first_positional_index = if (i + 1 <= args.len) i + 1 else args.len;
            break;
        }

        if (command == null) {
            if (std.mem.endsWith(u8, arg, ".wasm") or std.mem.endsWith(u8, arg, ".wat")) {
                command = .run;
                if (first_positional_index == null) {
                    first_positional_index = i;
                }
                i += 1;
                continue;
            }

            if (common.parseCommand(arg)) |detected| {
                command = detected;
                i += 1;
                continue;
            }
        }

        if (arg.len > 0 and arg[0] == '-') {
            if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
                const remaining = if (i + 1 < args.len) args[i + 1 ..] else &[_][:0]const u8{};
                return CliResult{ .help = try help_cmd.parse(remaining) };
            }
            if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--version")) {
                return CliResult{ .version = .{} };
            }

            if (consumeGlobalOption(args, i, &cfg, &command)) |consumed| {
                if (std.mem.eql(u8, arg, "--cfile") or std.mem.eql(u8, arg, "-c") or
                    std.mem.eql(u8, arg, "--cppfile") or std.mem.eql(u8, arg, "-C"))
                {
                    first_positional_index = consumed + 1;
                    break;
                }
                i = consumed + 1;
                continue;
            } else |_| {
                if (command != null) {
                    if (first_positional_index == null)
                        first_positional_index = i;
                    i += 1;
                    continue;
                }
                return CliError.InvalidArgument;
            }
        }

        if (first_positional_index == null)
            first_positional_index = i;
        i += 1;
    }

    if (command == null) {
        if (cfg.bench) command = .bench;
        if (first_positional_index != null)
            command = .run;
        if (command == null) return CliResult{ .help = .{} };
    }

    if (command.? == .bench)
        cfg.bench = true;


    const pos_start = first_positional_index orelse args.len;
    const positional = args[pos_start..];

    switch (command.?) {
        .help => {
            const opts = try help_cmd.parse(positional);
            return CliResult{ .help = opts };
        },
        .shell => {
            return CliResult{ .shell = shell_cmd.parse(cfg, positional) };
        },
        .version => return CliResult{ .version = .{} },
        .completion => {
            const opts = try completion_cmd.parse(positional);
            return CliResult{ .completion = opts };
        },
        .config => {
            const action = try config_cmd.parse(cfg, positional);
            const options = try config_cmd.exec(cfg, action, positional);
            return CliResult{ .config = options };
        },
        .inspect => {
            const options = try inspect_cmd.parse(cfg, positional);
            return CliResult{ .inspect = options };
        },
        .bench => {
            return CliResult{ .bench = try bench_cmd.parse(cfg, positional) };
        },
        .verify => {
            const options = try verify_cmd.parse(cfg, positional);
            return CliResult{ .verify = options };
        },
        .init => {
            const options = try init_cmd.parse(cfg, positional);
            return CliResult{ .init = options };
        },
        .package => {
            const options = try package_cmd.parse(cfg, positional);
            return CliResult{ .package = options };
        },
        .build => {
            const options = try build_cmd.parse(cfg, positional);
            return CliResult{ .build = options };
        },
        .deploy => {
            const options = try deploy_cmd.parse(cfg, positional);
            return CliResult{ .deploy = options };
        },
        .compile => {
            const options = try compile_cmd.parse(cfg, positional);
            return CliResult{ .compile = options };
        },
        .run => {
            const options = try run_cmd.parse(cfg, positional);
            return CliResult{ .run = options };
        },
    }
}

pub fn run(allocator: std.mem.Allocator, io: std.Io, program_path: [:0]const u8, result: CliResult) !void {
    const command_name = blk: {
        const full_name = program_path;
        if (full_name.len == 0) break :blk full_name;
        if (std.mem.lastIndexOfScalar(u8, full_name, '/')) |idx|
            break :blk full_name[idx + 1 ..];
        break :blk full_name;
    };

    switch (result) {
        .help => |opts| help_cmd.run(command_name, opts),
        .version => version_cmd.run(),
        .run => |opts| try run_cmd.run(allocator, io, opts),
        .bench => |opts| try bench_cmd.run(allocator, io, opts),
        .verify => |opts| try verify_cmd.run(allocator, io, opts),
        .completion => |opts| try completion_cmd.run(allocator, io, opts),
        .inspect => |opts| try inspect_cmd.run(allocator, io, opts),
        .config => |opts| try config_cmd.run(allocator, io, opts),
        .init => |opts| try init_cmd.run(allocator, io, opts),
        .package => |opts| try package_cmd.run(allocator, io, opts),
        .build => |opts| try build_cmd.run(allocator, io, opts),
        .deploy => |opts| try deploy_cmd.run(allocator, io, opts),
        .compile => |opts| try compile_cmd.run(allocator, io, opts),
        .shell => |opts| try shell_cmd.run(allocator, io, opts),
    }
}

pub fn printHelp(program_name: []const u8, opts: help_cmd.Options) void {
    help_cmd.run(program_name, opts);
}

fn consumeGlobalOption(args: []const [:0]const u8, idx: usize, cfg: *Config, command_hint: *?Command) CliError!usize {
    const arg = args[idx];

    if (std.mem.eql(u8, arg, "--debug") or std.mem.eql(u8, arg, "-d")) {
        cfg.debug = true;
        return idx;
    }
    if (std.mem.eql(u8, arg, "--jit") or std.mem.eql(u8, arg, "-j")) {
        cfg.jit = true;
        return idx;
    }
    if (std.mem.eql(u8, arg, "--aot") or std.mem.eql(u8, arg, "-a") or std.mem.eql(u8, arg, "--compile")) {
        cfg.aot = true;
        return idx;
    }
    if (std.mem.eql(u8, arg, "--wast") or std.mem.eql(u8, arg, "-w") or std.mem.eql(u8, arg, "--wat")) {
        cfg.wast = true;
        return idx;
    }
    if (std.mem.eql(u8, arg, "--no-validate")) {
        cfg.validate = false;
        return idx;
    }
    if (std.mem.eql(u8, arg, "--bench") or std.mem.eql(u8, arg, "-b")) {
        cfg.bench = true;
        if (command_hint.* == null)
            command_hint.* = .bench;
        return idx;
    }
    if (std.mem.eql(u8, arg, "--function") or std.mem.eql(u8, arg, "-f")) {
        if (idx + 1 >= args.len) return CliError.MissingArgument;
        cfg.function = args[idx + 1];
        return idx + 1;
    }
    if (std.mem.eql(u8, arg, "--output") or std.mem.eql(u8, arg, "-o")) {
        if (idx + 1 >= args.len) return CliError.MissingArgument;
        cfg.aot_output = args[idx + 1];
        return idx + 1;
    }
    if (std.mem.eql(u8, arg, "--dump-objc")) {
        cfg.dump_objc = true;
        return idx;
    }
    if (std.mem.eql(u8, arg, "--cfile") or std.mem.eql(u8, arg, "-c")) {
        if (idx + 1 >= args.len) return CliError.MissingArgument;
        cfg.cfile_path = args[idx + 1];
        return idx + 1;
    }
    if (std.mem.eql(u8, arg, "--cppfile") or std.mem.eql(u8, arg, "-C")) {
        if (idx + 1 >= args.len) return CliError.MissingArgument;
        cfg.cppfile_path = args[idx + 1];
        return idx + 1;
    }
    if (std.mem.eql(u8, arg, "--color")) {
        cfg.color = true;
        return idx;
    }
    if (std.mem.eql(u8, arg, "--no-color")) {
        cfg.color = false;
        return idx;
    }
    if (std.mem.startsWith(u8, arg, "--color=")) {
        const value = arg[8..];
        if (std.mem.eql(u8, value, "true"))
            cfg.color = true;
        if (std.mem.eql(u8, value, "false"))
            cfg.color = false;
         return CliError.InvalidArgument;
    }
    if (std.mem.eql(u8, arg, "--verbose") or std.mem.eql(u8, arg, "-V")) {
        if (idx + 1 >= args.len) return CliError.MissingArgument;
        cfg.verbose = std.fmt.parseInt(u8, args[idx + 1], 10) catch return CliError.InvalidArgument;
        return idx + 1;
    }
    if (std.mem.eql(u8, arg, "--generate-config-file") or std.mem.eql(u8, arg, "-G")) {
        cfg.generate_config = true;
        return idx;
    }

    return CliError.InvalidArgument;
}
