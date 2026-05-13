const common = @import("common.zig");
const run_cmd = @import("run.zig");
const bench_cmd = @import("bench.zig");
const verify_cmd = @import("verify.zig");
const compile_cmd = @import("compile.zig");
const inspect_cmd = @import("inspect.zig");
const completion_cmd = @import("completion.zig");
const config_cmd = @import("config.zig");
const init_cmd = @import("init.zig");
const package_cmd = @import("package.zig");
const build_cmd = @import("build.zig");
const deploy_cmd = @import("deploy.zig");
const shell_cmd = @import("shell.zig");
const version_cmd = @import("version.zig");

pub const Options = struct {
    target: ?common.Command = null,
};

pub fn parse(args: []const [:0]u8) common.CliError!Options {
    if (args.len == 0) return Options{};
    if (args.len > 1) return common.CliError.InvalidArgument;

    const cmd = common.parseCommand(args[0]) orelse return common.CliError.InvalidCommand;
    return Options{ .target = cmd };
}

pub fn run(program_name: []const u8, opts: Options) void {
    if (opts.target) |cmd| {
        switch (cmd) {
            .run => run_cmd.help(program_name),
            .bench => bench_cmd.help(program_name),
            .verify => verify_cmd.help(program_name),
            .compile => compile_cmd.help(program_name),
            .inspect => inspect_cmd.help(program_name),
            .completion => completion_cmd.help(program_name),
            .config => config_cmd.help(program_name),
            .init => init_cmd.help(program_name),
            .package => package_cmd.help(program_name),
            .build => build_cmd.help(program_name),
            .deploy => deploy_cmd.help(program_name),
            .shell => shell_cmd.help(program_name),
            .version => version_cmd.help(program_name),
            .help => runGeneralHelp(program_name),
        }
        return;
    }

    runGeneralHelp(program_name);
}

fn runGeneralHelp(program_name: []const u8) void {
    const print = common.print;
    const Color = common.Color;

    print("{s}wart{s}", .{ Color.bright_cyan, Color.reset }, Color.reset);
    print("Experimental WebAssembly runtime and CLI.", .{}, Color.reset);
    print("", .{}, Color.reset);

    print("Usage:", .{}, Color.reset);
    print("  {s} <module.wasm> [args...]", .{program_name}, Color.reset);
    print("  {s} <command> [options]", .{program_name}, Color.reset);
    print("", .{}, Color.reset);

    print("Commands:", .{}, Color.reset);
    print("  run         Execute a WebAssembly or WAT module", .{}, Color.reset);
    print("  inspect     Inspect a module or show capability metadata", .{}, Color.reset);
    print("  verify      Run the pinned verification harness", .{}, Color.reset);
    print("  bench       Run a workload or a pinned benchmark profile", .{}, Color.reset);
    print("  compile     Compile a module with the AOT pipeline", .{}, Color.reset);
    print("  config      Inspect or initialize local config", .{}, Color.reset);
    print("  init        Generate a starter wart.toml", .{}, Color.reset);
    print("  package     Package and workspace commands", .{}, Color.reset);
    print("  build       Build a package archive", .{}, Color.reset);
    print("  deploy      Publish a package", .{}, Color.reset);
    print("  completion  Emit shell completion scripts", .{}, Color.reset);
    print("  shell       Start the interactive shell (aliases: repl, sh)", .{}, Color.reset);
    print("  version     Print the current version", .{}, Color.reset);
    print("  help        Show command help", .{}, Color.reset);
    print("", .{}, Color.reset);

    print("Global options:", .{}, Color.reset);
    print("  -h, --help         Show help", .{}, Color.reset);
    print("  -v, --version      Show version", .{}, Color.reset);
    print("  -d, --debug        Enable runtime debug logging", .{}, Color.reset);
    print("  -j, --jit          Request JIT execution", .{}, Color.reset);
    print("  -a, --aot          Request AOT execution", .{}, Color.reset);
    print("  -w, --wat          Force WAT parsing", .{}, Color.reset);
    print("  --no-validate      Skip validation", .{}, Color.reset);
    print("  --no-color         Disable colorized output", .{}, Color.reset);
    print("", .{}, Color.reset);

    print("Examples:", .{}, Color.reset);
    print("  {s} examples/simple.wasm", .{program_name}, Color.reset);
    print("  {s} inspect capabilities --format json", .{program_name}, Color.reset);
    print("  {s} verify spec --profile all --output artifacts/spec", .{program_name}, Color.reset);
    print("  {s} bench run --profile core-universal", .{program_name}, Color.reset);
}
