const std = @import("std");
const builtin = @import("builtin");
const common = @import("common.zig");
const fmt = @import("../util/fmt.zig");
const Color = common.Color;
const Runtime = @import("../wasm/runtime.zig");
const Value = Runtime.Value;
const ValueType = @import("../wasm/value.zig").Type;
const CCompiler = @import("../wasm/c_compiler.zig");
const WatParser = @import("../wasm/wat.zig");
const Module = @import("../wasm/module.zig");

const max_module_size_bytes = 100 * 1024 * 1024;
const max_history_items = 200;
const max_call_args = 32;
const default_entry_points = [_][]const u8{ "_start", "main", "run", "execute" };

pub const Options = struct {
    wasm_file: ?[:0]u8 = null,
    config: common.Config,
};

pub const SourceLanguage = enum {
    auto,
    unknown,
    c,
    cpp,
    wat,
    wasm,
};

const ShellAction = enum {
    continue_loop,
    exit_loop,
};

const CompileResult = struct {
    wasm: []u8,
    language: SourceLanguage,
};

const ResolvedCall = struct {
    index: usize,
    signature: Module.Signature,
};

pub const ShellSession = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    runtime: *Runtime,
    current_module: ?*Runtime.Module,
    color_enabled: bool,
    verbose: u8,
    preferred_language: SourceLanguage,
    paste_mode: bool,
    history: std.ArrayList([]u8),
    paste_buffer: std.ArrayList(u8),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, io: std.Io, config: common.Config) !Self {
        const rt = try Runtime.init(allocator, io);
        rt.debug = config.debug;
        rt.validate = config.validate;
        rt.jit_enabled = config.jit;

        return Self{
            .allocator = allocator,
            .io = io,
            .runtime = rt,
            .current_module = null,
            .color_enabled = config.color,
            .verbose = config.verbose,
            .preferred_language = .auto,
            .paste_mode = false,
            .history = try std.ArrayList([]u8).initCapacity(allocator, 0),
            .paste_buffer = try std.ArrayList(u8).initCapacity(allocator, 0),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.history.items) |entry| {
            self.allocator.free(entry);
        }
        self.history.deinit(self.allocator);
        self.paste_buffer.deinit(self.allocator);
        self.runtime.deinit();
    }

    pub fn detectLanguage(source: []const u8) SourceLanguage {
        const trimmed = std.mem.trim(u8, source, &std.ascii.whitespace);
        if (trimmed.len == 0) return .unknown;

        if (isWasmBinary(trimmed)) return .wasm;

        if (trimmed[0] == '(' or std.mem.indexOf(u8, trimmed, "(module") != null or
            std.mem.indexOf(u8, trimmed, "(func") != null or
            std.mem.indexOf(u8, trimmed, "(import") != null)
        {
            return .wat;
        }

        const has_cpp = std.mem.indexOf(u8, trimmed, "class ") != null or
            std.mem.indexOf(u8, trimmed, "namespace ") != null or
            std.mem.indexOf(u8, trimmed, "template") != null or
            std.mem.indexOf(u8, trimmed, "std::") != null or
            std.mem.indexOf(u8, trimmed, "cout") != null or
            std.mem.indexOf(u8, trimmed, "cin") != null;

        const has_c = std.mem.indexOf(u8, trimmed, "#include") != null or
            std.mem.indexOf(u8, trimmed, "int ") != null or
            std.mem.indexOf(u8, trimmed, "void ") != null or
            std.mem.indexOf(u8, trimmed, "return") != null;

        if (has_cpp) return .cpp;
        if (has_c) return .c;

        return .unknown;
    }

    pub fn languageFromPath(path: []const u8) SourceLanguage {
        if (std.mem.endsWith(u8, path, ".wasm")) return .wasm;
        if (std.mem.endsWith(u8, path, ".wat") or std.mem.endsWith(u8, path, ".wast")) return .wat;
        if (std.mem.endsWith(u8, path, ".c")) return .c;
        if (std.mem.endsWith(u8, path, ".cpp") or std.mem.endsWith(u8, path, ".cc") or std.mem.endsWith(u8, path, ".cxx") or std.mem.endsWith(u8, path, ".c++")) return .cpp;
        return .unknown;
    }

    pub fn compileSource(self: *Self, source: []const u8, hint: SourceLanguage) !CompileResult {
        var resolved_hint = hint;
        if (resolved_hint == .auto and self.preferred_language != .auto) {
            resolved_hint = self.preferred_language;
        }

        const language = switch (resolved_hint) {
            .auto => Self.detectLanguage(source),
            .unknown => Self.detectLanguage(source),
            else => resolved_hint,
        };

        return switch (language) {
            .wasm => blk: {
                if (!isWasmBinary(source)) return error.InvalidWasmBinary;
                break :blk CompileResult{ .wasm = try self.allocator.dupe(u8, source), .language = .wasm };
            },
            .wat => CompileResult{ .wasm = try WatParser.convertWatToWasm(self.allocator, self.io, source), .language = .wat },
            .c => CompileResult{ .wasm = try CCompiler.compileCToWasm(self.allocator, self.io, source), .language = .c },
            .cpp => CompileResult{ .wasm = try CCompiler.compileCppToWasm(self.allocator, self.io, source), .language = .cpp },
            .auto, .unknown => error.UnknownSourceLanguage,
        };
    }

    pub fn compileFile(self: *Self, path: []const u8) !CompileResult {
        const file_bytes = try std.Io.Dir.cwd().readFileAlloc(self.io, path, self.allocator, .limited(max_module_size_bytes));
        defer self.allocator.free(file_bytes);

        var hint = Self.languageFromPath(path);
        if (hint == .unknown) {
            hint = .auto;
        }
        return self.compileSource(file_bytes, hint);
    }

    pub fn loadModule(self: *Self, wasm_bytes: []const u8) !void {
        const module = try self.runtime.loadModule(wasm_bytes);
        self.current_module = module;

        var argv_buf: [1][:0]u8 = undefined;
        var argv_item: [16]u8 = undefined;
        @memcpy(argv_item[0.."wart-shell".len], "wart-shell");
        argv_item["wart-shell".len] = 0;
        argv_buf[0] = argv_item[0.."wart-shell".len :0];

        if (module.memory != null) {
            try self.runtime.setupWASI(&argv_buf);
        } else if (self.verbose >= 1) {
            std.debug.print("Skipping WASI setup for module without memory section\n", .{});
        }
    }

    pub fn clearModule(self: *Self) void {
        self.current_module = null;
    }

    pub fn addHistory(self: *Self, line: []const u8) !void {
        if (line.len == 0) return;
        const owned = try self.allocator.dupe(u8, line);
        try self.history.append(self.allocator, owned);

        if (self.history.items.len > max_history_items) {
            const dropped = self.history.items[0];
            self.allocator.free(dropped);
            std.mem.copyForwards([]u8, self.history.items[0 .. self.history.items.len - 1], self.history.items[1..]);
            self.history.items.len -= 1;
        }
    }

    pub fn printHistory(self: *Self) void {
        if (self.history.items.len == 0) {
            printColorLine(self.color_enabled, Color.dim, "(history is empty)", .{});
            return;
        }

        for (self.history.items, 0..) |entry, idx| {
            printColorLine(self.color_enabled, Color.dim, "{d:>4}  {s}", .{ idx + 1, entry });
        }
    }

    pub fn listExports(self: *Self) void {
        const module = self.current_module orelse {
            printColorLine(self.color_enabled, Color.bright_red, "No module loaded", .{});
            return;
        };

        var function_count: usize = 0;
        var memory_count: usize = 0;
        var global_count: usize = 0;
        var other_count: usize = 0;

        printColorLine(self.color_enabled, Color.bright_yellow, "Exports", .{});
        for (module.exports.items) |exp| {
            switch (exp.kind) {
                .function => {
                    function_count += 1;
                    const display_name = printableExportName(exp.name);
                    const maybe_sig = signatureForFunction(module, @intCast(exp.index));
                    if (maybe_sig) |sig| {
                        const signature = formatSignatureAlloc(self.allocator, sig) catch "";
                        if (signature.len > 0) {
                            defer self.allocator.free(signature);
                        }
                        printColorLine(self.color_enabled, Color.bright_cyan, "  fn {s}{s}", .{ display_name, signature });
                    } else {
                        printColorLine(self.color_enabled, Color.bright_cyan, "  fn {s}", .{display_name});
                    }
                },
                .memory => {
                    memory_count += 1;
                    printColorLine(self.color_enabled, Color.bright_magenta, "  memory {s}", .{printableExportName(exp.name)});
                },
                .global => {
                    global_count += 1;
                    printColorLine(self.color_enabled, Color.bright_green, "  global {s}", .{printableExportName(exp.name)});
                },
                else => {
                    other_count += 1;
                    printColorLine(self.color_enabled, Color.bright_white, "  {s} {s}", .{ @tagName(exp.kind), printableExportName(exp.name) });
                },
            }
        }

        if (module.exports.items.len == 0) {
            printColorLine(self.color_enabled, Color.dim, "  (none)", .{});
        }

        printColorLine(self.color_enabled, Color.dim, "Summary: {d} function(s), {d} memory, {d} global(s), {d} other", .{
            function_count,
            memory_count,
            global_count,
            other_count,
        });
    }

    pub fn moduleInfo(self: *Self) void {
        const module = self.current_module orelse {
            printColorLine(self.color_enabled, Color.bright_red, "No module loaded", .{});
            return;
        };

        printColorLine(self.color_enabled, Color.bright_yellow, "Module info", .{});
        printColorLine(self.color_enabled, Color.dim, "  types: {d}", .{module.types.items.len});
        printColorLine(self.color_enabled, Color.dim, "  functions: {d}", .{module.functions.items.len});
        printColorLine(self.color_enabled, Color.dim, "  exports: {d}", .{module.exports.items.len});
        printColorLine(self.color_enabled, Color.dim, "  imports: {d}", .{module.imports.items.len});

        if (module.memory) |memory| {
            printColorLine(self.color_enabled, Color.dim, "  memory bytes: {d}", .{memory.len});
        } else {
            printColorLine(self.color_enabled, Color.dim, "  memory: (none)", .{});
        }
    }

    pub fn resolveExportedCall(self: *Self, name: []const u8) !ResolvedCall {
        const module = self.current_module orelse return error.NoModuleLoaded;
        const function_index = self.findExportedFunction(name) orelse return error.FunctionNotFound;

        if (function_index >= module.functions.items.len) return error.InvalidFunctionIndex;
        const func = module.functions.items[function_index];
        if (func.type_index >= module.types.items.len) return error.InvalidFunctionType;

        return ResolvedCall{
            .index = function_index,
            .signature = module.types.items[func.type_index],
        };
    }

    pub fn callFunction(self: *Self, name: []const u8, args: []const Value) !Value {
        const resolved = try self.resolveExportedCall(name);
        if (args.len != resolved.signature.params.len) {
            printColorLine(self.color_enabled, Color.bright_red, "Function {s} expects {d} arg(s), got {d}", .{ name, resolved.signature.params.len, args.len });
            return error.ArgumentCountMismatch;
        }

        return self.runtime.executeFunction(resolved.index, args);
    }

    fn findExportedFunction(self: *Self, name: []const u8) ?usize {
        if (self.runtime.findExportedFunction(name)) |index| {
            return index;
        }

        const module = self.current_module orelse return null;
        for (module.exports.items) |exp| {
            if (exp.kind != .function) continue;
            if (std.mem.eql(u8, printableExportName(exp.name), name)) {
                return @intCast(exp.index);
            }
        }

        return null;
    }
};

