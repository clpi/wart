const std = @import("std");

pub const FeatureGroup = struct {
    status: []const u8,
    note: []const u8,
    features: []const []const u8,
};

pub const BenchmarkProfile = struct {
    name: []const u8,
    status: []const u8,
    description: []const u8,
};

pub const CapabilityReport = struct {
    lock_date: []const u8,
    wasm_features: FeatureGroup,
    wasi_preview1: FeatureGroup,
    wasi_preview2: FeatureGroup,
    wasi_components: FeatureGroup,
    wasix: FeatureGroup,
    benchmark_profiles: []const BenchmarkProfile,
};

const wasm_feature_list = [_][]const u8{
    "mvp",
    "bulk-memory",
    "reference-types",
    "simd",
    "memory64",
    "threads",
    "tail-call",
    "exception-handling",
    "gc",
    "multi-memory",
};

const wasi_preview1_feature_list = [_][]const u8{
    "args",
    "env",
    "filesystem",
    "clocks",
    "random",
    "poll",
};

const wasi_preview2_feature_list = [_][]const u8{
    "cli",
    "clocks",
    "io",
    "random",
    "poll",
    "http",
    "sockets",
    "concurrency",
};

const component_feature_list = [_][]const u8{
    "component-parser",
    "canonical-abi",
    "wit-idl",
    "resource-tables",
};

const wasix_feature_list = [_][]const u8{
    "process-lifecycle",
    "pipes",
    "sockets",
    "udp",
    "scheduler",
    "shared-memory",
};

const benchmark_profile_list = [_]BenchmarkProfile{
    .{
        .name = "core-universal",
        .status = "ready",
        .description = "Pinned cross-runtime gate for workloads expected to run everywhere.",
    },
    .{
        .name = "preview1",
        .status = "ready",
        .description = "Pinned WASI Preview 1 workloads with explicit output hashing.",
    },
    .{
        .name = "components",
        .status = "placeholder",
        .description = "Reserved for component-model and WIT benchmarks once linked fixtures are live.",
    },
    .{
        .name = "wasix",
        .status = "placeholder",
        .description = "Reserved for WASIX black-box benchmarks once guest fixtures are wired in.",
    },
};

pub fn report() CapabilityReport {
    return .{
        .lock_date = "2026-03-04",
        .wasm_features = .{
            .status = "partial",
            .note = "Feature modules exist, but pinned upstream conformance is not yet green.",
            .features = &wasm_feature_list,
        },
        .wasi_preview1 = .{
            .status = "partial",
            .note = "Preview 1 coverage exists in the runtime, but the pinned upstream suite is not yet fully integrated.",
            .features = &wasi_preview1_feature_list,
        },
        .wasi_preview2 = .{
            .status = "partial",
            .note = "Preview 2 APIs are present, but several paths are still mocked or incomplete.",
            .features = &wasi_preview2_feature_list,
        },
        .wasi_components = .{
            .status = "partial",
            .note = "Component parsing exists, but linked-component execution and WIT round-trips are not fully verified.",
            .features = &component_feature_list,
        },
        .wasix = .{
            .status = "experimental",
            .note = "WASIX modules exist, but full black-box compatibility and performance gating are not complete.",
            .features = &wasix_feature_list,
        },
        .benchmark_profiles = &benchmark_profile_list,
    };
}

pub fn renderJsonAlloc(allocator: std.mem.Allocator) ![]u8 {
    var aw = std.Io.Writer.Allocating.init(allocator);
    defer aw.deinit();
    const writer = &aw.writer;
    const capability_report = report();

    try writer.writeAll("{\n");
    try writer.writeAll("  \"lock_date\": ");
    try writeJsonString(writer, capability_report.lock_date);
    try writer.writeAll(",\n  \"wasm_features\": ");
    try writeFeatureGroupJson(writer, capability_report.wasm_features);
    try writer.writeAll(",\n  \"wasi_preview1\": ");
    try writeFeatureGroupJson(writer, capability_report.wasi_preview1);
    try writer.writeAll(",\n  \"wasi_preview2\": ");
    try writeFeatureGroupJson(writer, capability_report.wasi_preview2);
    try writer.writeAll(",\n  \"wasi_components\": ");
    try writeFeatureGroupJson(writer, capability_report.wasi_components);
    try writer.writeAll(",\n  \"wasix\": ");
    try writeFeatureGroupJson(writer, capability_report.wasix);
    try writer.writeAll(",\n  \"benchmark_profiles\": [\n");
    for (capability_report.benchmark_profiles, 0..) |profile, index| {
        if (index != 0) try writer.writeAll(",\n");
        try writer.writeAll("    {\"name\": ");
        try writeJsonString(writer, profile.name);
        try writer.writeAll(", \"status\": ");
        try writeJsonString(writer, profile.status);
        try writer.writeAll(", \"description\": ");
        try writeJsonString(writer, profile.description);
        try writer.writeAll("}");
    }
    try writer.writeAll("\n  ]\n}\n");

    return aw.toOwnedSlice();
}

pub fn renderMarkdownAlloc(allocator: std.mem.Allocator) ![]u8 {
    var aw = std.Io.Writer.Allocating.init(allocator);
    defer aw.deinit();
    const writer = &aw.writer;
    const capability_report = report();

    try writer.writeAll("# Capability Report\n\n");
    try writeFeatureGroup(writer, "WebAssembly", capability_report.wasm_features);
    try writeFeatureGroup(writer, "WASI Preview 1", capability_report.wasi_preview1);
    try writeFeatureGroup(writer, "WASI Preview 2", capability_report.wasi_preview2);
    try writeFeatureGroup(writer, "Components and WIT", capability_report.wasi_components);
    try writeFeatureGroup(writer, "WASIX", capability_report.wasix);
    try writer.writeAll("## Benchmark Profiles\n");
    for (capability_report.benchmark_profiles) |profile| {
        try writer.print("- `{s}`: {s}. {s}\n", .{ profile.name, profile.status, profile.description });
    }

    return aw.toOwnedSlice();
}

fn writeFeatureGroup(writer: anytype, title: []const u8, group: FeatureGroup) !void {
    try writer.print("## {s}\n", .{title});
    try writer.print("- Status: `{s}`\n", .{group.status});
    try writer.print("- Note: {s}\n", .{group.note});
    try writer.writeAll("- Features:");
    if (group.features.len == 0) {
        try writer.writeAll(" none\n\n");
        return;
    }
    try writer.writeAll("\n");
    for (group.features) |feature| {
        try writer.print("  - `{s}`\n", .{feature});
    }
    try writer.writeAll("\n");
}

fn writeFeatureGroupJson(writer: anytype, group: FeatureGroup) !void {
    try writer.writeAll("{\"status\": ");
    try writeJsonString(writer, group.status);
    try writer.writeAll(", \"note\": ");
    try writeJsonString(writer, group.note);
    try writer.writeAll(", \"features\": [");
    for (group.features, 0..) |feature, index| {
        if (index != 0) try writer.writeAll(", ");
        try writeJsonString(writer, feature);
    }
    try writer.writeAll("]}");
}

fn writeJsonString(writer: anytype, value: []const u8) !void {
    try writer.writeByte('"');
    for (value) |byte| {
        switch (byte) {
            '\\' => try writer.writeAll("\\\\"),
            '"' => try writer.writeAll("\\\""),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => try writer.writeByte(byte),
        }
    }
    try writer.writeByte('"');
}
