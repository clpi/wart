const std = @import("std");
const Manifest = @import("manifest.zig");

/// Package creator for WebAssembly packages
/// Creates tar.gz archives compatible with wapm/wasmer registries
pub const Packager = @This();

allocator: std.mem.Allocator,
io: std.Io,
manifest: Manifest,
include_source: bool = false,
verbose: bool = false,

pub const PackageError = error{
    ManifestNotFound,
    ModuleNotFound,
    InvalidManifest,
    ArchiveCreationFailed,
    OutOfMemory,
    FileNotFound,
    AccessDenied,
    PermissionDenied,
    InputOutput,
    Unexpected,
    PathTooLong,
};

pub fn init(allocator: std.mem.Allocator, io: std.Io) !Packager {
    const manifest = Manifest.loadFromCwd(allocator, io) catch |err| {
        return switch (err) {
            error.FileNotFound => PackageError.ManifestNotFound,
            else => PackageError.InvalidManifest,
        };
    };

    return .{
        .allocator = allocator,
        .io = io,
        .manifest = manifest,
    };
}

pub fn deinit(self: *Packager) void {
    self.manifest.deinit();
}

/// File entry for the package
pub const FileEntry = struct {
    path: []const u8,
    content: []const u8,
    is_binary: bool = false,
};

/// Collect all files to be included in the package
pub fn collectFiles(self: *Packager) !std.ArrayListUnmanaged(FileEntry) {
    const io = self.io;
    var files = std.ArrayListUnmanaged(FileEntry).empty;
    errdefer files.deinit(self.allocator);

    const manifest_name = "wart.toml";
    const manifest_content = std.Io.Dir.cwd().readFileAlloc(io, manifest_name, self.allocator, .limited(1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return err,
        else => return err,
    };
    try files.append(self.allocator, .{ .path = manifest_name, .content = manifest_content });

    // Include README if exists
    if (std.Io.Dir.cwd().readFileAlloc(io, "README.md", self.allocator, .limited(1024 * 1024))) |content| {
        try files.append(self.allocator, .{ .path = "README.md", .content = content });
    } else |_| {}

    // Include LICENSE if exists
    if (std.Io.Dir.cwd().readFileAlloc(io, "LICENSE", self.allocator, .limited(1024 * 1024))) |content| {
        try files.append(self.allocator, .{ .path = "LICENSE", .content = content });
    } else |_| {}

    // Include all module sources (.wasm files)
    for (self.manifest.modules) |mod| {
        if (std.Io.Dir.cwd().readFileAlloc(io, mod.source, self.allocator, .limited(50 * 1024 * 1024))) |content| {
            try files.append(self.allocator, .{ .path = mod.source, .content = content, .is_binary = true });
        } else |err| {
            if (self.verbose) {
                std.debug.print("Warning: Could not read module source '{s}': {s}\n", .{ mod.source, @errorName(err) });
            }
        }
    }

    // Include source files if requested
    if (self.include_source) {
        try self.collectSourceFiles(&files, "src");
    }

    return files;
}

fn collectSourceFiles(self: *Packager, files: *std.ArrayListUnmanaged(FileEntry), dir_path: []const u8) !void {
    const io = self.io;
    var dir = std.Io.Dir.cwd().openDir(io, dir_path, .{ .iterate = true }) catch return;
    defer dir.close(io);

    var iter = dir.iterate();
    while (try iter.next(io)) |entry| {
        const full_path = try std.fs.path.join(self.allocator, &[_][]const u8{ dir_path, entry.name });
        defer self.allocator.free(full_path);

        switch (entry.kind) {
            .file => {
                // Include common source file types
                const ext = std.fs.path.extension(entry.name);
                if (std.mem.eql(u8, ext, ".zig") or
                    std.mem.eql(u8, ext, ".c") or
                    std.mem.eql(u8, ext, ".h") or
                    std.mem.eql(u8, ext, ".cpp") or
                    std.mem.eql(u8, ext, ".rs") or
                    std.mem.eql(u8, ext, ".wat") or
                    std.mem.eql(u8, ext, ".wit"))
                {
                    if (std.Io.Dir.cwd().readFileAlloc(io, full_path, self.allocator, .limited(10 * 1024 * 1024))) |content| {
                        const stored_path = try self.allocator.dupe(u8, full_path);
                        try files.append(self.allocator, .{ .path = stored_path, .content = content });
                    } else |_| {}
                }
            },
            .directory => {
                // Skip hidden directories and common build artifacts
                if (entry.name[0] != '.' and
                    !std.mem.eql(u8, entry.name, "target") and
                    !std.mem.eql(u8, entry.name, "zig-out") and
                    !std.mem.eql(u8, entry.name, "zig-cache") and
                    !std.mem.eql(u8, entry.name, "node_modules"))
                {
                    try self.collectSourceFiles(files, full_path);
                }
            },
            else => {},
        }
    }
}

/// Package info for display
pub const PackageInfo = struct {
    name: []const u8,
    version: []const u8,
    file_count: usize,
    total_size: usize,
    output_path: []const u8,
};

/// Create the package archive
/// Returns info about the created package
pub fn createPackage(self: *Packager, output_path: ?[]const u8) !PackageInfo {
    const io = self.io;
    var files = try self.collectFiles();
    defer {
        for (files.items) |f| {
            self.allocator.free(@constCast(f.content));
            // Free the path if it was allocated (source files have allocated paths)
            if (self.include_source and
                !std.mem.eql(u8, f.path, "wart.toml") and
                !std.mem.eql(u8, f.path, "README.md") and !std.mem.eql(u8, f.path, "LICENSE"))
            {
                self.allocator.free(@constCast(f.path));
            }
        }
        files.deinit(self.allocator);
    }

    // Determine output filename
    var name_buf: [256]u8 = undefined;
    const out_path = output_path orelse blk: {
        const formatted = std.fmt.bufPrint(&name_buf, "{s}-{s}.tar.gz", .{
            self.manifest.package.name,
            self.manifest.package.version,
        }) catch "package.tar.gz";
        break :blk formatted;
    };

    // Calculate total size
    var total_size: usize = 0;
    for (files.items) |f| {
        total_size += f.content.len;
    }

    // Create tar archive in memory then gzip it
    const tar_data = try createTarArchive(self.allocator, files.items);
    defer self.allocator.free(tar_data);

    // Write the tar (we'll use .tar extension, gzip would require zlib)
    // For simplicity, we'll create a .tar file
    const tar_path = blk: {
        if (std.mem.endsWith(u8, out_path, ".gz")) {
            // Remove .gz extension for now
            break :blk out_path[0 .. out_path.len - 3];
        }
        break :blk out_path;
    };

    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = tar_path, .data = tar_data });

    // Duplicate the path string since it may be pointing to a stack buffer
    const output_path_owned = try self.allocator.dupe(u8, tar_path);

    return PackageInfo{
        .name = self.manifest.package.name,
        .version = self.manifest.package.version,
        .file_count = files.items.len,
        .total_size = total_size,
        .output_path = output_path_owned,
    };
}