pub fn parse(cfg: common.Config, positional: []const [:0]u8) Options {
    return Options{
        .wasm_file = if (positional.len > 0) positional[0] else null,
        .config = cfg,
    };
}

pub fn run(allocator: std.mem.Allocator, io: std.Io, opts: Options) !void {
    fmt.setLogEnabled(opts.config.debug);
    fmt.setColorEnabled(opts.config.color);

    var session = try ShellSession.init(allocator, io, opts.config);
    defer session.deinit();

    printBanner(session.color_enabled);
    printColorLine(session.color_enabled, Color.dim, "Type :help for commands, :quit to exit", .{});
    printColorLine(session.color_enabled, Color.dim, "Input supports WAT, C, and C++ source (auto-transpiled to WASM)", .{});
    printLine("", .{});

    if (opts.wasm_file) |file_path| {
        const startup_path: []const u8 = file_path;
        try loadPathAndMaybeRun(&session, startup_path, false);
    }

    var line_buffer: [4096]u8 = undefined;
    var stdin_reader_buffer: [4096]u8 = undefined;
    var stdin_file = std.Io.File{ .handle = if (builtin.os.tag == .windows) std.os.windows.GetStdHandle(std.os.windows.STD_INPUT_HANDLE) catch unreachable else 0, .flags = .{ .nonblocking = false } };
    var stdin = stdin_file.reader(io, &stdin_reader_buffer);
    var tty_fd: ?std.posix.fd_t = null;
    defer if (tty_fd) |fd| {
        _ = std.posix.system.close(fd);
    };

    if (builtin.os.tag != .windows) {
        const stdin_is_tty = std.Io.File.stdin().isTty(io) catch false;
        if (stdin_is_tty) {
            const fd = std.c.open("/dev/tty", .{ .ACCMODE = .RDONLY });
            tty_fd = if (fd >= 0) fd else null;
        }
    }

    while (true) {
        renderPrompt(&session);

        const maybe_line = try readLine(&stdin, line_buffer[0..], tty_fd orelse std.posix.STDIN_FILENO);
        const raw_line = maybe_line orelse {
            printLine("", .{});
            printColorLine(session.color_enabled, Color.bright_cyan, "Goodbye.", .{});
            break;
        };

        const trimmed = std.mem.trim(u8, raw_line, &std.ascii.whitespace);
        if (trimmed.len == 0) {
            continue;
        }

        var effective_input = trimmed;
        if (std.mem.eql(u8, trimmed, "!!")) {
            if (session.history.items.len == 0) {
                printColorLine(session.color_enabled, Color.bright_yellow, "History is empty", .{});
                continue;
            }
            effective_input = session.history.items[session.history.items.len - 1];
            printColorLine(session.color_enabled, Color.dim, "{s}", .{effective_input});
        }

        try session.addHistory(effective_input);

        if (session.paste_mode and !std.mem.eql(u8, effective_input, ":end") and !std.mem.eql(u8, effective_input, ";;") and !std.mem.eql(u8, effective_input, ":cancel")) {
            try session.paste_buffer.appendSlice(allocator, effective_input);
            try session.paste_buffer.append(allocator, '\n');
            continue;
        }

        if (effective_input[0] == '!' and !session.paste_mode) {
            runHostCommand(&session, effective_input[1..]);
            continue;
        }

        const action = processInput(&session, allocator, effective_input) catch |err| {
            printColorLine(session.color_enabled, Color.bright_red, "Error: {s}", .{@errorName(err)});
            continue;
        };

        if (action == .exit_loop) break;
    }
}

