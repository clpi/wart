const std = @import("std");

/// wart project manifest (wart.toml) parser and handler
/// Compatible with wapm manifest format for packaging
pub const Manifest = @This();

/// Package metadata
pub const Package = struct {
    name: []const u8 = "",
    version: []const u8 = "0.1.0",
    description: []const u8 = "",
    license: []const u8 = "MIT",
    readme: ?[]const u8 = null,
    repository: ?[]const u8 = null,
    homepage: ?[]const u8 = null,
    documentation: ?[]const u8 = null,
    keywords: []const []const u8 = &[_][]const u8{},
    categories: []const []const u8 = &[_][]const u8{},
    authors: []const Author = &[_]Author{},
    private: bool = false,

    pub const Author = struct {
        name: []const u8,
        email: ?[]const u8 = null,
    };
};

/// WebAssembly module definition
pub const Module = struct {
    name: []const u8,
    source: []const u8,
    abi: Abi = .wasi,
    interfaces: ?[]const u8 = null,
    bindings: ?Bindings = null,

    pub const Abi = enum {
        wasi,
        emscripten,
        none,
        wasi_cli_command,
        wasi_http_proxy,
        custom,
    };

    pub const Bindings = struct {
        wai_version: ?[]const u8 = null,
        exports: ?[]const u8 = null,
        imports: ?[]const u8 = null,
    };
};

/// Command definition (CLI entry point)
pub const Command = struct {
    name: []const u8,
    module: []const u8,
    main_args: ?[]const u8 = null,
    runner: ?[]const u8 = null,
    annotations: ?Annotations = null,

    pub const Annotations = struct {
        wasi: ?WasiAnnotations = null,
        file: ?[]const FileMapping = null,
    };

    pub const WasiAnnotations = struct {
        stdin: ?[]const u8 = null,
        stdout: ?[]const u8 = null,
        stderr: ?[]const u8 = null,
        env: ?[]const []const u8 = null,
        main_args: ?[]const u8 = null,
        atom: ?[]const u8 = null,
    };

    pub const FileMapping = struct {
        host: []const u8,
        guest: []const u8,
    };
};

/// Filesystem mappings
pub const Filesystem = struct {
    mappings: []const Mapping = &[_]Mapping{},

    pub const Mapping = struct {
        host: []const u8,
        guest: []const u8,
    };
};

/// Workspace configuration
pub const Workspace = struct {
    members: []const []const u8 = &[_][]const u8{},
    default_members: []const []const u8 = &[_][]const u8{},
    exclude: []const []const u8 = &[_][]const u8{},
    resolver: ?[]const u8 = null,
};

/// Component model configuration
pub const Component = struct {
    wit: ?[]const u8 = null,
    world: ?[]const u8 = null,
    target: ?[]const u8 = null,
};

/// Build configuration
pub const Build = struct {
    command: ?[]const u8 = null,
    output: ?[]const u8 = null,
    target: ?[]const u8 = null,
    optimize: ?[]const u8 = null,
    env: []const EnvVar = &[_]EnvVar{},

    pub const EnvVar = struct {
        name: []const u8,
        value: []const u8,
    };
};

/// Dependency specification
pub const Dependency = struct {
    name: []const u8,
    version: ?[]const u8 = null,
    path: ?[]const u8 = null,
    git: ?[]const u8 = null,
    branch: ?[]const u8 = null,
    tag: ?[]const u8 = null,
    registry: ?[]const u8 = null,
    optional: bool = false,
};

/// The complete manifest structure
package: Package = .{},
modules: []const Module = &[_]Module{},
commands: []const Command = &[_]Command{},
filesystem: Filesystem = .{},
workspace: ?Workspace = null,
component: ?Component = null,
build: Build = .{},
dependencies: []const Dependency = &[_]Dependency{},
dev_dependencies: []const Dependency = &[_]Dependency{},

allocator: std.mem.Allocator,
io: std.Io,
raw_content: []const u8 = "",

pub fn init(allocator: std.mem.Allocator, io: std.Io) Manifest {
    return .{
        .allocator = allocator,
        .io = io,
    };
}