/// Create a TAR archive from files
fn createTarArchive(allocator: std.mem.Allocator, files: []const FileEntry) ![]u8 {
    var buffer = std.ArrayListUnmanaged(u8).empty;
    errdefer buffer.deinit(allocator);

    for (files) |file| {
        // Create TAR header (512 bytes)
        var header: [512]u8 = [_]u8{0}**512;

        // Name (100 bytes)
        // Name (100 bytes) - validate path length
        if (file.path.len > 100) {
            return error.PathTooLong;
        }
        const name_len = file.path.len;
        @memcpy(header[0..name_len], file.path[0..name_len]);

        // Mode (8 bytes) - 0644 for files
        @memcpy(header[100..107], "0000644");

        // UID (8 bytes)
        @memcpy(header[108..115], "0000000");

        // GID (8 bytes)
        @memcpy(header[116..123], "0000000");

        // Size (12 bytes, octal)
        var size_buf: [12]u8 = undefined;
        const size_str = std.fmt.bufPrint(&size_buf, "{o:0>11}", .{file.content.len}) catch "00000000000";
        @memcpy(header[124..135], size_str[0..11]);

        // Mtime (12 bytes)
        const now = @import("util/time.zig").nanoTimestamp();
        var mtime_buf: [12]u8 = undefined;
        const mtime_str = std.fmt.bufPrint(&mtime_buf, "{o:0>11}", .{@as(u64, @intCast(now))}) catch "00000000000";
        @memcpy(header[136..147], mtime_str[0..11]);

        // Checksum placeholder (8 spaces)
        @memcpy(header[148..156], "        ");

        // Type flag ('0' for regular file)
        header[156] = '0';

        // Calculate checksum
        var checksum: u32 = 0;
        for (header) |byte| {
            checksum += byte;
        }
        var checksum_buf: [8]u8 = undefined;
        const checksum_str = std.fmt.bufPrint(&checksum_buf, "{o:0>6}\x00 ", .{checksum}) catch "000000\x00 ";
        @memcpy(header[148..156], checksum_str[0..8]);

        // Write header
        try buffer.appendSlice(allocator, &header);

        // Write file content
        try buffer.appendSlice(allocator, file.content);

        // Pad to 512-byte boundary
        const padding_needed = (512 - (file.content.len % 512)) % 512;
        if (padding_needed > 0) {
            const padding = try allocator.alloc(u8, padding_needed);
            defer allocator.free(padding);
            @memset(padding, 0);
            try buffer.appendSlice(allocator, padding);
        }
    }

    // Write two empty blocks to end the archive
    const end_blocks = [_]u8{0} ** 1024;
    try buffer.appendSlice(allocator, &end_blocks);

    return buffer.toOwnedSlice(allocator);
}

/// Verify a package can be published
pub fn verifyForPublish(self: *Packager) !void {
    const io = self.io;
    try self.manifest.validate();

    // Check that all module sources exist
    for (self.manifest.modules) |mod| {
        std.Io.Dir.cwd().access(io, mod.source, .{}) catch {
            return PackageError.ModuleNotFound;
        };
    }
}

/// Get package manifest summary for display
pub fn getSummary(self: *const Packager) PackageSummary {
    return .{
        .name = self.manifest.package.name,
        .version = self.manifest.package.version,
        .description = self.manifest.package.description,
        .module_count = self.manifest.modules.len,
        .command_count = self.manifest.commands.len,
        .has_workspace = self.manifest.workspace != null,
    };
}

pub const PackageSummary = struct {
    name: []const u8,
    version: []const u8,
    description: []const u8,
    module_count: usize,
    command_count: usize,
    has_workspace: bool,
};

// Tests
test "packager init with missing manifest" {
    var io_provider = std.Io.Threaded.init(std.testing.allocator, .{});
    defer io_provider.deinit();
    const result = Packager.init(std.testing.allocator, io_provider.io());
    try std.testing.expectError(PackageError.ManifestNotFound, result);
}