fn processInput(session: *ShellSession, allocator: std.mem.Allocator, input: []const u8) !ShellAction {
    if (input.len == 0) return .continue_loop;

    if (input[0] == ':') {
        return handleCommand(session, allocator, input);
    }

    if (isLegacyShellCommand(input)) {
        const prefixed = try std.fmt.allocPrint(allocator, ":{s}", .{input});
        defer allocator.free(prefixed);
        return handleCommand(session, allocator, prefixed);
    }

    try compileLoadAndRunSource(session, input, .auto);
    return .continue_loop;
}

fn handleCommand(session: *ShellSession, _: std.mem.Allocator, raw_cmd: []const u8) !ShellAction {
    const parsed = splitCommand(raw_cmd);

    if (std.mem.eql(u8, parsed.command, ":help") or std.mem.eql(u8, parsed.command, ":?")) {
        printHelp(session.color_enabled);
        return .continue_loop;
    }

    if (std.mem.eql(u8, parsed.command, ":quit") or std.mem.eql(u8, parsed.command, ":exit")) {
        return .exit_loop;
    }

    if (std.mem.eql(u8, parsed.command, ":history")) {
        session.printHistory();
        return .continue_loop;
    }

    if (std.mem.eql(u8, parsed.command, ":clear") or std.mem.eql(u8, parsed.command, ":cls")) {
        session.clearModule();
        printColorLine(session.color_enabled, Color.cyan, "Cleared current module", .{});
        return .continue_loop;
    }

    if (std.mem.eql(u8, parsed.command, ":exports") or std.mem.eql(u8, parsed.command, ":exp")) {
        session.listExports();
        return .continue_loop;
    }

    if (std.mem.eql(u8, parsed.command, ":info")) {
        session.moduleInfo();
        return .continue_loop;
    }

    if (std.mem.eql(u8, parsed.command, ":version")) {
        printColorLine(session.color_enabled, Color.bright_cyan, "wart REPL {s}", .{common.version_string});
        return .continue_loop;
    }

    if (std.mem.eql(u8, parsed.command, ":paste")) {
        session.paste_mode = true;
        session.paste_buffer.clearRetainingCapacity();
        printColorLine(session.color_enabled, Color.bright_yellow, "Paste mode enabled. End with :end or ;;", .{});
        return .continue_loop;
    }

    if (std.mem.eql(u8, parsed.command, ":cancel")) {
        session.paste_mode = false;
        session.paste_buffer.clearRetainingCapacity();
        printColorLine(session.color_enabled, Color.cyan, "Paste mode cancelled", .{});
        return .continue_loop;
    }

    if (std.mem.eql(u8, parsed.command, ":end")) {
        if (!session.paste_mode) {
            printColorLine(session.color_enabled, Color.bright_yellow, "Not in paste mode", .{});
            return .continue_loop;
        }

        session.paste_mode = false;
        const source = std.mem.trim(u8, session.paste_buffer.items, &std.ascii.whitespace);
        if (source.len == 0) {
            printColorLine(session.color_enabled, Color.bright_yellow, "No source captured", .{});
            session.paste_buffer.clearRetainingCapacity();
            return .continue_loop;
        }

        try compileLoadAndRunSource(session, source, .auto);
        session.paste_buffer.clearRetainingCapacity();
        return .continue_loop;
    }

    if (std.mem.eql(u8, parsed.command, ":load")) {
        if (parsed.args.len == 0) {
            printColorLine(session.color_enabled, Color.bright_yellow, "Usage: :load <file.wasm|file.wat|file.c|file.cpp>", .{});
            return .continue_loop;
        }

        try loadPathAndMaybeRun(session, parsed.args, false);
        return .continue_loop;
    }

    if (std.mem.eql(u8, parsed.command, ":lang")) {
        handleLanguageCommand(session, parsed.args);
        return .continue_loop;
    }

    if (std.mem.eql(u8, parsed.command, ":run")) {
        if (parsed.args.len == 0) {
            _ = try runDefaultEntryPoint(session);
            return .continue_loop;
        }

        try callNamedFunction(session, parsed.args);
        return .continue_loop;
    }

    if (std.mem.eql(u8, parsed.command, ":call")) {
        if (parsed.args.len == 0) {
            printColorLine(session.color_enabled, Color.bright_yellow, "Usage: :call <function> [args...]", .{});
            return .continue_loop;
        }

        try callNamedFunction(session, parsed.args);
        return .continue_loop;
    }

    printColorLine(session.color_enabled, Color.bright_red, "Unknown command: {s}", .{parsed.command});
    printColorLine(session.color_enabled, Color.dim, "Use :help for command list", .{});
    return .continue_loop;
}

