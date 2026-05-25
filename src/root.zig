const std = @import("std");
pub const rt = @import("wasm/runtime.zig");
pub const op = @import("wasm/op.zig");
pub const module = @import("wasm/module.zig");
pub const js = @import("js/api.zig");

// WASI support - all versions
pub const wasi = @import("wasm/wasi.zig"); // WASI Preview 1
pub const wasi2 = @import("wasm/wasi2.zig"); // WASI Preview 2 (0.2)
pub const wasi3 = @import("wasm/wasi3.zig"); // WASI Preview 3 (experimental)
pub const wasi_nn = @import("wasm/wasi/nn.zig"); // WASI NN helper
pub const wasix = @import("wasm/wasix.zig"); // WASIX - Extended WASI
pub const wasix_ext = @import("wasm/wasix_ext.zig"); // WASIX Advanced Extensions

pub const jit = @import("wasm/jit.zig");
pub const aot = @import("wasm/aot.zig");
pub const SmallVec = @import("wasm/stack.zig").SmallVec;
pub const testing = std.testing;
pub const fmt = @import("util/fmt.zig");
pub const value = @import("wasm/value.zig");
pub const Component = @import("wasm/component.zig").Component;

// WASM 3.0 Features
pub const exception = @import("wasm/exception.zig"); // Exception Handling
pub const multi_memory = @import("wasm/multi_memory.zig"); // Multi-Memory
pub const fast_dispatch = @import("wasm/fast_dispatch.zig"); // Optimized Dispatch
pub const bulk_memory = @import("wasm/bulk_memory.zig"); // Bulk Memory Ops
pub const threads = @import("wasm/threads.zig"); // Thread Support

// Project and packaging support
pub const manifest = @import("manifest.zig"); // wart.toml manifest parsing
pub const pack = @import("pack.zig"); // Package creation