pub fn deinit(self: *Manifest) void {
    if (self.raw_content.len > 0) {
        self.allocator.free(self.raw_content);
    }

    // Free allocated slices
    if (self.modules.len > 0) {
        self.allocator.free(self.modules);
    }
    if (self.commands.len > 0) {
        self.allocator.free(self.commands);
    }
    if (self.dependencies.len > 0) {
        self.allocator.free(self.dependencies);
    }
    if (self.filesystem.mappings.len > 0) {
        self.allocator.free(self.filesystem.mappings);
    }
    if (self.workspace) |ws| {
        if (ws.members.len > 0) {
            self.allocator.free(ws.members);
        }
    }
}

/// Load manifest from file
pub fn load(allocator: std.mem.Allocator, io: std.Io, path: []const u8) !Manifest {
    const content = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(1024 * 1024));
    errdefer allocator.free(content);
    return parse(allocator, io, content);
}

/// Load manifest from current directory (prefers wart.toml, falls back to legacy wart.toml)
pub fn loadFromCwd(allocator: std.mem.Allocator, io: std.Io) !Manifest {
    return load(allocator, io, "wart.toml") catch |err| switch (err) {
        error.FileNotFound => load(allocator, io, "wart.toml"),
        else => err,
    };
}

/// Parse TOML content into manifest
pub fn parse(allocator: std.mem.Allocator, io: std.Io, content: []const u8) !Manifest {
    var manifest = Manifest.init(allocator, io);
    manifest.raw_content = content;

    var current_section: Section = .none;
    var current_table_array: TableArray = .none;

    // Lists for collecting items
    var modules_list = std.ArrayListUnmanaged(Module).empty;
    defer modules_list.deinit(allocator);
    var commands_list = std.ArrayListUnmanaged(Command).empty;
    defer commands_list.deinit(allocator);
    var deps_list = std.ArrayListUnmanaged(Dependency).empty;
    defer deps_list.deinit(allocator);
    var members_list = std.ArrayListUnmanaged([]const u8).empty;
    defer members_list.deinit(allocator);
    var fs_mappings = std.ArrayListUnmanaged(Filesystem.Mapping).empty;
    defer fs_mappings.deinit(allocator);

    // Temporary storage for current module/command being parsed
    var current_module: ?Module = null;
    var current_command: ?Command = null;

    var lines = std.mem.splitAny(u8, content, "\n");
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");

        // Skip empty lines and comments
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        // Check for section headers
        if (trimmed[0] == '[') {
            // Save current module/command if any
            if (current_module) |mod| {
                try modules_list.append(allocator, mod);
                current_module = null;
            }
            if (current_command) |cmd| {
                try commands_list.append(allocator, cmd);
                current_command = null;
            }

            // Parse section header
            if (std.mem.startsWith(u8, trimmed, "[[module]]")) {
                current_table_array = .module;
                current_section = .module;
                current_module = Module{ .name = "", .source = "" };
            } else if (std.mem.startsWith(u8, trimmed, "[[command]]")) {
                current_table_array = .command;
                current_section = .command;
                current_command = Command{ .name = "", .module = "" };
            } else if (std.mem.startsWith(u8, trimmed, "[package.authors]")) {
                current_section = .package_authors;
                current_table_array = .none;
            } else if (std.mem.startsWith(u8, trimmed, "[package]")) {
                current_section = .package;
                current_table_array = .none;
            } else if (std.mem.startsWith(u8, trimmed, "[dependencies]")) {
                current_section = .dependencies;
                current_table_array = .none;
            } else if (std.mem.startsWith(u8, trimmed, "[dev-dependencies]") or std.mem.startsWith(u8, trimmed, "[dev_dependencies]")) {
                current_section = .dev_dependencies;
                current_table_array = .none;
            } else if (std.mem.startsWith(u8, trimmed, "[workspace]")) {
                current_section = .workspace;
                current_table_array = .none;
                manifest.workspace = Workspace{};
            } else if (std.mem.startsWith(u8, trimmed, "[component]")) {
                current_section = .component;
                current_table_array = .none;
                manifest.component = Component{};
            } else if (std.mem.startsWith(u8, trimmed, "[build]")) {
                current_section = .build;
                current_table_array = .none;
            } else if (std.mem.startsWith(u8, trimmed, "[fs]")) {
                current_section = .filesystem;
                current_table_array = .none;
            }
            continue;
        }

        // Parse key-value pairs
        if (std.mem.indexOf(u8, trimmed, " = ")) |eq_pos| {
            const key = std.mem.trim(u8, trimmed[0..eq_pos], " \t");
            const value_raw = std.mem.trim(u8, trimmed[eq_pos + 3 ..], " \t");
            const value = parseValue(value_raw);

            switch (current_section) {
                .package => {
                    if (std.mem.eql(u8, key, "name")) {
                        manifest.package.name = value;
                    } else if (std.mem.eql(u8, key, "version")) {
                        manifest.package.version = value;
                    } else if (std.mem.eql(u8, key, "description")) {
                        manifest.package.description = value;
                    } else if (std.mem.eql(u8, key, "license")) {
                        manifest.package.license = value;
                    } else if (std.mem.eql(u8, key, "readme")) {
                        manifest.package.readme = value;
                    } else if (std.mem.eql(u8, key, "repository")) {
                        manifest.package.repository = value;
                    } else if (std.mem.eql(u8, key, "homepage")) {
                        manifest.package.homepage = value;
                    } else if (std.mem.eql(u8, key, "documentation")) {
                        manifest.package.documentation = value;
                    } else if (std.mem.eql(u8, key, "private")) {
                        manifest.package.private = std.mem.eql(u8, value, "true");
                    }
                },
                .module => {
                    if (current_module) |*mod| {
                        if (std.mem.eql(u8, key, "name")) {
                            mod.name = value;
                        } else if (std.mem.eql(u8, key, "source")) {
                            mod.source = value;
                        } else if (std.mem.eql(u8, key, "abi")) {
                            mod.abi = parseAbi(value);
                        } else if (std.mem.eql(u8, key, "interfaces")) {
                            mod.interfaces = value;
                        }
                    }
                },
                .command => {
                    if (current_command) |*cmd| {
                        if (std.mem.eql(u8, key, "name")) {
                            cmd.name = value;
                        } else if (std.mem.eql(u8, key, "module")) {
                            cmd.module = value;
                        } else if (std.mem.eql(u8, key, "runner")) {
                            cmd.runner = value;
                        } else if (std.mem.eql(u8, key, "main_args")) {
                            cmd.main_args = value;
                        }
                    }
                },
                .workspace => {
                    if (manifest.workspace) |*ws| {
                        if (std.mem.eql(u8, key, "members")) {
                            // Parse array
                            const members = try parseArrayInline(allocator, value_raw);
                            ws.members = members;
                        } else if (std.mem.eql(u8, key, "resolver")) {
                            ws.resolver = value;
                        }
                    }
                },
                .component => {
                    if (manifest.component) |*comp| {
                        if (std.mem.eql(u8, key, "wit")) {
                            comp.wit = value;
                        } else if (std.mem.eql(u8, key, "world")) {
                            comp.world = value;
                        } else if (std.mem.eql(u8, key, "target")) {
                            comp.target = value;
                        }
                    }
                },
                .build => {
                    if (std.mem.eql(u8, key, "command")) {
                        manifest.build.command = value;
                    } else if (std.mem.eql(u8, key, "output")) {
                        manifest.build.output = value;
                    } else if (std.mem.eql(u8, key, "target")) {
                        manifest.build.target = value;
                    } else if (std.mem.eql(u8, key, "optimize")) {
                        manifest.build.optimize = value;
                    }
                },
                .dependencies => {
                    // Simple dependency: name = "version"
                    try deps_list.append(allocator, .{ .name = key, .version = value });
                },
                .filesystem => {
                    // Filesystem mapping: "/guest" = "host"
                    try fs_mappings.append(allocator, .{ .guest = key, .host = value });
                },
                else => {},
            }
        }
    }

    // Save any remaining module/command
    if (current_module) |mod| {
        try modules_list.append(allocator, mod);
    }
    if (current_command) |cmd| {
        try commands_list.append(allocator, cmd);
    }

    // Convert lists to slices
    manifest.modules = try modules_list.toOwnedSlice(allocator);
    manifest.commands = try commands_list.toOwnedSlice(allocator);
    manifest.dependencies = try deps_list.toOwnedSlice(allocator);
    manifest.filesystem.mappings = try fs_mappings.toOwnedSlice(allocator);

    return manifest;
}

