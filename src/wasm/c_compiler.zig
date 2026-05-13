const std = @import("std");
const Io = std.Io;
const cwd = Io.Dir.cwd;
const time = @import("../util/time.zig");

pub fn compileCToWasm(allocator: std.mem.Allocator, io: std.Io, c_content: []const u8) ![]u8 {
    const nowt = time.secondTimestamp();
    const tmp_dir = std.Io.Dir.cwd();

    const tmp_c_path = try std.fmt.allocPrint(allocator, "/tmp/wart_temp_{d}.c", .{nowt});
    defer allocator.free(tmp_c_path);

    const tmp_wasm_path = try std.fmt.allocPrint(allocator, "/tmp/wart_temp_{d}.wasm", .{nowt});
    defer allocator.free(tmp_wasm_path);

    const c_file = try tmp_dir.createFile(io, tmp_c_path, .{});
    defer {
        c_file.close(io);
        tmp_dir.deleteFile(io, tmp_c_path) catch {};
    }
    try c_file.writeStreamingAll(io, c_content);

    const compilers = [_][]const []const u8{
        &[_][]const u8{
            "/opt/wasi-sdk/bin/clang",
            "--target=wasm32-wasi",
            "-O2",
            "-nostdlib",
            "-Wl,--no-entry",
            "-Wl,--export-all",
            tmp_c_path,
            "-o",
            tmp_wasm_path,
        },
        &[_][]const u8{
            "clang",
            "--target=wasm32-wasi",
            "-O2",
            "-nostdlib",
            "-Wl,--no-entry",
            "-Wl,--export-all",
            tmp_c_path,
            "-o",
            tmp_wasm_path,
        },
        &[_][]const u8{
            "zig",
            "cc",
            "-target",
            "wasm32-wasi",
            "-nostdlib",
            "-Wl,--no-entry",
            "-Wl,--export=run",
            tmp_c_path,
            "-o",
            tmp_wasm_path,
        },
        &[_][]const u8{
            "zig",
            "cc",
            "-target",
            "wasm32-wasi",
            "-nostdlib",
            "-Wl,--no-entry",
            "-Wl,--export=main",
            tmp_c_path,
            "-o",
            tmp_wasm_path,
        },
        &[_][]const u8{
            "zig",
            "cc",
            "-target",
            "wasm32-wasi",
            "-nostdlib",
            "-Wl,--no-entry",
            tmp_c_path,
            "-o",
            tmp_wasm_path,
        },
    };

    var last_error: ?[]const u8 = null;
    defer if (last_error) |err| allocator.free(err);

    for (compilers) |compiler_args| {
        const result = std.process.run(allocator, io, .{
            .argv = compiler_args,
        }) catch |err| {
            if (err == error.FileNotFound) {
                continue;
            }
            return err;
        };
        defer allocator.free(result.stdout);
        defer {
            if (last_error) |err| allocator.free(err);
            last_error = null;
        }

        if (result.term == .exited and result.term.exited == 0) {
            const wasm_bytes = tmp_dir.readFileAlloc(io, tmp_wasm_path, allocator, .limited(1024 * 1024 * 10)) catch |err| {
                return err;
            };
            tmp_dir.deleteFile(io, tmp_wasm_path) catch {};
            return wasm_bytes;
        }

        last_error = try allocator.dupe(u8, result.stderr);
    }

    if (last_error) |err| {
        std.debug.print("C compilation error:\n{s}\n", .{err});
    } else {
        std.debug.print("Error: No suitable C to WASM compiler found.\n", .{});
        std.debug.print("Please install one of:\n", .{});
        std.debug.print("  - WASI SDK: https://github.com/WebAssembly/wasi-sdk\n", .{});
        std.debug.print("  - Zig: https://ziglang.org/\n", .{});
    }

    return error.CompilationFailed;
}

pub fn compileCppToWasm(allocator: std.mem.Allocator, io: std.Io, cpp_content: []const u8) ![]u8 {
    const tmp_dir = std.Io.Dir.cwd();
    const nowt = time.secondTimestamp();

    const tmp_cpp_path = try std.fmt.allocPrint(allocator, "/tmp/wart_temp_{d}.cpp", .{nowt});
    defer allocator.free(tmp_cpp_path);

    const tmp_wasm_path = try std.fmt.allocPrint(allocator, "/tmp/wart_temp_{d}.wasm", .{nowt});
    defer allocator.free(tmp_wasm_path);

    const cpp_file = try tmp_dir.createFile(io, tmp_cpp_path, .{});
    defer {
        cpp_file.close(io);
        tmp_dir.deleteFile(io, tmp_cpp_path) catch {};
    }
    try cpp_file.writeStreamingAll(io, cpp_content);

    const compilers = [_][]const []const u8{
        &[_][]const u8{
            "/opt/wasi-sdk/bin/clang++",
            "--target=wasm32-wasi",
            "-O2",
            "-nostdlib",
            "-Wl,--no-entry",
            "-Wl,--export-all",
            tmp_cpp_path,
            "-o",
            tmp_wasm_path,
        },
        &[_][]const u8{
            "clang++",
            "--target=wasm32-wasi",
            "-O2",
            "-nostdlib",
            "-Wl,--no-entry",
            "-Wl,--export-all",
            tmp_cpp_path,
            "-o",
            tmp_wasm_path,
        },
        &[_][]const u8{
            "zig",
            "c++",
            "-target",
            "wasm32-wasi",
            "-nostdlib",
            "-Wl,--no-entry",
            "-Wl,--export=run",
            tmp_cpp_path,
            "-o",
            tmp_wasm_path,
        },
        &[_][]const u8{
            "zig",
            "c++",
            "-target",
            "wasm32-wasi",
            "-nostdlib",
            "-Wl,--no-entry",
            "-Wl,--export=main",
            tmp_cpp_path,
            "-o",
            tmp_wasm_path,
        },
        &[_][]const u8{
            "zig",
            "c++",
            "-target",
            "wasm32-wasi",
            "-nostdlib",
            "-Wl,--no-entry",
            tmp_cpp_path,
            "-o",
            tmp_wasm_path,
        },
    };

    var last_error: ?[]const u8 = null;
    defer if (last_error) |err| allocator.free(err);

    for (compilers) |compiler_args| {
        const result = std.process.run(
            allocator,
            io,
            .{
                .argv = compiler_args,
            },
        ) catch |err| {
            if (err == error.FileNotFound) {
                continue;
            }
            return err;
        };
        defer allocator.free(result.stdout);
        defer {
            if (last_error) |err| allocator.free(err);
            last_error = null;
        }

        if (result.term == .exited and result.term.exited == 0) {
            const wasm_bytes = tmp_dir.readFileAlloc(io, tmp_wasm_path, allocator, .limited(1024 * 1024 * 10)) catch |err| {
                return err;
            };
            tmp_dir.deleteFile(io, tmp_wasm_path) catch {};
            return wasm_bytes;
        }

        last_error = try allocator.dupe(u8, result.stderr);
    }

    if (last_error) |err| {
        std.debug.print("C++ compilation error:\n{s}\n", .{err});
    } else {
        std.debug.print("Error: No suitable C++ to WASM compiler found.\n", .{});
        std.debug.print("Please install one of:\n", .{});
        std.debug.print("  - WASI SDK: https://github.com/WebAssembly/wasi-sdk\n", .{});
        std.debug.print("  - Zig: https://ziglang.org/\n", .{});
    }

    return error.CompilationFailed;
}
