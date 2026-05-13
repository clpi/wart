const std = @import("std");
const common = @import("common.zig");
const Config = common.Config;
const Color = common.Color;
const print = common.print;
const cwd = std.Io.Dir.cwd;

pub const Template: type = enum { default, library, application, component };

pub const Options = struct {
    name: ?[]const u8 = null,
    path: []const u8 = ".",
    template: Template = .default,
    config: Config,
};

pub fn parse(base_cfg: Config, positional: []const [:0]u8) common.CliError!Options {
    var options = Options{ .config = base_cfg };

    var i: usize = 0;
    while (i < positional.len) : (i += 1) {
        const arg = positional[i];

        if (std.mem.eql(u8, arg, "--template") or std.mem.eql(u8, arg, "-t")) {
            if (i + 1 >= positional.len) return common.CliError.MissingArgument;
            i += 1;
            const template_name = std.mem.sliceTo(positional[i], 0);
            if (std.mem.eql(u8, template_name, "lib") or std.mem.eql(u8, template_name, "library")) {
                options.template = .library;
            } else if (std.mem.eql(u8, template_name, "app") or std.mem.eql(u8, template_name, "application")) {
                options.template = .application;
            } else if (std.mem.eql(u8, template_name, "component")) {
                options.template = .component;
            } else if (std.mem.eql(u8, template_name, "default")) {
                options.template = .default;
            } else {
                return common.CliError.InvalidArgument;
            }
        } else if (std.mem.eql(u8, arg, "--name") or std.mem.eql(u8, arg, "-n")) {
            if (i + 1 >= positional.len) return common.CliError.MissingArgument;
            i += 1;
            options.name = std.mem.sliceTo(positional[i], 0);
        } else if (arg[0] != '-') {
            options.path = std.mem.sliceTo(arg, 0);
        }
    }

    return options;
}

pub fn run(allocator: std.mem.Allocator, io: std.Io, opts: Options) !void {
    const project_path = opts.path;

    if (!std.mem.eql(u8, project_path, ".")) {
        cwd().createDirPath(io, project_path) catch |err| {
            print("error: failed to create directory '{s}': {s}", .{ project_path, @errorName(err) }, Color.red);
            return err;
        };
    }

    const project_name = opts.name orelse blk: {
        if (std.mem.eql(u8, project_path, ".")) {
            var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
            const pwd = cwd().realPath(io, &cwd_buf) catch break :blk "my-project";
            break :blk std.Io.Dir.path.basename(cwd_buf[0..pwd]);
        } else {
            break :blk std.Io.Dir.path.basename(project_path);
        }
    };

    const toml_content = try generateWartToml(allocator, project_name, opts.template);
    defer allocator.free(toml_content);

    const toml_path = try std.fs.path.join(allocator, &[_][]const u8{ project_path, "wart.toml" });
    defer allocator.free(toml_path);

    if (cwd().access(io, toml_path, .{})) |_| {
        print("error: wart.toml already exists at {s}", .{toml_path}, Color.yellow);
        return;
    } else |_| {}

    try cwd().writeFile(io, .{
        .sub_path = toml_path,
        .data = toml_content,
    });

    print("Generated {s} using the {s} template", .{ toml_path, @tagName(opts.template) }, Color.reset);
}

pub fn help(program_name: []const u8) void {
    print("{s}wart init{s}", .{ Color.bright_cyan, Color.reset }, Color.reset);
    print("Usage: {s} init [--template <template>] [--name <name>] [path]", .{program_name}, Color.reset);
    print("Templates: default | library | application | component", .{}, Color.reset);
}