fn compileLoadAndRunSource(session: *ShellSession, source: []const u8, hint: SourceLanguage) !void {
    const compile_result = session.compileSource(source, hint) catch |err| {
        reportCompilationError(session, err);
        return;
    };
    defer session.allocator.free(compile_result.wasm);

    session.loadModule(compile_result.wasm) catch |err| {
        printColorLine(session.color_enabled, Color.bright_red, "Failed to load module: {s}", .{@errorName(err)});
        return;
    };

    printColorLine(session.color_enabled, Color.bright_green, "Loaded module ({s} -> wasm, {d} bytes)", .{
        languageLabel(compile_result.language),
        compile_result.wasm.len,
    });

    _ = try runDefaultEntryPoint(session);
}

fn loadPathAndMaybeRun(session: *ShellSession, path: []const u8, run_after_load: bool) !void {
    printColorLine(session.color_enabled, Color.cyan, "Loading {s}", .{path});

    const compile_result = session.compileFile(path) catch |err| {
        if (err == error.FileNotFound) {
            printColorLine(session.color_enabled, Color.bright_red, "File not found: {s}", .{path});
            return;
        }

        reportCompilationError(session, err);
        return;
    };
    defer session.allocator.free(compile_result.wasm);

    session.loadModule(compile_result.wasm) catch |err| {
        printColorLine(session.color_enabled, Color.bright_red, "Failed to load module: {s}", .{@errorName(err)});
        return;
    };

    printColorLine(session.color_enabled, Color.bright_green, "Loaded module from {s} ({s} -> wasm)", .{ path, languageLabel(compile_result.language) });

    if (run_after_load) {
        _ = try runDefaultEntryPoint(session);
    }
}

