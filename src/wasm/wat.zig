const std = @import("std");
const time = @import("../util/time.zig");

pub fn convertWatToWasm(allocator: std.mem.Allocator, io: std.Io, wat_content: []const u8) ![]u8 {
    const tmp_dir = std.Io.Dir.cwd();
    const nowt = time.secondTimestamp();

    const tmp_wat_path = try std.fmt.allocPrint(allocator, "/tmp/wart_temp_{d}.wat", .{nowt});
    defer allocator.free(tmp_wat_path);

    const tmp_wasm_path = try std.fmt.allocPrint(allocator, "/tmp/wart_temp_{d}.wasm", .{nowt});
    defer allocator.free(tmp_wasm_path);

    const wat_file = try tmp_dir.createFile(io, tmp_wat_path, .{});
    defer {
        wat_file.close(io);
        tmp_dir.deleteFile(io, tmp_wat_path) catch {};
    }
    try wat_file.writeStreamingAll(io, wat_content);

    const result = std.process.run(allocator, io, .{
        .argv = &[_][]const u8{ "wat2wasm", tmp_wat_path, "-o", tmp_wasm_path },
    }) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("Error: wat2wasm not found. Install WABT tools:\n", .{});
            std.debug.print("  brew install wabt  (macOS)\n", .{});
            std.debug.print("  apt install wabt   (Linux)\n", .{});
            return error.Wat2WasmNotFound;
        }
        return err;
    };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term != .exited or result.term.exited != 0) {
        std.debug.print("wat2wasm error: {s}\n", .{result.stderr});
        return error.Wat2WasmFailed;
    }

    const wasm_bytes = tmp_dir.readFileAlloc(io, tmp_wasm_path, allocator, .limited(1024 * 1024 * 10)) catch |err| {
        return err;
    };
    errdefer allocator.free(wasm_bytes);

    tmp_dir.deleteFile(io, tmp_wasm_path) catch {};

    return wasm_bytes;
}