/// Parse a TOML value (handles strings with quotes)
fn parseValue(raw: []const u8) []const u8 {
    if (raw.len >= 2 and (raw[0] == '"' or raw[0] == '\'')) {
        return raw[1 .. raw.len - 1];
    }
    return raw;
}

/// Parse ABI string to enum
fn parseAbi(value: []const u8) Module.Abi {
    if (std.mem.eql(u8, value, "wasi")) return .wasi;
    if (std.mem.eql(u8, value, "emscripten")) return .emscripten;
    if (std.mem.eql(u8, value, "none")) return .none;
    if (std.mem.startsWith(u8, value, "wasi:cli/command")) return .wasi_cli_command;
    if (std.mem.startsWith(u8, value, "wasi:http/proxy")) return .wasi_http_proxy;
    return .custom;
}

/// Parse inline array like ["a", "b", "c"]
fn parseArrayInline(allocator: std.mem.Allocator, raw: []const u8) ![]const []const u8 {
    var items = std.ArrayListUnmanaged([]const u8).empty;
    errdefer items.deinit(allocator);

    var content = raw;
    if (content.len >= 2 and content[0] == '[') {
        content = content[1 .. content.len - 1];
    }

    var iter = std.mem.splitAny(u8, content, ",");
    while (iter.next()) |item| {
        const trimmed = std.mem.trim(u8, item, " \t\"'");
        if (trimmed.len > 0) {
            try items.append(allocator, trimmed);
        }
    }

    return items.toOwnedSlice(allocator);
}