fn runDefaultEntryPoint(session: *ShellSession) !bool {
    const module = session.current_module orelse {
        printColorLine(session.color_enabled, Color.bright_red, "No module loaded", .{});
        return false;
    };

    for (default_entry_points) |name| {
        const function_index = session.findExportedFunction(name) orelse continue;
        const signature = signatureForFunction(module, function_index) orelse continue;

        var auto_args_buf: [max_call_args]Value = undefined;
        const auto_args = buildDefaultArgs(signature.params, &auto_args_buf) orelse {
            continue;
        };

        printColorLine(session.color_enabled, Color.bright_cyan, "Running entry: {s}", .{name});

        const result = session.runtime.executeFunction(function_index, auto_args) catch |err| {
            printColorLine(session.color_enabled, Color.bright_red, "Execution failed in {s}: {s}", .{ name, @errorName(err) });
            return false;
        };

        if (signature.results.len > 0) {
            printColorLine(session.color_enabled, Color.bright_green, "Return: {any}", .{result});
        }

        return true;
    }

    printColorLine(session.color_enabled, Color.bright_yellow, "No runnable default entry found (_start/main/run/execute)", .{});
    printColorLine(session.color_enabled, Color.dim, "Use :exports and :call <name> [args...]", .{});
    return false;
}

fn callNamedFunction(session: *ShellSession, args_text: []const u8) !void {
    const parsed = splitCommand(args_text);
    const fn_name = parsed.command;
    const arg_text = parsed.args;

    if (fn_name.len == 0) {
        printColorLine(session.color_enabled, Color.bright_yellow, "Usage: :call <function> [args...]", .{});
        return;
    }

    const resolved = session.resolveExportedCall(fn_name) catch |err| {
        switch (err) {
            error.NoModuleLoaded => printColorLine(session.color_enabled, Color.bright_red, "No module loaded", .{}),
            error.FunctionNotFound => printColorLine(session.color_enabled, Color.bright_red, "Function not found: {s}", .{fn_name}),
            else => printColorLine(session.color_enabled, Color.bright_red, "Unable to resolve function: {s}", .{@errorName(err)}),
        }
        return;
    };

    var parsed_args_buf: [max_call_args]Value = undefined;
    const parsed_args = parseArgumentsForSignature(resolved.signature.params, arg_text, &parsed_args_buf) catch |err| {
        switch (err) {
            error.TooManyArguments => printColorLine(session.color_enabled, Color.bright_red, "Too many args (max {d})", .{max_call_args}),
            error.ArgumentCountMismatch => printColorLine(session.color_enabled, Color.bright_red, "Function {s} expects {d} arg(s)", .{ fn_name, resolved.signature.params.len }),
            error.InvalidArgument => printColorLine(session.color_enabled, Color.bright_red, "Invalid argument for function signature", .{}),
        }
        return;
    };

    const result = session.callFunction(fn_name, parsed_args) catch |err| {
        printColorLine(session.color_enabled, Color.bright_red, "Call failed: {s}", .{@errorName(err)});
        return;
    };

    if (resolved.signature.results.len > 0) {
        printColorLine(session.color_enabled, Color.bright_green, "Result: {any}", .{result});
    } else {
        printColorLine(session.color_enabled, Color.green, "Call completed", .{});
    }
}

fn parseArgumentsForSignature(expected: []const ValueType, raw_args: []const u8, out: *[max_call_args]Value) ![]const Value {
    var count: usize = 0;
    var it = std.mem.tokenizeAny(u8, raw_args, " \t");

    while (it.next()) |token| {
        if (count >= out.len) return error.TooManyArguments;
        out[count] = try parseTokenAsValue(token, if (count < expected.len) expected[count] else null);
        count += 1;
    }

    if (count != expected.len) return error.ArgumentCountMismatch;
    return out[0..count];
}

