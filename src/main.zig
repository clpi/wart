const std = @import("std");
const cmd = @import("cmd.zig");
const Io = std.Io;
const Threaded = Io.Threaded;
const testComponentExecution = @import("wasm/component.zig").testComponentExecution;

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    // Get command line arguments.
    const args_const = try init.minimal.args.toSlice(init.arena.allocator());
    const args = try init.arena.allocator().alloc([:0]u8, args_const.len);
    for (args, args_const) |*dst, src| {
        dst.* = @constCast(src);
    }

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