fn generateWartToml(allocator: std.mem.Allocator, name: []const u8, template: Template) ![]u8 {
    var buffer = std.ArrayListUnmanaged(u8).empty;
    errdefer buffer.deinit(allocator);
    var writer = std.Io.Writer.fromArrayList(&buffer);

    switch (template) {
        .default => {
            try writer.writeAll("# wart project configuration\n");
            try writer.writeAll("# https://github.com/clpi/wart\n\n");
            try writer.writeAll("[package]\n");
            try writer.print("name = \"{s}\"\n", .{name});
            try writer.writeAll("version = \"0.1.0\"\n");
            try writer.writeAll("description = \"A WebAssembly project\"\n");
            try writer.writeAll("license = \"MIT\"\n");
            try writer.writeAll("readme = \"README.md\"\n");
            try writer.writeAll("repository = \"\"\n");
            try writer.writeAll("homepage = \"\"\n\n");
            try writer.writeAll("[package.authors]\n");
            try writer.writeAll("# name = \"Your Name <your.email@example.com>\"\n\n");
            try writer.writeAll("[dependencies]\n");
            try writer.writeAll("# Example: wasi = \"0.2.0\"\n\n");
            try writer.writeAll("[[module]]\n");
            try writer.writeAll("name = \"main\"\n");
            try writer.writeAll("source = \"src/main.wasm\"\n");
            try writer.writeAll("abi = \"wasi\"\n\n");
            try writer.writeAll("[[command]]\n");
            try writer.print("name = \"{s}\"\n", .{name});
            try writer.writeAll("module = \"main\"\n\n");
            try writer.writeAll("[build]\n");
            try writer.writeAll("# Build command to compile your project to wasm\n");
            try writer.writeAll("command = \"zig build -Dtarget=wasm32-wasi\"\n");
            try writer.writeAll("output = \"zig-out/bin\"\n");
        },
        .library => {
            try writer.writeAll("# wart library configuration\n");
            try writer.writeAll("# https://github.com/clpi/wart\n\n");
            try writer.writeAll("[package]\n");
            try writer.print("name = \"{s}\"\n", .{name});
            try writer.writeAll("version = \"0.1.0\"\n");
            try writer.writeAll("description = \"A WebAssembly library\"\n");
            try writer.writeAll("license = \"MIT\"\n");
            try writer.writeAll("readme = \"README.md\"\n\n");
            try writer.writeAll("[package.authors]\n");
            try writer.writeAll("# name = \"Your Name <your.email@example.com>\"\n\n");
            try writer.writeAll("[dependencies]\n\n");
            try writer.writeAll("[[module]]\n");
            try writer.print("name = \"{s}\"\n", .{name});
            try writer.print("source = \"lib/{s}.wasm\"\n", .{name});
            try writer.writeAll("abi = \"none\"\n\n");
            try writer.writeAll("[build]\n");
            try writer.writeAll("command = \"zig build -Dtarget=wasm32-freestanding\"\n");
            try writer.writeAll("output = \"lib\"\n");
        },
        .application => {
            try writer.writeAll("# wart application configuration\n");
            try writer.writeAll("# https://github.com/clpi/wart\n\n");
            try writer.writeAll("[package]\n");
            try writer.print("name = \"{s}\"\n", .{name});
            try writer.writeAll("version = \"0.1.0\"\n");
            try writer.writeAll("description = \"A WebAssembly application\"\n");
            try writer.writeAll("license = \"MIT\"\n");
            try writer.writeAll("readme = \"README.md\"\n");
            try writer.writeAll("repository = \"\"\n");
            try writer.writeAll("homepage = \"\"\n\n");
            try writer.writeAll("[package.authors]\n");
            try writer.writeAll("# name = \"Your Name <your.email@example.com>\"\n\n");
            try writer.writeAll("[dependencies]\n");
            try writer.writeAll("# wasi_vfs = \"0.1.0\"\n\n");
            try writer.writeAll("[[module]]\n");
            try writer.writeAll("name = \"main\"\n");
            try writer.print("source = \"target/wasm32-wasi/release/{s}.wasm\"\n", .{name});
            try writer.writeAll("abi = \"wasi\"\n\n");
            try writer.writeAll("[[command]]\n");
            try writer.print("name = \"{s}\"\n", .{name});
            try writer.writeAll("module = \"main\"\n");
            try writer.writeAll("runner = \"https://webc.org/runner/wasi\"\n\n");
            try writer.writeAll("[fs]\n");
            try writer.writeAll("# Map host directories to WASI filesystem\n");
            try writer.writeAll("# \"/data\" = \"data\"\n\n");
            try writer.writeAll("[build]\n");
            try writer.writeAll("command = \"zig build -Dtarget=wasm32-wasi -Drelease-fast\"\n");
            try writer.writeAll("output = \"target/wasm32-wasi/release\"\n");
        },
        .component => {
            try writer.writeAll("# wart component model configuration\n");
            try writer.writeAll("# https://github.com/clpi/wart\n\n");
            try writer.writeAll("[package]\n");
            try writer.print("name = \"{s}\"\n", .{name});
            try writer.writeAll("version = \"0.1.0\"\n");
            try writer.writeAll("description = \"A WebAssembly Component\"\n");
            try writer.writeAll("license = \"MIT\"\n");
            try writer.writeAll("readme = \"README.md\"\n\n");
            try writer.writeAll("[package.authors]\n");
            try writer.writeAll("# name = \"Your Name <your.email@example.com>\"\n\n");
            try writer.writeAll("[dependencies]\n\n");
            try writer.writeAll("[[module]]\n");
            try writer.print("name = \"{s}\"\n", .{name});
            try writer.print("source = \"target/{s}.component.wasm\"\n", .{name});
            try writer.writeAll("abi = \"wasi:cli/command@0.2.0\"\n\n");
            try writer.writeAll("[component]\n");
            try writer.writeAll("# WIT (WebAssembly Interface Types) file\n");
            try writer.print("wit = \"wit/{s}.wit\"\n", .{name});
            try writer.writeAll("# Target world\n");
            try writer.print("world = \"{s}:main/component\"\n\n", .{name});
            try writer.writeAll("[build]\n");
            try writer.print("command = \"wasm-tools component new target/{s}.wasm -o target/{s}.component.wasm\"\n", .{ name, name });
            try writer.writeAll("output = \"target\"\n");
        },
    }

    return buffer.toOwnedSlice(allocator);
}
