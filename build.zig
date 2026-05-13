const std = @import("std");

const Build = std.Build;
const Version = std.SemanticVersion;

pub fn libtest(b: *std.Build) *std.Build.Step.Run {
    const cache_dir = b.pathFromRoot("zig-cache");
    const global_cache = b.pathFromRoot("zig-cache/global-tests");
    const root_test = b.pathFromRoot("src/root.zig");
    const test_cmd = b.addSystemCommand(&[_][]const u8{
        "zig",
        "test",
        root_test,
        "--cache-dir",
        cache_dir,
        "--global-cache-dir",
        global_cache,
        "-O",
        "ReleaseFast",
    });
    return test_cmd;
}

pub const version: Version = .{
    .build = "0",
    .major = 0,
    .patch = 0,
    .minor = 0,
    .pre = "alpha",
};

pub fn exetest(b: *std.Build) *std.Build.Step.Run {
    const cache_dir = b.pathFromRoot("zig-cache");
    const global_cache = b.pathFromRoot("zig-cache/global-tests");
    const main_test = b.pathFromRoot("src/main.zig");
    std.debug.print("Running tests for version {d}.{d}.{d}-{s}\n", .{ version.major, version.minor, version.patch, version.pre orelse "" });
    const test_cmd = b.addSystemCommand(&[_][]const u8{
        "zig",
        "test",
        main_test,
        "--cache-dir",
        cache_dir,
        "--global-cache-dir",
        global_cache,
        "-O",
        "ReleaseFast",
    });
    return test_cmd;
}

fn addStandaloneTest(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    root_path: []const u8,
) *std.Build.Step.Run {
    const sync_module = b.createModule(.{
        .root_source_file = b.path("src/util/sync.zig"),
        .target = target,
        .optimize = optimize,
    });
    const root_module = b.createModule(.{
        .root_source_file = b.path(root_path),
        .target = target,
        .optimize = optimize,
    });
    root_module.addImport("sync", sync_module);
    root_module.addImport("wasi_cli", b.createModule(.{
        .root_source_file = b.path("src/wasm/wasi/cli.zig"),
        .target = target,
        .optimize = optimize,
    }));
    root_module.addImport("wasi_http", b.createModule(.{
        .root_source_file = b.path("src/wasm/wasi/http.zig"),
        .target = target,
        .optimize = optimize,
    }));
    const wasi_concurrency_module = b.createModule(.{
        .root_source_file = b.path("src/wasm/wasi/concurrency.zig"),
        .target = target,
        .optimize = optimize,
    });
    wasi_concurrency_module.addImport("sync", sync_module);
    root_module.addImport("wasi_concurrency", wasi_concurrency_module);
    root_module.addImport("wasi_nn", b.createModule(.{
        .root_source_file = b.path("src/wasm/wasi/nn.zig"),
        .target = target,
        .optimize = optimize,
    }));
    root_module.addImport("cmd_root", b.createModule(.{
        .root_source_file = b.path("src/cmd.zig"),
        .target = target,
        .optimize = optimize,
    }));

    const tests = b.addTest(.{ .root_module = root_module });
    return b.addRunArtifact(tests);
}

