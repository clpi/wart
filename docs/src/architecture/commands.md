# CLI Commands

Each command is implemented in `src/cmd/` as a separate module.

## Structure

```zig
// src/cmd/run.zig
const std = @import("std");
const common = @import("common.zig");
const execution = @import("execution.zig");

pub const Options = execution.RunOptions;

pub fn parse(cfg: common.Config, positional: []const [:0]u8) common.CliError!Options {
    // Parse command-specific options
}

pub fn run(allocator: std.mem.Allocator, io: std.Io, opts: Options) !void {
    // Execute the command
}

pub fn help(program_name: []const u8) void {
    // Print help text
}
```

## Command Flow

```
main.zig
    │
    ▼
cmd.parseArgs() ───► CliResult (tagged union)
    │
    ▼
cmd.run() ─────────► Dispatches to cmd/*.zig
    │
    ▼
cmd/run.zig
    │
    ▼
execution.executeRun()
```

## Adding a New Command

1. Create `src/cmd/newcmd.zig`:

```zig
const std = @import("std");
const common = @import("common.zig");
const Color = common.Color;
const print = common.print;

pub const Options = struct {
    // Command-specific options
    config: common.Config,
};

pub fn parse(cfg: common.Config, positional: []const [:0]u8) common.CliError!Options {
    // Parse options
    return Options{ .config = cfg };
}

pub fn run(allocator: std.mem.Allocator, io: std.Io, opts: Options) !void {
    // Execute
}

pub fn help(program_name: []const u8) void {
    print("{s}wart newcmd{s}", .{ Color.bright_cyan, Color.reset }, Color.reset);
}
```

2. Register in `src/cmd/common.zig`:

```zig
pub const Command = enum {
    // ...existing...
    newcmd,
};
```

3. Add to `src/cmd.zig`:

```zig
const newcmd_cmd = @import("cmd/newcmd.zig");

pub const CliResult = union(enum) {
    // ...existing...
    newcmd: newcmd_cmd.Options,
};

// In parseArgs:
if (common.commandFromWord(arg)) |detected| {
    // automatically handles the new command
}

// In run:
.newcmd => |opts| try newcmd_cmd.run(allocator, io, opts),
```
