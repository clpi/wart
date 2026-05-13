const std = @import("std");

pub const WasiNn = struct {
    allocator: std.mem.Allocator,
    models: std.AutoHashMap(u32, Model),
    contexts: std.AutoHashMap(u32, Context),
    next_model_handle: u32,
    next_context_handle: u32,

    const Model = struct {
        blob: []u8,
    };

    const Context = struct {
        model_handle: u32,
        input: []u8,
        output: []u8,
    };

    pub fn init(allocator: std.mem.Allocator) !*WasiNn {
        const nn = try allocator.create(WasiNn);
        nn.* = .{
            .allocator = allocator,
            .models = std.AutoHashMap(u32, Model).init(allocator),
            .contexts = std.AutoHashMap(u32, Context).init(allocator),
            .next_model_handle = 1,
            .next_context_handle = 1,
        };
        return nn;
    }

    pub fn deinit(self: *WasiNn) void {
        {
            var it = self.models.iterator();
            while (it.next()) |entry| {
                self.allocator.free(entry.value_ptr.blob);
            }
        }
        {
            var it = self.contexts.iterator();
            while (it.next()) |entry| {
                self.allocator.free(entry.value_ptr.input);
                self.allocator.free(entry.value_ptr.output);
            }
        }
        self.models.deinit();
        self.contexts.deinit();
        self.allocator.destroy(self);
    }

    pub fn loadModel(self: *WasiNn, blob: []const u8) !u32 {
        const handle = self.next_model_handle;
        self.next_model_handle += 1;

        try self.models.putNoClobber(handle, .{
            .blob = try self.allocator.dupe(u8, blob),
        });
        return handle;
    }

    pub fn initExecutionContext(self: *WasiNn, model_handle: u32) !u32 {
        if (!self.models.contains(model_handle)) {
            return error.InvalidModelHandle;
        }

        const handle = self.next_context_handle;
        self.next_context_handle += 1;

        try self.contexts.putNoClobber(handle, .{
            .model_handle = model_handle,
            .input = &[_]u8{},
            .output = &[_]u8{},
        });
        return handle;
    }

    pub fn setInput(self: *WasiNn, context_handle: u32, _: u32, data: []const u8) !void {
        const ctx = self.contexts.getPtr(context_handle) orelse return error.InvalidContextHandle;
        if (ctx.input.len > 0) {
            self.allocator.free(ctx.input);
        }
        ctx.input = try self.allocator.dupe(u8, data);
    }

    pub fn compute(self: *WasiNn, context_handle: u32) !void {
        const ctx = self.contexts.getPtr(context_handle) orelse return error.InvalidContextHandle;
        const model = self.models.get(ctx.model_handle) orelse return error.InvalidModelHandle;

        if (ctx.output.len > 0) {
            self.allocator.free(ctx.output);
        }

        // Lightweight deterministic "inference" kernel so runtimes can benchmark host-call overhead
        // without tying this to a specific backend.
        var acc: u32 = 2166136261;
        for (model.blob) |b| {
            acc = (acc ^ b) *% 16777619;
        }
        for (ctx.input) |b| {
            acc = (acc ^ b) *% 16777619;
        }

        const out_len = @max(ctx.input.len, 16);
        const out = try self.allocator.alloc(u8, out_len);
        for (out, 0..) |*slot, i| {
            const shift = @as(u5, @intCast((i % 4) * 8));
            slot.* = @truncate((acc >> shift) +% @as(u32, @intCast(i * 31)));
        }
        ctx.output = out;
    }

    pub fn getOutput(self: *WasiNn, context_handle: u32, _: u32, dst: []u8) !usize {
        const ctx = self.contexts.get(context_handle) orelse return error.InvalidContextHandle;
        const copied = @min(dst.len, ctx.output.len);
        @memcpy(dst[0..copied], ctx.output[0..copied]);
        return copied;
    }
};