fn parseTokenAsValue(token: []const u8, expected_type: ?ValueType) !Value {
    if (expected_type) |typ| {
        return switch (typ) {
            .i32 => Value{ .i32 = std.fmt.parseInt(i32, token, 0) catch return error.InvalidArgument },
            .i64 => Value{ .i64 = std.fmt.parseInt(i64, token, 0) catch return error.InvalidArgument },
            .f32 => Value{ .f32 = std.fmt.parseFloat(f32, token) catch return error.InvalidArgument },
            .f64 => Value{ .f64 = std.fmt.parseFloat(f64, token) catch return error.InvalidArgument },
            else => return error.InvalidArgument,
        };
    }

    if (std.fmt.parseInt(i64, token, 0)) |integer| {
        return Value{ .i64 = integer };
    } else |_| {
        const float = std.fmt.parseFloat(f64, token) catch return error.InvalidArgument;
        return Value{ .f64 = float };
    }

    return error.InvalidArgument;
}

fn buildDefaultArgs(expected: []const ValueType, out: *[max_call_args]Value) ?[]const Value {
    if (expected.len > out.len) return null;

    for (expected, 0..) |typ, idx| {
        out[idx] = switch (typ) {
            .i32 => Value{ .i32 = 0 },
            .i64 => Value{ .i64 = 0 },
            .f32 => Value{ .f32 = 0.0 },
            .f64 => Value{ .f64 = 0.0 },
            else => return null,
        };
    }

    return out[0..expected.len];
}

fn handleLanguageCommand(session: *ShellSession, raw_args: []const u8) void {
    const mode = std.mem.trim(u8, raw_args, &std.ascii.whitespace);
    if (mode.len == 0) {
        printColorLine(session.color_enabled, Color.bright_yellow, "Current language mode: {s}", .{languageLabel(session.preferred_language)});
        printColorLine(session.color_enabled, Color.dim, "Use :lang auto|wat|c|cpp|wasm", .{});
        return;
    }

    const lowered = std.ascii.allocLowerString(session.allocator, mode) catch {
        printColorLine(session.color_enabled, Color.bright_red, "Failed to update language mode", .{});
        return;
    };
    defer session.allocator.free(lowered);

    if (std.mem.eql(u8, lowered, "auto")) {
        session.preferred_language = .auto;
    } else if (std.mem.eql(u8, lowered, "wat")) {
        session.preferred_language = .wat;
    } else if (std.mem.eql(u8, lowered, "c")) {
        session.preferred_language = .c;
    } else if (std.mem.eql(u8, lowered, "cpp") or std.mem.eql(u8, lowered, "c++")) {
        session.preferred_language = .cpp;
    } else if (std.mem.eql(u8, lowered, "wasm")) {
        session.preferred_language = .wasm;
    } else {
        printColorLine(session.color_enabled, Color.bright_red, "Unknown language mode: {s}", .{mode});
        return;
    }

    printColorLine(session.color_enabled, Color.bright_green, "Language mode set to {s}", .{languageLabel(session.preferred_language)});
}

fn runHostCommand(session: *ShellSession, command_text: []const u8) void {
    const command = std.mem.trim(u8, command_text, &std.ascii.whitespace);
    if (command.len == 0) {
        printColorLine(session.color_enabled, Color.bright_yellow, "Usage: !<shell command>", .{});
        return;
    }

    const argv = if (builtin.os.tag == .windows)
        &[_][]const u8{ "cmd", "/C", command }
    else
        &[_][]const u8{ "sh", "-c", command };

    const result = std.process.run(session.allocator, session.io, .{
        .argv = argv,
    }) catch |err| {
        printColorLine(session.color_enabled, Color.bright_red, "Failed to run command: {s}", .{@errorName(err)});
        return;
    };
    defer session.allocator.free(result.stdout);
    defer session.allocator.free(result.stderr);

    if (result.stdout.len > 0) {
        std.debug.print("{s}", .{result.stdout});
    }
    if (result.stderr.len > 0) {
        std.debug.print("{s}", .{result.stderr});
    }
    if (result.term != .exited or result.term.exited != 0) {
        printColorLine(session.color_enabled, Color.bright_red, "Command exited with non-zero status", .{});
    }
}

fn reportCompilationError(session: *ShellSession, err: anyerror) void {
    switch (err) {
        error.UnknownSourceLanguage => {
            printColorLine(session.color_enabled, Color.bright_red, "Unable to detect source language", .{});
            printColorLine(session.color_enabled, Color.dim, "Use :lang to force mode, or :load with .wat/.c/.cpp/.wasm", .{});
        },
        error.InvalidWasmBinary => {
            printColorLine(session.color_enabled, Color.bright_red, "Input is not a valid wasm binary", .{});
        },
        error.Wat2WasmNotFound => {
            printColorLine(session.color_enabled, Color.bright_red, "wat2wasm not found (install wabt)", .{});
        },
        error.Wat2WasmFailed => {
            printColorLine(session.color_enabled, Color.bright_red, "WAT -> WASM conversion failed", .{});
        },
        error.CompilationFailed => {
            printColorLine(session.color_enabled, Color.bright_red, "C/C++ compilation to WASM failed", .{});
            printColorLine(session.color_enabled, Color.dim, "Install WASI SDK clang/clang++ or use zig cc/zig c++", .{});
        },
        else => {
            printColorLine(session.color_enabled, Color.bright_red, "Compilation failed: {s}", .{@errorName(err)});
        },
    }
}