const Section = enum {
    none,
    package,
    package_authors,
    module,
    command,
    dependencies,
    dev_dependencies,
    workspace,
    component,
    build,
    filesystem,
};

const TableArray = enum {
    none,
    module,
    command,
};

/// Generate TOML string from manifest
pub fn toToml(self: *const Manifest, allocator: std.mem.Allocator) ![]u8 {
    var buffer = std.ArrayListUnmanaged(u8).empty;
    const writer = buffer.writer(allocator);

    // Header
    try writer.writeAll("# wart project configuration\n");
    try writer.writeAll("# https://github.com/clpi/wart\n\n");

    // Package section
    try writer.writeAll("[package]\n");
    try writer.print("name = \"{s}\"\n", .{self.package.name});
    try writer.print("version = \"{s}\"\n", .{self.package.version});
    try writer.print("description = \"{s}\"\n", .{self.package.description});
    try writer.print("license = \"{s}\"\n", .{self.package.license});
    if (self.package.readme) |readme| {
        try writer.print("readme = \"{s}\"\n", .{readme});
    }
    if (self.package.repository) |repo| {
        if (repo.len > 0) try writer.print("repository = \"{s}\"\n", .{repo});
    }
    if (self.package.homepage) |homepage| {
        if (homepage.len > 0) try writer.print("homepage = \"{s}\"\n", .{homepage});
    }
    if (self.package.private) {
        try writer.writeAll("private = true\n");
    }
    try writer.writeAll("\n");

    // Dependencies
    if (self.dependencies.len > 0) {
        try writer.writeAll("[dependencies]\n");
        for (self.dependencies) |dep| {
            if (dep.version) |ver| {
                try writer.print("{s} = \"{s}\"\n", .{ dep.name, ver });
            } else if (dep.path) |path| {
                try writer.print("{s} = {{ path = \"{s}\" }}\n", .{ dep.name, path });
            } else if (dep.git) |git| {
                try writer.print("{s} = {{ git = \"{s}\" }}\n", .{ dep.name, git });
            }
        }
        try writer.writeAll("\n");
    }

    // Modules
    for (self.modules) |mod| {
        try writer.writeAll("[[module]]\n");
        try writer.print("name = \"{s}\"\n", .{mod.name});
        try writer.print("source = \"{s}\"\n", .{mod.source});
        try writer.print("abi = \"{s}\"\n", .{abiToString(mod.abi)});
        try writer.writeAll("\n");
    }

    // Commands
    for (self.commands) |cmd| {
        try writer.writeAll("[[command]]\n");
        try writer.print("name = \"{s}\"\n", .{cmd.name});
        try writer.print("module = \"{s}\"\n", .{cmd.module});
        if (cmd.runner) |runner| {
            try writer.print("runner = \"{s}\"\n", .{runner});
        }
        try writer.writeAll("\n");
    }

    // Workspace
    if (self.workspace) |ws| {
        try writer.writeAll("[workspace]\n");
        if (ws.members.len > 0) {
            try writer.writeAll("members = [");
            for (ws.members, 0..) |member, i| {
                if (i > 0) try writer.writeAll(", ");
                try writer.print("\"{s}\"", .{member});
            }
            try writer.writeAll("]\n");
        }
        try writer.writeAll("\n");
    }

    // Component
    if (self.component) |comp| {
        try writer.writeAll("[component]\n");
        if (comp.wit) |wit| {
            try writer.print("wit = \"{s}\"\n", .{wit});
        }
        if (comp.world) |world| {
            try writer.print("world = \"{s}\"\n", .{world});
        }
        try writer.writeAll("\n");
    }

    // Build
    if (self.build.command != null or self.build.output != null) {
        try writer.writeAll("[build]\n");
        if (self.build.command) |cmd| {
            try writer.print("command = \"{s}\"\n", .{cmd});
        }
        if (self.build.output) |output| {
            try writer.print("output = \"{s}\"\n", .{output});
        }
        if (self.build.target) |target| {
            try writer.print("target = \"{s}\"\n", .{target});
        }
        try writer.writeAll("\n");
    }

    // Filesystem
    if (self.filesystem.mappings.len > 0) {
        try writer.writeAll("[fs]\n");
        for (self.filesystem.mappings) |mapping| {
            try writer.print("\"{s}\" = \"{s}\"\n", .{ mapping.guest, mapping.host });
        }
        try writer.writeAll("\n");
    }

    return buffer.toOwnedSlice(allocator);
}