pub fn exeopts(
    b: *std.Build,
    t: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    use_llvm: bool,
    use_lld: bool,
) *std.Build.Step.Compile {
    const root_module = b.createModule(.{
        .sanitize_c = .off,
        .valgrind = false,
        .root_source_file = b.path("src/main.zig"),
        .error_tracing = false,
        .link_libc = true,
        .link_libcpp = true,
        .no_builtin = true,
        .sanitize_thread = false,
        .single_threaded = true,
        .stack_protector = false,
        .unwind_tables = .none,
        .omit_frame_pointer = true,
        .red_zone = false,

        .stack_check = false,
        .dwarf_format = null,
        .strip = true,
        .code_model = .small,
        .target = t,
        .optimize = optimize,
    });
    root_module.addImport("sync", b.createModule(.{
        .root_source_file = b.path("src/util/sync.zig"),
        .target = t,
        .optimize = optimize,
    }));

    const exe = b.addExecutable(.{
        .name = "wart",
        .use_llvm = use_llvm,
        .use_lld = use_lld,
        .root_module = root_module,
        .version = version,
        .linkage = .dynamic,
    });
    exe.pie = true;
    exe.root_module.strip = true;
    exe.root_module.sanitize_thread = false;
    exe.root_module.single_threaded = true;
    exe.root_module.omit_frame_pointer = true;
    exe.root_module.error_tracing = false; // Disable error tracing for max performance
    exe.root_module.red_zone = false; // Disable red zone for maximum call speed
    exe.root_module.optimize = optimize;
    exe.root_module.stack_protector = false; // Disable stack protector for speed
    exe.root_module.unwind_tables = .none; // No unwind tables for maximum speed

    b.installArtifact(exe);
    return exe;
}
pub fn libopts(b: *std.Build, t: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Step.Compile {
    const root_module = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .no_builtin = true,
        .unwind_tables = .async,
        .sanitize_c = .off,
        .single_threaded = true,
        .stack_protector = false,
        .omit_frame_pointer = true,
        .link_libc = true,
        .link_libcpp = true,
        .red_zone = false,
        .stack_check = false,
        .error_tracing = false,
        .sanitize_thread = false,
        .valgrind = false,
        .strip = true,
        .pic = true,
        .target = t,
        .optimize = optimize,
    });
    root_module.addImport("sync", b.createModule(.{
        .root_source_file = b.path("src/util/sync.zig"),
        .target = t,
        .optimize = optimize,
    }));

    const lib = b.addSharedLibrary(.{
        .name = "wartlib",
        .version = version,
        .root_module = root_module,
    });
    lib.pie = true;
    lib.root_module.strip = true;
    lib.linkLibC();
    lib.root_module.omit_frame_pointer = true;
    lib.root_module.single_threaded = true;
    lib.root_module.error_tracing = true;
    lib.root_module.sanitize_thread = false;
    b.installArtifact(lib);
    return lib;
}

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    b.cache_root = .{ .path = ".zig-cache", .handle = std.Io.Dir.cwd() };

    // Enable parallel compilation and native CPU optimizations for maximum performance
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseFast });
    const use_llvm = b.option(bool, "use-llvm", "Use LLVM backend") orelse true;
    const use_lld = b.option(bool, "use-lld", "Use LLD linker") orelse false; // macOS doesn't support LLD

    const exe = exeopts(b, target, optimize, use_llvm, use_lld);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args|
        run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run unit tests");

    const minimal_test_cmd = addStandaloneTest(b, target, optimize, "test/minimal_test.zig");
    test_step.dependOn(&minimal_test_cmd.step);

    const features_test_cmd = addStandaloneTest(b, target, optimize, "test/features_test.zig");
    test_step.dependOn(&features_test_cmd.step);

    const phase0_cli_test_cmd = addStandaloneTest(b, target, optimize, "test/phase0_cli_test.zig");
    test_step.dependOn(&phase0_cli_test_cmd.step);

    // Build a WASI WASM CLI that exercises opcodes
    const wasm_target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .wasi });
    const wasi2_benchmark = b.addExecutable(.{
        .name = "wasi2_benchmark",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/wasi2_benchmark.zig"),
            .target = wasm_target,
            .optimize = .ReleaseSmall,
        }),
    });
    wasi2_benchmark.entry = .disabled;
    wasi2_benchmark.rdynamic = true;

    const install_wasi2_benchmark = b.addInstallArtifact(wasi2_benchmark, .{
        .dest_dir = .{ .override = .{ .custom = "bin" } },
    });

    const wasi2_benchmark_step = b.step("wasi2-benchmark", "Build WASI 2 + WIT IDL + Concurrency benchmark");
    wasi2_benchmark_step.dependOn(&install_wasi2_benchmark.step);

    const opcodes_cli = b.addExecutable(.{
        .name = "opcodes_cli",
        .use_llvm = true,
        .use_lld = true,
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/opcodes_cli/main.zig"),
            .target = wasm_target,
            .optimize = .ReleaseSmall,
            .link_libc = true,
        }),
    });
    b.installArtifact(opcodes_cli);

    const build_wasm = b.step("opcodes-wasm", "Build WASI opcodes CLI (.wasm)");
    build_wasm.dependOn(&opcodes_cli.step);

    const bench_cmd = b.addSystemCommand(&[_][]const u8{ "bash", "bench.sh" });
    const bench_step = b.step("bench", "Run cross-runtime benchmarks");
    bench_step.dependOn(&bench_cmd.step);

    const bench_core_cmd = b.addSystemCommand(&[_][]const u8{
        "bash",
        "scripts/run-benchmarks.sh",
        "--profile",
        "core-universal",
        "--format",
        "markdown",
        "--output",
        "bench/results",
    });
    const bench_core_step = b.step("bench-core", "Run pinned benchmark gate");
    bench_core_step.dependOn(&bench_core_cmd.step);

    const verify_spec_cmd = b.addSystemCommand(&[_][]const u8{
        "bash",
        "scripts/run-spec-tests.sh",
        "--profile",
        "all",
        "--format",
        "markdown",
        "--output",
        "artifacts/spec",
    });
    const verify_spec_step = b.step("verify-spec", "Run pinned spec verification");
    verify_spec_step.dependOn(&verify_spec_cmd.step);
}