fn splitCommand(input: []const u8) struct { command: []const u8, args: []const u8 } {
    const trimmed = std.mem.trim(u8, input, &std.ascii.whitespace);
    if (trimmed.len == 0) {
        return .{ .command = "", .args = "" };
    }

    const first_ws = std.mem.indexOfAny(u8, trimmed, " \t") orelse {
        return .{ .command = trimmed, .args = "" };
    };

    return .{
        .command = trimmed[0..first_ws],
        .args = std.mem.trim(u8, trimmed[first_ws + 1 ..], &std.ascii.whitespace),
    };
}

fn isLegacyShellCommand(line: []const u8) bool {
    const first = splitCommand(line).command;
    return std.mem.eql(u8, first, "help") or std.mem.eql(u8, first, "?") or
        std.mem.eql(u8, first, "quit") or std.mem.eql(u8, first, "exit") or
        std.mem.eql(u8, first, "exports") or std.mem.eql(u8, first, "exp") or
        std.mem.eql(u8, first, "call") or std.mem.eql(u8, first, "run") or
        std.mem.eql(u8, first, "load") or std.mem.eql(u8, first, "info") or
        std.mem.eql(u8, first, "clear") or std.mem.eql(u8, first, "cls") or
        std.mem.eql(u8, first, "history") or std.mem.eql(u8, first, "lang") or
        std.mem.eql(u8, first, "paste") or std.mem.eql(u8, first, "version");
}

fn readLine(stdin: anytype, line_buffer: []u8, fd: std.posix.fd_t) !?[]const u8 {
    if (builtin.os.tag != .windows) {
        return readLinePosix(line_buffer, fd);
    }

    return readLineBuffered(stdin, line_buffer);
}

fn readLineBuffered(stdin: anytype, line_buffer: []u8) !?[]const u8 {
    var length: usize = 0;

    while (length < line_buffer.len) {
        var one = [_][]u8{line_buffer[length .. length + 1]};
        const read = try stdin.interface.readVec(&one);
        if (read == 0) {
            if (length == 0) return null;
            break;
        }

        if (line_buffer[length] == '\n') break;
        if (line_buffer[length] == '\r') continue;
        length += read;
    }

    if (length == line_buffer.len) {
        while (true) {
            var discard: [1]u8 = undefined;
            var chunk = [_][]u8{discard[0..1]};
            const read = try stdin.interface.readVec(&chunk);
            if (read == 0 or discard[0] == '\n') break;
        }
    }

    return line_buffer[0..length];
}

fn readLinePosix(line_buffer: []u8, fd: std.posix.fd_t) !?[]const u8 {
    var length: usize = 0;

    while (length < line_buffer.len) {
        const read = try std.posix.read(fd, line_buffer[length .. length + 1]);
        if (read == 0) {
            if (length == 0) return null;
            break;
        }

        if (line_buffer[length] == '\n') break;
        if (line_buffer[length] == '\r') continue;
        length += read;
    }

    if (length == line_buffer.len) {
        while (true) {
            var discard: [1]u8 = undefined;
            const read = try std.posix.read(fd, discard[0..1]);
            if (read == 0 or discard[0] == '\n') break;
        }
    }

    return line_buffer[0..length];
}

fn renderPrompt(session: *ShellSession) void {
    const prompt = if (session.paste_mode)
        "....> "
    else if (session.current_module != null)
        "wart*> "
    else
        "wart> ";

    const color = if (session.paste_mode)
        Color.bright_yellow
    else if (session.current_module != null)
        Color.bright_green
    else
        Color.bright_blue;

    if (session.color_enabled) {
        std.debug.print("{s}{s}{s}", .{ color, prompt, Color.reset });
    } else {
        std.debug.print("{s}", .{prompt});
    }
}

fn signatureForFunction(module: *Runtime.Module, index: usize) ?Module.Signature {
    if (index >= module.functions.items.len) return null;
    const func = module.functions.items[index];
    if (func.type_index >= module.types.items.len) return null;
    return module.types.items[func.type_index];
}

fn valueTypeLabel(typ: ValueType) []const u8 {
    return switch (typ) {
        .i32 => "i32",
        .i64 => "i64",
        .f32 => "f32",
        .f64 => "f64",
        .v128 => "v128",
        .funcref => "funcref",
        .externref => "externref",
        .anyref => "anyref",
        .eqref => "eqref",
        .i31ref => "i31ref",
        .structref => "structref",
        .arrayref => "arrayref",
        .nullref => "nullref",
        .block => "block",
    };
}