fn abiToString(abi: Module.Abi) []const u8 {
    return switch (abi) {
        .wasi => "wasi",
        .emscripten => "emscripten",
        .none => "none",
        .wasi_cli_command => "wasi:cli/command@0.2.0",
        .wasi_http_proxy => "wasi:http/proxy@0.2.0",
        .custom => "custom",
    };
}

/// Save manifest to file
pub fn save(self: *const Manifest, path: []const u8) !void {
    const io = self.io;
    const content = try self.toToml(self.allocator);
    defer self.allocator.free(content);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = content });
}

/// Save manifest to wart.toml in current directory
pub fn saveToml(self: *const Manifest) !void {
    try self.save("wart.toml");
}

/// Check if manifest has workspace configuration
pub fn isWorkspace(self: *const Manifest) bool {
    return self.workspace != null and self.workspace.?.members.len > 0;
}

/// Get all module sources for packaging
/// Get all module sources for packaging
/// Caller owns the returned memory and must free it
pub fn getModuleSources(self: *const Manifest, allocator: std.mem.Allocator) ![]const []const u8 {
    var sources = std.ArrayListUnmanaged([]const u8).empty;
    errdefer sources.deinit(allocator);

    for (self.modules) |mod| {
        try sources.append(allocator, mod.source);
    }
    return sources.toOwnedSlice(allocator);
}

/// Validate manifest for publishing
pub fn validate(self: *const Manifest) !void {
    if (self.package.name.len == 0) {
        return error.MissingPackageName;
    }
    if (self.package.version.len == 0) {
        return error.MissingPackageVersion;
    }
    if (self.modules.len == 0) {
        return error.NoModulesDefined;
    }
    for (self.modules) |mod| {
        if (mod.source.len == 0) {
            return error.ModuleMissingSource;
        }
    }
}

/// Template types for project initialization
pub const Template = enum {
    default,
    library,
    application,
    component,
    workspace,

    pub fn description(self: Template) []const u8 {
        return switch (self) {
            .default => "A basic WebAssembly project",
            .library => "A WebAssembly library (no CLI)",
            .application => "A full WASI application with CLI",
            .component => "A WebAssembly Component Model project",
            .workspace => "A multi-package workspace",
        };
    }
};

