const std = @import("std");
const cmd = @import("cmd.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const io = init.io;

    const args = try init.minimal.args.toSlice(allocator);

    // Parse arguments (skip program name)
    const result = cmd.parseArgs(io, args[1..]) catch |err| {
        switch (err) {
            cmd.CliError.InvalidCommand => {
                cmd.printHelp(args[0], .{});
                return;
            },
            cmd.CliError.MissingArgument => {
                cmd.printHelp(args[0], .{});
                return;
            },
            cmd.CliError.InvalidArgument => {
                cmd.printHelp(args[0], .{});
                return;
            },
            cmd.CliError.UnsupportedShell => {
                std.debug.print("Unsupported shell for completions\n", .{});
                return;
            },
        }
    };

    // Execute the command
    try cmd.run(allocator, io, args[0], result);
}
