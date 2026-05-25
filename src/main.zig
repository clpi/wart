const std = @import("std");
const cmd = @import("cmd.zig");
const Io = std.Io;
const Threaded = Io.Threaded;
const testComponentExecution = @import("wasm/component.zig").testComponentExecution;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const io = std.io.getStdOut().writer();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

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