/// Create a new manifest from template
pub fn fromTemplate(allocator: std.mem.Allocator, io: std.Io, name: []const u8, template: Template) !Manifest {
    var manifest = Manifest.init(allocator, io);

    manifest.package.name = name;
    manifest.package.version = "0.1.0";

    switch (template) {
        .default => {
            manifest.package.description = "A WebAssembly project";
            manifest.modules = try allocator.dupe(Module, &[_]Module{
                .{ .name = "main", .source = "src/main.wasm", .abi = .wasi },
            });
            manifest.commands = try allocator.dupe(Command, &[_]Command{
                .{ .name = name, .module = "main" },
            });
            manifest.build.command = "zig build -Dtarget=wasm32-wasi";
            manifest.build.output = "zig-out/bin";
        },
        .library => {
            manifest.package.description = "A WebAssembly library";
            manifest.modules = try allocator.dupe(Module, &[_]Module{
                .{ .name = name, .source = try std.fmt.allocPrint(allocator, "lib/{s}.wasm", .{name}), .abi = .none },
            });
            manifest.build.command = "zig build -Dtarget=wasm32-freestanding";
            manifest.build.output = "lib";
        },
        .application => {
            manifest.package.description = "A WebAssembly application";
            manifest.modules = try allocator.dupe(Module, &[_]Module{
                .{ .name = "main", .source = try std.fmt.allocPrint(allocator, "target/wasm32-wasi/release/{s}.wasm", .{name}), .abi = .wasi },
            });
            manifest.commands = try allocator.dupe(Command, &[_]Command{
                .{ .name = name, .module = "main", .runner = "https://webc.org/runner/wasi" },
            });
            manifest.build.command = "zig build -Dtarget=wasm32-wasi -Drelease-fast";
            manifest.build.output = "target/wasm32-wasi/release";
        },
        .component => {
            manifest.package.description = "A WebAssembly Component";
            manifest.modules = try allocator.dupe(Module, &[_]Module{
                .{ .name = name, .source = try std.fmt.allocPrint(allocator, "target/{s}.component.wasm", .{name}), .abi = .wasi_cli_command },
            });
            manifest.component = Component{
                .wit = try std.fmt.allocPrint(allocator, "wit/{s}.wit", .{name}),
                .world = try std.fmt.allocPrint(allocator, "{s}:main/component", .{name}),
            };
            manifest.build.command = try std.fmt.allocPrint(allocator, "wasm-tools component new target/{s}.wasm -o target/{s}.component.wasm", .{ name, name });
            manifest.build.output = "target";
        },
        .workspace => {
            manifest.package.description = "A WebAssembly workspace";
            manifest.workspace = Workspace{
                .members = try allocator.dupe([]const u8, &[_][]const u8{"packages/*"}),
            };
        },
    }

    return manifest;
}

// Tests
test "parse simple manifest" {
    const content =
        \\[package]
        \\name = "test-project"
        \\version = "1.0.0"
        \\description = "A test project"
        \\
        \\[[module]]
        \\name = "main"
        \\source = "src/main.wasm"
        \\abi = "wasi"
        \\
        \\[[command]]
        \\name = "test"
        \\module = "main"
    ;

    const manifest = try parse(std.testing.allocator, content);
    defer {
        std.testing.allocator.free(manifest.modules);
        std.testing.allocator.free(manifest.commands);
    }

    try std.testing.expectEqualStrings("test-project", manifest.package.name);
    try std.testing.expectEqualStrings("1.0.0", manifest.package.version);
    try std.testing.expectEqual(@as(usize, 1), manifest.modules.len);
    try std.testing.expectEqualStrings("main", manifest.modules[0].name);
}

test "parse workspace manifest" {
    const content =
        \\[package]
        \\name = "workspace-root"
        \\version = "0.1.0"
        \\
        \\[workspace]
        \\members = ["packages/core", "packages/utils"]
    ;

    const manifest = try parse(std.testing.allocator, content);
    defer {
        if (manifest.workspace) |ws| {
            std.testing.allocator.free(ws.members);
        }
    }

    try std.testing.expect(manifest.workspace != null);
    try std.testing.expectEqual(@as(usize, 2), manifest.workspace.?.members.len);
}