fn printableExportName(name: []const u8) []const u8 {
    const non_null = if (std.mem.indexOfScalar(u8, name, 0)) |nul_idx| name[0..nul_idx] else name;
    for (non_null, 0..) |byte, idx| {
        if (byte < 0x20 or byte > 0x7e) {
            return non_null[0..idx];
        }
    }
    return non_null;
}

fn formatSignatureAlloc(allocator: std.mem.Allocator, sig: Module.Signature) ![]u8 {
    var output = try std.ArrayList(u8).initCapacity(allocator, 0);
    errdefer output.deinit(allocator);

    try output.append(allocator, '(');
    for (sig.params, 0..) |param, idx| {
        if (idx != 0) try output.appendSlice(allocator, ", ");
        try output.appendSlice(allocator, valueTypeLabel(param));
    }
    try output.append(allocator, ')');

    if (sig.results.len > 0) {
        try output.appendSlice(allocator, " -> (");
        for (sig.results, 0..) |result, idx| {
            if (idx != 0) try output.appendSlice(allocator, ", ");
            try output.appendSlice(allocator, valueTypeLabel(result));
        }
        try output.append(allocator, ')');
    }

    return output.toOwnedSlice(allocator);
}

fn isWasmBinary(bytes: []const u8) bool {
    return bytes.len >= 8 and std.mem.eql(u8, bytes[0..4], "\x00asm") and std.mem.eql(u8, bytes[4..8], "\x01\x00\x00\x00");
}

fn languageLabel(lang: SourceLanguage) []const u8 {
    return switch (lang) {
        .auto => "auto",
        .unknown => "unknown",
        .c => "c",
        .cpp => "c++",
        .wat => "wat",
        .wasm => "wasm",
    };
}

fn printBanner(color_enabled: bool) void {
    printColorLine(color_enabled, Color.bright_cyan, "╔══════════════════════════════════════════════════════╗", .{});
    printColorLine(color_enabled, Color.bright_cyan, "║                wart interactive REPL                 ║", .{});
    printColorLine(color_enabled, Color.bright_cyan, "╚══════════════════════════════════════════════════════╝", .{});
}

fn printHelp(color_enabled: bool) void {
    printLine("", .{});
    printColorLine(color_enabled, Color.bright_yellow, "Input", .{});
    printColorLine(color_enabled, Color.dim, "  Enter WAT/C/C++ source directly and it will transpile -> wasm -> execute", .{});
    printColorLine(color_enabled, Color.dim, "  Enter !! to repeat the previous command", .{});
    printColorLine(color_enabled, Color.dim, "  Enter !<cmd> to run a host shell command", .{});
    printLine("", .{});

    printColorLine(color_enabled, Color.bright_yellow, "Commands", .{});
    printColorLine(color_enabled, Color.bright_cyan, "  :help / :?", .{});
    printColorLine(color_enabled, Color.bright_cyan, "  :load <file>", .{});
    printColorLine(color_enabled, Color.bright_cyan, "  :exports", .{});
    printColorLine(color_enabled, Color.bright_cyan, "  :run [function args...]", .{});
    printColorLine(color_enabled, Color.bright_cyan, "  :call <function> [args...]", .{});
    printColorLine(color_enabled, Color.bright_cyan, "  :lang auto|wat|c|cpp|wasm", .{});
    printColorLine(color_enabled, Color.bright_cyan, "  :paste / :end / :cancel", .{});
    printColorLine(color_enabled, Color.bright_cyan, "  :history", .{});
    printColorLine(color_enabled, Color.bright_cyan, "  :info", .{});
    printColorLine(color_enabled, Color.bright_cyan, "  :clear", .{});
    printColorLine(color_enabled, Color.bright_cyan, "  :quit / :exit", .{});
    printLine("", .{});

    printColorLine(color_enabled, Color.dim, "Legacy command forms without ':' still work for help/exports/call/run/etc", .{});
    printLine("", .{});
}

pub fn help(program_name: []const u8) void {
    printColorLine(true, Color.bright_cyan, "wart shell", .{});
    printLine("", .{});
    printColorLine(true, Color.bright_white, "Usage: {s} shell|repl|sh [module.wasm|module.wat|module.c|module.cpp]", .{program_name});
    printLine("", .{});
    printColorLine(true, Color.dim, "Starts an interactive REPL that transpiles WAT/C/C++ to WASM and executes it.", .{});
    printLine("", .{});
    printColorLine(true, Color.bright_yellow, "Examples", .{});
    printLine("  {s} shell", .{program_name});
    printLine("  {s} repl examples/simple.wasm", .{program_name});
    printLine("  {s} sh examples/hello.wat", .{program_name});
    printLine("  {s} shell examples/program.c", .{program_name});
}

fn printLine(comptime format: []const u8, args: anytype) void {
    std.debug.print(format, args);
    std.debug.print("\n", .{});
}

fn printColorLine(color_enabled: bool, color: []const u8, comptime format: []const u8, args: anytype) void {
    if (color_enabled and color.len > 0 and !std.mem.eql(u8, color, Color.reset)) {
        std.debug.print("{s}", .{color});
        std.debug.print(format, args);
        std.debug.print("{s}\n", .{Color.reset});
    } else {
        printLine(format, args);
    }
}
