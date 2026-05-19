/// SIMD operations implementation for WebAssembly v128
/// This module handles all SIMD (0xFD prefix) instructions
const std = @import("std");
const Value = @import("value.zig").Value;
const simd = @import("simd.zig");
const V128 = @import("op/simd.zig").V128;
const Module = @import("module.zig");
const Error = @import("op.zig").Error;
const SmallVec = @import("stack.zig").SmallVec;

/// Execute a SIMD operation given the sub-opcode
pub fn executeSIMD(
    stack: *SmallVec(Value, 256),
    memory: ?[]u8,
    reader: *Module.Reader,
    simd_opcode: u32,
    allocator: std.mem.Allocator,
) !void {
    const op = V128.fromU32(simd_opcode) orelse return Error.InvalidOpcode;

    switch (op) {
        // ===== MEMORY OPERATIONS =====

        .load => {
            const flags = try reader.readLEB128();
            const offset = try reader.readLEB128();
            _ = flags;

            if (stack.items.len < 1) return Error.StackUnderflow;
            const addr_val = stack.pop().?;
            const addr = @as(u32, @bitCast(addr_val.i32)) + @as(u32, @intCast(offset));

            if (memory) |mem| {
                if (addr + 16 > mem.len) return Error.InvalidAccess;
                var v128_val: [16]u8 = undefined;
                @memcpy(&v128_val, mem[addr .. addr + 16]);
                try stack.append(allocator, .{ .v128 = v128_val });
            } else {
                return Error.InvalidAccess;
            }
        },

        .store => {
            const flags = try reader.readLEB128();
            const offset = try reader.readLEB128();
            _ = flags;

            if (stack.items.len < 2) return Error.StackUnderflow;
            const v = stack.pop().?.v128;
            const addr_val = stack.pop().?;
            const addr = @as(u32, @bitCast(addr_val.i32)) + @as(u32, @intCast(offset));

            if (memory) |mem| {
                if (addr + 16 > mem.len) return Error.InvalidAccess;
                @memcpy(mem[addr .. addr + 16], &v);
            } else {
                return Error.InvalidAccess;
            }
        },

        .@"const" => {
            var bytes: [16]u8 = undefined;
            for (0..16) |i| {
                bytes[i] = try reader.readByte();
            }
            try stack.append(allocator, .{ .v128 = bytes });
        },

        // Load with extension operations
        .load8x8_s, .load8x8_u, .load16x4_s, .load16x4_u, .load32x2_s, .load32x2_u => {
            const flags = try reader.readLEB128();
            const offset = try reader.readLEB128();
            _ = flags;

            if (stack.items.len < 1) return Error.StackUnderflow;
            const addr_val = stack.pop().?;
            const addr = @as(u32, @bitCast(addr_val.i32)) + @as(u32, @intCast(offset));

            if (memory) |mem| {
                var result: [16]u8 = undefined;
                switch (op) {
                    .load8x8_s => {
                        if (addr + 8 > mem.len) return Error.InvalidAccess;
                        for (0..8) |i| {
                            const val: i8 = @bitCast(mem[addr + i]);
                            const extended: i16 = val;
                            const idx = i * 2;
                            result[idx] = @truncate(@as(u16, @bitCast(extended)));
                            result[idx + 1] = @truncate(@as(u16, @bitCast(extended)) >> 8);
                        }
                    },
                    .load8x8_u => {
                        if (addr + 8 > mem.len) return Error.InvalidAccess;
                        for (0..8) |i| {
                            const val: u8 = mem[addr + i];
                            const extended: u16 = val;
                            const idx = i * 2;
                            result[idx] = @truncate(extended);
                            result[idx + 1] = @truncate(extended >> 8);
                        }
                    },
                    .load16x4_s => {
                        if (addr + 8 > mem.len) return Error.InvalidAccess;
                        for (0..4) |i| {
                            const val: i16 = @bitCast(std.mem.readInt(u16, mem[addr + i * 2 ..][0..2], .little));
                            const extended: i32 = val;
                            const idx = i * 4;
                            const u_val: u32 = @bitCast(extended);
                            result[idx] = @truncate(u_val);
                            result[idx + 1] = @truncate(u_val >> 8);
                            result[idx + 2] = @truncate(u_val >> 16);
                            result[idx + 3] = @truncate(u_val >> 24);
                        }
                    },
                    .load16x4_u => {
                        if (addr + 8 > mem.len) return Error.InvalidAccess;
                        for (0..4) |i| {
                            const val: u16 = std.mem.readInt(u16, mem[addr + i * 2 ..][0..2], .little);
                            const extended: u32 = val;
                            const idx = i * 4;
                            result[idx] = @truncate(extended);
                            result[idx + 1] = @truncate(extended >> 8);
                            result[idx + 2] = @truncate(extended >> 16);
                            result[idx + 3] = @truncate(extended >> 24);
                        }
                    },
                    .load32x2_s => {
                        if (addr + 8 > mem.len) return Error.InvalidAccess;
                        for (0..2) |i| {
                            const val: i32 = @bitCast(std.mem.readInt(u32, mem[addr + i * 4 ..][0..4], .little));
                            const extended: i64 = val;
                            const idx = i * 8;
                            const u_val: u64 = @bitCast(extended);
                            result[idx] = @truncate(u_val);
                            result[idx + 1] = @truncate(u_val >> 8);
                            result[idx + 2] = @truncate(u_val >> 16);
                            result[idx + 3] = @truncate(u_val >> 24);
                            result[idx + 4] = @truncate(u_val >> 32);
                            result[idx + 5] = @truncate(u_val >> 40);
                            result[idx + 6] = @truncate(u_val >> 48);
                            result[idx + 7] = @truncate(u_val >> 56);
                        }
                    },
                    .load32x2_u => {
                        if (addr + 8 > mem.len) return Error.InvalidAccess;
                        for (0..2) |i| {
                            const val: u32 = std.mem.readInt(u32, mem[addr + i * 4 ..][0..4], .little);
                            const extended: u64 = val;
                            const idx = i * 8;
                            result[idx] = @truncate(extended);
                            result[idx + 1] = @truncate(extended >> 8);
                            result[idx + 2] = @truncate(extended >> 16);
                            result[idx + 3] = @truncate(extended >> 24);
                            result[idx + 4] = @truncate(extended >> 32);
                            result[idx + 5] = @truncate(extended >> 40);
                            result[idx + 6] = @truncate(extended >> 48);
                            result[idx + 7] = @truncate(extended >> 56);
                        }
                    },
                    else => return Error.InvalidOpcode,
                }
                try stack.append(allocator, .{ .v128 = result });
            } else {
                return Error.InvalidAccess;
            }
        },

        // Load splat operations
        .load8_splat => {
            const flags = try reader.readLEB128();
            const offset = try reader.readLEB128();
            _ = flags;

            if (stack.items.len < 1) return Error.StackUnderflow;
            const addr_val = stack.pop().?;
            const addr = @as(u32, @bitCast(addr_val.i32)) + @as(u32, @intCast(offset));

            if (memory) |mem| {
                if (addr + 1 > mem.len) return Error.InvalidAccess;
                const val = mem[addr];
                try stack.append(allocator, .{ .v128 = [_]u8{ val, val, val, val, val, val, val, val, val, val, val, val, val, val, val, val } });
            } else {
                return Error.InvalidAccess;
            }
        },

        .load16_splat => {
            const flags = try reader.readLEB128();
            const offset = try reader.readLEB128();
            _ = flags;

            if (stack.items.len < 1) return Error.StackUnderflow;
            const addr_val = stack.pop().?;
            const addr = @as(u32, @bitCast(addr_val.i32)) + @as(u32, @intCast(offset));

            if (memory) |mem| {
                if (addr + 2 > mem.len) return Error.InvalidAccess;
                const val = std.mem.readInt(u16, mem[addr..][0..2], .little);
                var result: [16]u8 = undefined;
                for (0..8) |i| {
                    const idx = i * 2;
                    result[idx] = @truncate(val);
                    result[idx + 1] = @truncate(val >> 8);
                }
                try stack.append(allocator, .{ .v128 = result });
            } else {
                return Error.InvalidAccess;
            }
        },

        .load32_splat => {
            const flags = try reader.readLEB128();
            const offset = try reader.readLEB128();
            _ = flags;

            if (stack.items.len < 1) return Error.StackUnderflow;
            const addr_val = stack.pop().?;
            const addr = @as(u32, @bitCast(addr_val.i32)) + @as(u32, @intCast(offset));

            if (memory) |mem| {
                if (addr + 4 > mem.len) return Error.InvalidAccess;
                const val = std.mem.readInt(u32, mem[addr..][0..4], .little);
                var result: [16]u8 = undefined;
                for (0..4) |i| {
                    const idx = i * 4;
                    result[idx] = @truncate(val);
                    result[idx + 1] = @truncate(val >> 8);
                    result[idx + 2] = @truncate(val >> 16);
                    result[idx + 3] = @truncate(val >> 24);
                }
                try stack.append(allocator, .{ .v128 = result });
            } else {
                return Error.InvalidAccess;
            }
        },

        .load64_splat => {
            const flags = try reader.readLEB128();
            const offset = try reader.readLEB128();
            _ = flags;

            if (stack.items.len < 1) return Error.StackUnderflow;
            const addr_val = stack.pop().?;
            const addr = @as(u32, @bitCast(addr_val.i32)) + @as(u32, @intCast(offset));

            if (memory) |mem| {
                if (addr + 8 > mem.len) return Error.InvalidAccess;
                const val = std.mem.readInt(u64, mem[addr..][0..8], .little);
                var result: [16]u8 = undefined;
                for (0..2) |i| {
                    const idx = i * 8;
                    result[idx] = @truncate(val);
                    result[idx + 1] = @truncate(val >> 8);
                    result[idx + 2] = @truncate(val >> 16);
                    result[idx + 3] = @truncate(val >> 24);
                    result[idx + 4] = @truncate(val >> 32);
                    result[idx + 5] = @truncate(val >> 40);
                    result[idx + 6] = @truncate(val >> 48);
                    result[idx + 7] = @truncate(val >> 56);
                }
                try stack.append(allocator, .{ .v128 = result });
            } else {
                return Error.InvalidAccess;
            }
        },

        .v128_load32_zero => {
            const flags = try reader.readLEB128();
            const offset = try reader.readLEB128();
            _ = flags;

            if (stack.items.len < 1) return Error.StackUnderflow;
            const addr_val = stack.pop().?;
            const addr = @as(u32, @bitCast(addr_val.i32)) + @as(u32, @intCast(offset));

            if (memory) |mem| {
                if (addr + 4 > mem.len) return Error.InvalidAccess;
                var result: [16]u8 = .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
                @memcpy(result[0..4], mem[addr .. addr + 4]);
                try stack.append(allocator, .{ .v128 = result });
            } else {
                return Error.InvalidAccess;
            }
        },

        .v128_load64_zero => {
            const flags = try reader.readLEB128();
            const offset = try reader.readLEB128();
            _ = flags;

            if (stack.items.len < 1) return Error.StackUnderflow;
            const addr_val = stack.pop().?;
            const addr = @as(u32, @bitCast(addr_val.i32)) + @as(u32, @intCast(offset));

            if (memory) |mem| {
                if (addr + 8 > mem.len) return Error.InvalidAccess;
                var result: [16]u8 = .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
                @memcpy(result[0..8], mem[addr .. addr + 8]);
                try stack.append(allocator, .{ .v128 = result });
            } else {
                return Error.InvalidAccess;
            }
        },

        // ===== SPLAT OPERATIONS =====

        .i8x16_splat => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const val = stack.pop().?;
            const byte: u8 = @truncate(@as(u32, @bitCast(val.i32)));
            try stack.append(allocator, .{ .v128 = [_]u8{ byte, byte, byte, byte, byte, byte, byte, byte, byte, byte, byte, byte, byte, byte, byte, byte } });
        },

        .i16x8_splat => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const val = stack.pop().?;
            const u16_val: u16 = @truncate(@as(u32, @bitCast(val.i32)));
            var result: [16]u8 = undefined;
            for (0..8) |i| {
                const idx = i * 2;
                result[idx] = @truncate(u16_val);
                result[idx + 1] = @truncate(u16_val >> 8);
            }
            try stack.append(allocator, .{ .v128 = result });
        },

        .i32x4_splat => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const val = stack.pop().?;
            const u32_val: u32 = @bitCast(val.i32);
            var result: [16]u8 = undefined;
            for (0..4) |i| {
                const idx = i * 4;
                result[idx] = @truncate(u32_val);
                result[idx + 1] = @truncate(u32_val >> 8);
                result[idx + 2] = @truncate(u32_val >> 16);
                result[idx + 3] = @truncate(u32_val >> 24);
            }
            try stack.append(allocator, .{ .v128 = result });
        },

        .i64x2_splat => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const val = stack.pop().?;
            const u64_val: u64 = @bitCast(val.i64);
            var result: [16]u8 = undefined;
            for (0..2) |i| {
                const idx = i * 8;
                result[idx] = @truncate(u64_val);
                result[idx + 1] = @truncate(u64_val >> 8);
                result[idx + 2] = @truncate(u64_val >> 16);
                result[idx + 3] = @truncate(u64_val >> 24);
                result[idx + 4] = @truncate(u64_val >> 32);
                result[idx + 5] = @truncate(u64_val >> 40);
                result[idx + 6] = @truncate(u64_val >> 48);
                result[idx + 7] = @truncate(u64_val >> 56);
            }
            try stack.append(allocator, .{ .v128 = result });
        },

        .f32x4_splat => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const val = stack.pop().?;
            const u32_val: u32 = @bitCast(val.f32);
            var result: [16]u8 = undefined;
            for (0..4) |i| {
                const idx = i * 4;
                result[idx] = @truncate(u32_val);
                result[idx + 1] = @truncate(u32_val >> 8);
                result[idx + 2] = @truncate(u32_val >> 16);
                result[idx + 3] = @truncate(u32_val >> 24);
            }
            try stack.append(allocator, .{ .v128 = result });
        },

        .f64x2_splat => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const val = stack.pop().?;
            const u64_val: u64 = @bitCast(val.f64);
            var result: [16]u8 = undefined;
            for (0..2) |i| {
                const idx = i * 8;
                result[idx] = @truncate(u64_val);
                result[idx + 1] = @truncate(u64_val >> 8);
                result[idx + 2] = @truncate(u64_val >> 16);
                result[idx + 3] = @truncate(u64_val >> 24);
                result[idx + 4] = @truncate(u64_val >> 32);
                result[idx + 5] = @truncate(u64_val >> 40);
                result[idx + 6] = @truncate(u64_val >> 48);
                result[idx + 7] = @truncate(u64_val >> 56);
            }
            try stack.append(allocator, .{ .v128 = result });
        },

        // ===== LANE EXTRACT/REPLACE OPERATIONS =====

        .i8x16_extract_lane_s => {
            const lane = try reader.readByte();
            if (lane >= 16) return Error.InvalidOpcode;
            if (stack.items.len < 1) return Error.StackUnderflow;
            const v = stack.pop().?.v128;
            const byte: i8 = @bitCast(v[lane]);
            try stack.append(allocator, .{ .i32 = byte });
        },

        .i8x16_extract_lane_u => {
            const lane = try reader.readByte();
            if (lane >= 16) return Error.InvalidOpcode;
            if (stack.items.len < 1) return Error.StackUnderflow;
            const v = stack.pop().?.v128;
            try stack.append(allocator, .{ .i32 = v[lane] });
        },

        .i8x16_replace_lane => {
            const lane = try reader.readByte();
            if (lane >= 16) return Error.InvalidOpcode;
            if (stack.items.len < 2) return Error.StackUnderflow;
            const replacement = stack.pop().?;
            const vec = stack.pop().?.v128;
            var result = vec;
            result[lane] = @truncate(@as(u32, @bitCast(replacement.i32)));
            try stack.append(allocator, .{ .v128 = result });
        },

        .i16x8_extract_lane_s => {
            const lane = try reader.readByte();
            if (lane >= 8) return Error.InvalidOpcode;
            if (stack.items.len < 1) return Error.StackUnderflow;
            const v = stack.pop().?.v128;
            const lanes = simd.asI16x8(v);
            try stack.append(allocator, .{ .i32 = lanes[lane] });
        },

        .i16x8_extract_lane_u => {
            const lane = try reader.readByte();
            if (lane >= 8) return Error.InvalidOpcode;
            if (stack.items.len < 1) return Error.StackUnderflow;
            const v = stack.pop().?.v128;
            const idx = lane * 2;
            const val: u16 = @as(u16, v[idx]) | (@as(u16, v[idx + 1]) << 8);
            try stack.append(allocator, .{ .i32 = @intCast(val) });
        },

        .i16x8_replace_lane => {
            const lane = try reader.readByte();
            if (lane >= 8) return Error.InvalidOpcode;
            if (stack.items.len < 2) return Error.StackUnderflow;
            const replacement = stack.pop().?;
            const vec = stack.pop().?.v128;
            var lanes = simd.asI16x8(vec);
            lanes[lane] = @truncate(@as(i32, replacement.i32));
            try stack.append(allocator, .{ .v128 = simd.fromI16x8(lanes) });
        },

        .i32x4_extract_lane => {
            const lane = try reader.readByte();
            if (lane >= 4) return Error.InvalidOpcode;
            if (stack.items.len < 1) return Error.StackUnderflow;
            const v = stack.pop().?.v128;
            const lanes = simd.asI32x4(v);
            try stack.append(allocator, .{ .i32 = lanes[lane] });
        },

        .i32x4_replace_lane => {
            const lane = try reader.readByte();
            if (lane >= 4) return Error.InvalidOpcode;
            if (stack.items.len < 2) return Error.StackUnderflow;
            const replacement = stack.pop().?;
            const vec = stack.pop().?.v128;
            var lanes = simd.asI32x4(vec);
            lanes[lane] = replacement.i32;
            try stack.append(allocator, .{ .v128 = simd.fromI32x4(lanes) });
        },

        .i64x2_extract_lane => {
            const lane = try reader.readByte();
            if (lane >= 2) return Error.InvalidOpcode;
            if (stack.items.len < 1) return Error.StackUnderflow;
            const v = stack.pop().?.v128;
            const lanes = simd.asI64x2(v);
            try stack.append(allocator, .{ .i64 = lanes[lane] });
        },

        .i64x2_replace_lane => {
            const lane = try reader.readByte();
            if (lane >= 2) return Error.InvalidOpcode;
            if (stack.items.len < 2) return Error.StackUnderflow;
            const replacement = stack.pop().?;
            const vec = stack.pop().?.v128;
            var lanes = simd.asI64x2(vec);
            lanes[lane] = replacement.i64;
            try stack.append(allocator, .{ .v128 = simd.fromI64x2(lanes) });
        },

        .f32x4_extract_lane => {
            const lane = try reader.readByte();
            if (lane >= 4) return Error.InvalidOpcode;
            if (stack.items.len < 1) return Error.StackUnderflow;
            const v = stack.pop().?.v128;
            const lanes = simd.asF32x4(v);
            try stack.append(allocator, .{ .f32 = lanes[lane] });
        },

        .f32x4_replace_lane => {
            const lane = try reader.readByte();
            if (lane >= 4) return Error.InvalidOpcode;
            if (stack.items.len < 2) return Error.StackUnderflow;
            const replacement = stack.pop().?;
            const vec = stack.pop().?.v128;
            var lanes = simd.asF32x4(vec);
            lanes[lane] = replacement.f32;
            try stack.append(allocator, .{ .v128 = simd.fromF32x4(lanes) });
        },

        .f64x2_extract_lane => {
            const lane = try reader.readByte();
            if (lane >= 2) return Error.InvalidOpcode;
            if (stack.items.len < 1) return Error.StackUnderflow;
            const v = stack.pop().?.v128;
            const lanes = simd.asF64x2(v);
            try stack.append(allocator, .{ .f64 = lanes[lane] });
        },

        .f64x2_replace_lane => {
            const lane = try reader.readByte();
            if (lane >= 2) return Error.InvalidOpcode;
            if (stack.items.len < 2) return Error.StackUnderflow;
            const replacement = stack.pop().?;
            const vec = stack.pop().?.v128;
            var lanes = simd.asF64x2(vec);
            lanes[lane] = replacement.f64;
            try stack.append(allocator, .{ .v128 = simd.fromF64x2(lanes) });
        },

        // ===== i8x16 OPERATIONS =====

        .i8x16_eq => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b = stack.pop().?.v128;
            const a = stack.pop().?.v128;
            var result: [16]u8 = undefined;
            for (0..16) |i| {
                result[i] = if (a[i] == b[i]) 0xFF else 0x00;
            }
            try stack.append(allocator, .{ .v128 = result });
        },

        .i8x16_ne => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b = stack.pop().?.v128;
            const a = stack.pop().?.v128;
            var result: [16]u8 = undefined;
            for (0..16) |i| {
                result[i] = if (a[i] != b[i]) 0xFF else 0x00;
            }
            try stack.append(allocator, .{ .v128 = result });
        },

        .i8x16_lt_s => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b = stack.pop().?.v128;
            const a = stack.pop().?.v128;
            var result: [16]u8 = undefined;
            for (0..16) |i| {
                const ai: i8 = @bitCast(a[i]);
                const bi: i8 = @bitCast(b[i]);
                result[i] = if (ai < bi) 0xFF else 0x00;
            }
            try stack.append(allocator, .{ .v128 = result });
        },

        .i8x16_lt_u => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b = stack.pop().?.v128;
            const a = stack.pop().?.v128;
            var result: [16]u8 = undefined;
            for (0..16) |i| {
                result[i] = if (a[i] < b[i]) 0xFF else 0x00;
            }
            try stack.append(allocator, .{ .v128 = result });
        },

        .i8x16_gt_s => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b = stack.pop().?.v128;
            const a = stack.pop().?.v128;
            var result: [16]u8 = undefined;
            for (0..16) |i| {
                const ai: i8 = @bitCast(a[i]);
                const bi: i8 = @bitCast(b[i]);
                result[i] = if (ai > bi) 0xFF else 0x00;
            }
            try stack.append(allocator, .{ .v128 = result });
        },

        .i8x16_gt_u => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b = stack.pop().?.v128;
            const a = stack.pop().?.v128;
            var result: [16]u8 = undefined;
            for (0..16) |i| {
                result[i] = if (a[i] > b[i]) 0xFF else 0x00;
            }
            try stack.append(allocator, .{ .v128 = result });
        },

        .i8x16_le_s => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b = stack.pop().?.v128;
            const a = stack.pop().?.v128;
            var result: [16]u8 = undefined;
            for (0..16) |i| {
                const ai: i8 = @bitCast(a[i]);
                const bi: i8 = @bitCast(b[i]);
                result[i] = if (ai <= bi) 0xFF else 0x00;
            }
            try stack.append(allocator, .{ .v128 = result });
        },

        .i8x16_le_u => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b = stack.pop().?.v128;
            const a = stack.pop().?.v128;
            var result: [16]u8 = undefined;
            for (0..16) |i| {
                result[i] = if (a[i] <= b[i]) 0xFF else 0x00;
            }
            try stack.append(allocator, .{ .v128 = result });
        },

        .i8x16_ge_s => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b = stack.pop().?.v128;
            const a = stack.pop().?.v128;
            var result: [16]u8 = undefined;
            for (0..16) |i| {
                const ai: i8 = @bitCast(a[i]);
                const bi: i8 = @bitCast(b[i]);
                result[i] = if (ai >= bi) 0xFF else 0x00;
            }
            try stack.append(allocator, .{ .v128 = result });
        },

        .i8x16_ge_u => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b = stack.pop().?.v128;
            const a = stack.pop().?.v128;
            var result: [16]u8 = undefined;
            for (0..16) |i| {
                result[i] = if (a[i] >= b[i]) 0xFF else 0x00;
            }
            try stack.append(allocator, .{ .v128 = result });
        },

        .i8x16_abs => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a = stack.pop().?.v128;
            var result: [16]u8 = undefined;
            for (0..16) |i| {
                const ai: i8 = @bitCast(a[i]);
                result[i] = @bitCast(@abs(ai));
            }
            try stack.append(allocator, .{ .v128 = result });
        },

        .i8x16_neg => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a = stack.pop().?.v128;
            var result: [16]u8 = undefined;
            for (0..16) |i| {
                const ai: i8 = @bitCast(a[i]);
                result[i] = @bitCast(-%ai);
            }
            try stack.append(allocator, .{ .v128 = result });
        },

        .i8x16_popcnt => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a = stack.pop().?.v128;
            var result: [16]u8 = undefined;
            for (0..16) |i| {
                result[i] = @popCount(a[i]);
            }
            try stack.append(allocator, .{ .v128 = result });
        },

        .i8x16_all_true => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a = stack.pop().?.v128;
            var all_true: i32 = 1;
            for (a) |byte| {
                if (byte == 0) {
                    all_true = 0;
                    break;
                }
            }
            try stack.append(allocator, .{ .i32 = all_true });
        },

        .i8x16_bitmask => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a = stack.pop().?.v128;
            var mask: i32 = 0;
            for (0..16) |i| {
                const ai: i8 = @bitCast(a[i]);
                if (ai < 0) {
                    mask |= @as(i32, 1) << @intCast(i);
                }
            }
            try stack.append(allocator, .{ .i32 = mask });
        },

        .i8x16_shl => {
            const shift_val = try reader.readByte();
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a = stack.pop().?.v128;
            var result: [16]u8 = undefined;
            const shift: u3 = @truncate(shift_val & 7);
            for (0..16) |i| {
                result[i] = a[i] << shift;
            }
            try stack.append(allocator, .{ .v128 = result });
        },

        .i8x16_shr_s => {
            const shift_val = try reader.readByte();
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a = stack.pop().?.v128;
            var result: [16]u8 = undefined;
            const shift: u3 = @truncate(shift_val & 7);
            for (0..16) |i| {
                const ai: i8 = @bitCast(a[i]);
                result[i] = @bitCast(ai >> shift);
            }
            try stack.append(allocator, .{ .v128 = result });
        },

        .i8x16_shr_u => {
            const shift_val = try reader.readByte();
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a = stack.pop().?.v128;
            var result: [16]u8 = undefined;
            const shift: u3 = @truncate(shift_val & 7);
            for (0..16) |i| {
                result[i] = a[i] >> shift;
            }
            try stack.append(allocator, .{ .v128 = result });
        },

        .i8x16_add => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b = stack.pop().?.v128;
            const a = stack.pop().?.v128;
            var result: [16]u8 = undefined;
            for (0..16) |i| {
                const ai: i8 = @bitCast(a[i]);
                const bi: i8 = @bitCast(b[i]);
                result[i] = @bitCast(ai +% bi);
            }
            try stack.append(allocator, .{ .v128 = result });
        },

        .i8x16_add_sat_s => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b = stack.pop().?.v128;
            const a = stack.pop().?.v128;
            var result: [16]u8 = undefined;
            for (0..16) |i| {
                const ai: i8 = @bitCast(a[i]);
                const bi: i8 = @bitCast(b[i]);
                result[i] = @bitCast(simd.addSatI8(ai, bi));
            }
            try stack.append(allocator, .{ .v128 = result });
        },

        .i8x16_add_sat_u => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b = stack.pop().?.v128;
            const a = stack.pop().?.v128;
            var result: [16]u8 = undefined;
            for (0..16) |i| {
                result[i] = simd.addSatU8(a[i], b[i]);
            }
            try stack.append(allocator, .{ .v128 = result });
        },

        .i8x16_sub => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b = stack.pop().?.v128;
            const a = stack.pop().?.v128;
            var result: [16]u8 = undefined;
            for (0..16) |i| {
                const ai: i8 = @bitCast(a[i]);
                const bi: i8 = @bitCast(b[i]);
                result[i] = @bitCast(ai -% bi);
            }
            try stack.append(allocator, .{ .v128 = result });
        },

        .i8x16_sub_sat_s => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b = stack.pop().?.v128;
            const a = stack.pop().?.v128;
            var result: [16]u8 = undefined;
            for (0..16) |i| {
                const ai: i8 = @bitCast(a[i]);
                const bi: i8 = @bitCast(b[i]);
                result[i] = @bitCast(simd.subSatI8(ai, bi));
            }
            try stack.append(allocator, .{ .v128 = result });
        },

        .i8x16_sub_sat_u => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b = stack.pop().?.v128;
            const a = stack.pop().?.v128;
            var result: [16]u8 = undefined;
            for (0..16) |i| {
                result[i] = simd.subSatU8(a[i], b[i]);
            }
            try stack.append(allocator, .{ .v128 = result });
        },

        .i8x16_min_s => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b = stack.pop().?.v128;
            const a = stack.pop().?.v128;
            var result: [16]u8 = undefined;
            for (0..16) |i| {
                const ai: i8 = @bitCast(a[i]);
                const bi: i8 = @bitCast(b[i]);
                result[i] = @bitCast(@min(ai, bi));
            }
            try stack.append(allocator, .{ .v128 = result });
        },

        .i8x16_min_u => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b = stack.pop().?.v128;
            const a = stack.pop().?.v128;
            var result: [16]u8 = undefined;
            for (0..16) |i| {
                result[i] = @min(a[i], b[i]);
            }
            try stack.append(allocator, .{ .v128 = result });
        },

        .i8x16_max_s => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b = stack.pop().?.v128;
            const a = stack.pop().?.v128;
            var result: [16]u8 = undefined;
            for (0..16) |i| {
                const ai: i8 = @bitCast(a[i]);
                const bi: i8 = @bitCast(b[i]);
                result[i] = @bitCast(@max(ai, bi));
            }
            try stack.append(allocator, .{ .v128 = result });
        },

        .i8x16_max_u => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b = stack.pop().?.v128;
            const a = stack.pop().?.v128;
            var result: [16]u8 = undefined;
            for (0..16) |i| {
                result[i] = @max(a[i], b[i]);
            }
            try stack.append(allocator, .{ .v128 = result });
        },

        .i8x16_avgr_u => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b = stack.pop().?.v128;
            const a = stack.pop().?.v128;
            var result: [16]u8 = undefined;
            for (0..16) |i| {
                result[i] = simd.avgrU8(a[i], b[i]);
            }
            try stack.append(allocator, .{ .v128 = result });
        },

        // Narrow operations
        .i8x16_narrow_i16x8_s => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI16x8(a_v128);
            const b = simd.asI16x8(b_v128);
            var result: [16]u8 = undefined;
            for (0..8) |i| {
                const clamped = @max(@min(a[i], 127), -128);
                result[i] = @bitCast(@as(i8, @intCast(clamped)));
            }
            for (0..8) |i| {
                const clamped = @max(@min(b[i], 127), -128);
                result[i + 8] = @bitCast(@as(i8, @intCast(clamped)));
            }
            try stack.append(allocator, .{ .v128 = result });
        },

        .i8x16_narrow_i16x8_u => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI16x8(a_v128);
            const b = simd.asI16x8(b_v128);
            var result: [16]u8 = undefined;
            for (0..8) |i| {
                const clamped = @max(@min(a[i], 255), 0);
                result[i] = @intCast(clamped);
            }
            for (0..8) |i| {
                const clamped = @max(@min(b[i], 255), 0);
                result[i + 8] = @intCast(clamped);
            }
            try stack.append(allocator, .{ .v128 = result });
        },

        // ===== i16x8 OPERATIONS =====

        .i16x8_eq => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI16x8(a_v128);
            const b = simd.asI16x8(b_v128);
            var result: [8]i16 = undefined;
            for (0..8) |i| {
                result[i] = if (a[i] == b[i]) -1 else 0;
            }
            try stack.append(allocator, .{ .v128 = simd.fromI16x8(result) });
        },

        .i16x8_ne => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI16x8(a_v128);
            const b = simd.asI16x8(b_v128);
            var result: [8]i16 = undefined;
            for (0..8) |i| {
                result[i] = if (a[i] != b[i]) -1 else 0;
            }
            try stack.append(allocator, .{ .v128 = simd.fromI16x8(result) });
        },

        .i16x8_lt_s => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI16x8(a_v128);
            const b = simd.asI16x8(b_v128);
            var result: [8]i16 = undefined;
            for (0..8) |i| {
                result[i] = if (a[i] < b[i]) -1 else 0;
            }
            try stack.append(allocator, .{ .v128 = simd.fromI16x8(result) });
        },

        .i16x8_lt_u => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI16x8(a_v128);
            const b = simd.asI16x8(b_v128);
            var result: [8]i16 = undefined;
            for (0..8) |i| {
                const au: u16 = @bitCast(a[i]);
                const bu: u16 = @bitCast(b[i]);
                result[i] = if (au < bu) -1 else 0;
            }
            try stack.append(allocator, .{ .v128 = simd.fromI16x8(result) });
        },

        .i16x8_gt_s => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI16x8(a_v128);
            const b = simd.asI16x8(b_v128);
            var result: [8]i16 = undefined;
            for (0..8) |i| {
                result[i] = if (a[i] > b[i]) -1 else 0;
            }
            try stack.append(allocator, .{ .v128 = simd.fromI16x8(result) });
        },

        .i16x8_gt_u => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI16x8(a_v128);
            const b = simd.asI16x8(b_v128);
            var result: [8]i16 = undefined;
            for (0..8) |i| {
                const au: u16 = @bitCast(a[i]);
                const bu: u16 = @bitCast(b[i]);
                result[i] = if (au > bu) -1 else 0;
            }
            try stack.append(allocator, .{ .v128 = simd.fromI16x8(result) });
        },

        .i16x8_le_s => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI16x8(a_v128);
            const b = simd.asI16x8(b_v128);
            var result: [8]i16 = undefined;
            for (0..8) |i| {
                result[i] = if (a[i] <= b[i]) -1 else 0;
            }
            try stack.append(allocator, .{ .v128 = simd.fromI16x8(result) });
        },

        .i16x8_le_u => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI16x8(a_v128);
            const b = simd.asI16x8(b_v128);
            var result: [8]i16 = undefined;
            for (0..8) |i| {
                const au: u16 = @bitCast(a[i]);
                const bu: u16 = @bitCast(b[i]);
                result[i] = if (au <= bu) -1 else 0;
            }
            try stack.append(allocator, .{ .v128 = simd.fromI16x8(result) });
        },

        .i16x8_ge_s => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI16x8(a_v128);
            const b = simd.asI16x8(b_v128);
            var result: [8]i16 = undefined;
            for (0..8) |i| {
                result[i] = if (a[i] >= b[i]) -1 else 0;
            }
            try stack.append(allocator, .{ .v128 = simd.fromI16x8(result) });
        },

        .i16x8_ge_u => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI16x8(a_v128);
            const b = simd.asI16x8(b_v128);
            var result: [8]i16 = undefined;
            for (0..8) |i| {
                const au: u16 = @bitCast(a[i]);
                const bu: u16 = @bitCast(b[i]);
                result[i] = if (au >= bu) -1 else 0;
            }
            try stack.append(allocator, .{ .v128 = simd.fromI16x8(result) });
        },

        .i16x8_abs => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI16x8(a_v128);
            var result: [8]i16 = undefined;
            for (0..8) |i| {
                result[i] = if (a[i] == std.math.minInt(i16)) a[i] else if (a[i] < 0) -%a[i] else a[i];
            }
            try stack.append(allocator, .{ .v128 = simd.fromI16x8(result) });
        },

        .i16x8_neg => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI16x8(a_v128);
            var result: [8]i16 = undefined;
            for (0..8) |i| {
                result[i] = -%a[i];
            }
            try stack.append(allocator, .{ .v128 = simd.fromI16x8(result) });
        },

        .i16x8_all_true => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI16x8(a_v128);
            var all_true: i32 = 1;
            for (a) |val| {
                if (val == 0) {
                    all_true = 0;
                    break;
                }
            }
            try stack.append(allocator, .{ .i32 = all_true });
        },

        .i16x8_bitmask => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI16x8(a_v128);
            var mask: i32 = 0;
            for (0..8) |i| {
                if (a[i] < 0) {
                    mask |= @as(i32, 1) << @intCast(i);
                }
            }
            try stack.append(allocator, .{ .i32 = mask });
        },

        .i16x8_shl => {
            const shift_val = try reader.readByte();
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI16x8(a_v128);
            var result: [8]i16 = undefined;
            const shift: u4 = @truncate(shift_val & 15);
            for (0..8) |i| {
                result[i] = a[i] << shift;
            }
            try stack.append(allocator, .{ .v128 = simd.fromI16x8(result) });
        },

        .i16x8_shr_s => {
            const shift_val = try reader.readByte();
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI16x8(a_v128);
            var result: [8]i16 = undefined;
            const shift: u4 = @truncate(shift_val & 15);
            for (0..8) |i| {
                result[i] = a[i] >> shift;
            }
            try stack.append(allocator, .{ .v128 = simd.fromI16x8(result) });
        },

        .i16x8_shr_u => {
            const shift_val = try reader.readByte();
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI16x8(a_v128);
            var result: [8]i16 = undefined;
            const shift: u4 = @truncate(shift_val & 15);
            for (0..8) |i| {
                const au: u16 = @bitCast(a[i]);
                result[i] = @bitCast(au >> shift);
            }
            try stack.append(allocator, .{ .v128 = simd.fromI16x8(result) });
        },

        .i16x8_add => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI16x8(a_v128);
            const b = simd.asI16x8(b_v128);
            var result: [8]i16 = undefined;
            for (0..8) |i| {
                result[i] = a[i] +% b[i];
            }
            try stack.append(allocator, .{ .v128 = simd.fromI16x8(result) });
        },

        .i16x8_add_sat_s => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI16x8(a_v128);
            const b = simd.asI16x8(b_v128);
            var result: [8]i16 = undefined;
            for (0..8) |i| {
                result[i] = simd.addSatI16(a[i], b[i]);
            }
            try stack.append(allocator, .{ .v128 = simd.fromI16x8(result) });
        },

        .i16x8_add_sat_u => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI16x8(a_v128);
            const b = simd.asI16x8(b_v128);
            var result: [8]i16 = undefined;
            for (0..8) |i| {
                const au: u16 = @bitCast(a[i]);
                const bu: u16 = @bitCast(b[i]);
                result[i] = @bitCast(simd.addSatU16(au, bu));
            }
            try stack.append(allocator, .{ .v128 = simd.fromI16x8(result) });
        },

        .i16x8_sub => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI16x8(a_v128);
            const b = simd.asI16x8(b_v128);
            var result: [8]i16 = undefined;
            for (0..8) |i| {
                result[i] = a[i] -% b[i];
            }
            try stack.append(allocator, .{ .v128 = simd.fromI16x8(result) });
        },

        .i16x8_sub_sat_s => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI16x8(a_v128);
            const b = simd.asI16x8(b_v128);
            var result: [8]i16 = undefined;
            for (0..8) |i| {
                result[i] = simd.subSatI16(a[i], b[i]);
            }
            try stack.append(allocator, .{ .v128 = simd.fromI16x8(result) });
        },

        .i16x8_sub_sat_u => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI16x8(a_v128);
            const b = simd.asI16x8(b_v128);
            var result: [8]i16 = undefined;
            for (0..8) |i| {
                const au: u16 = @bitCast(a[i]);
                const bu: u16 = @bitCast(b[i]);
                result[i] = @bitCast(simd.subSatU16(au, bu));
            }
            try stack.append(allocator, .{ .v128 = simd.fromI16x8(result) });
        },

        .i16x8_mul => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI16x8(a_v128);
            const b = simd.asI16x8(b_v128);
            var result: [8]i16 = undefined;
            for (0..8) |i| {
                result[i] = a[i] *% b[i];
            }
            try stack.append(allocator, .{ .v128 = simd.fromI16x8(result) });
        },

        .i16x8_min_s => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI16x8(a_v128);
            const b = simd.asI16x8(b_v128);
            var result: [8]i16 = undefined;
            for (0..8) |i| {
                result[i] = @min(a[i], b[i]);
            }
            try stack.append(allocator, .{ .v128 = simd.fromI16x8(result) });
        },

        .i16x8_min_u => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI16x8(a_v128);
            const b = simd.asI16x8(b_v128);
            var result: [8]i16 = undefined;
            for (0..8) |i| {
                const au: u16 = @bitCast(a[i]);
                const bu: u16 = @bitCast(b[i]);
                result[i] = @bitCast(@min(au, bu));
            }
            try stack.append(allocator, .{ .v128 = simd.fromI16x8(result) });
        },

        .i16x8_max_s => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI16x8(a_v128);
            const b = simd.asI16x8(b_v128);
            var result: [8]i16 = undefined;
            for (0..8) |i| {
                result[i] = @max(a[i], b[i]);
            }
            try stack.append(allocator, .{ .v128 = simd.fromI16x8(result) });
        },

        .i16x8_max_u => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI16x8(a_v128);
            const b = simd.asI16x8(b_v128);
            var result: [8]i16 = undefined;
            for (0..8) |i| {
                const au: u16 = @bitCast(a[i]);
                const bu: u16 = @bitCast(b[i]);
                result[i] = @bitCast(@max(au, bu));
            }
            try stack.append(allocator, .{ .v128 = simd.fromI16x8(result) });
        },

        .i16x8_avgr_u => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI16x8(a_v128);
            const b = simd.asI16x8(b_v128);
            var result: [8]i16 = undefined;
            for (0..8) |i| {
                const au: u16 = @bitCast(a[i]);
                const bu: u16 = @bitCast(b[i]);
                result[i] = @bitCast(simd.avgrU16(au, bu));
            }
            try stack.append(allocator, .{ .v128 = simd.fromI16x8(result) });
        },

        .i16x8_narrow_i32x4_s => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI32x4(a_v128);
            const b = simd.asI32x4(b_v128);
            var result: [8]i16 = undefined;
            for (0..4) |i| {
                const clamped = @max(@min(a[i], 32767), -32768);
                result[i] = @intCast(clamped);
            }
            for (0..4) |i| {
                const clamped = @max(@min(b[i], 32767), -32768);
                result[i + 4] = @intCast(clamped);
            }
            try stack.append(allocator, .{ .v128 = simd.fromI16x8(result) });
        },

        .i16x8_narrow_i32x4_u => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI32x4(a_v128);
            const b = simd.asI32x4(b_v128);
            var result: [8]i16 = undefined;
            for (0..4) |i| {
                const clamped = @max(@min(a[i], 65535), 0);
                result[i] = @bitCast(@as(u16, @intCast(clamped)));
            }
            for (0..4) |i| {
                const clamped = @max(@min(b[i], 65535), 0);
                result[i + 4] = @bitCast(@as(u16, @intCast(clamped)));
            }
            try stack.append(allocator, .{ .v128 = simd.fromI16x8(result) });
        },

        // Extend operations
        .i16x8_extend_low_i8x16_s => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            var result: [8]i16 = undefined;
            for (0..8) |i| {
                const val: i8 = @bitCast(a_v128[i]);
                result[i] = val;
            }
            try stack.append(allocator, .{ .v128 = simd.fromI16x8(result) });
        },

        .i16x8_extend_high_i8x16_s => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            var result: [8]i16 = undefined;
            for (0..8) |i| {
                const val: i8 = @bitCast(a_v128[i + 8]);
                result[i] = val;
            }
            try stack.append(allocator, .{ .v128 = simd.fromI16x8(result) });
        },

        .i16x8_extend_low_i8x16_u => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            var result: [8]i16 = undefined;
            for (0..8) |i| {
                result[i] = @bitCast(@as(u16, a_v128[i]));
            }
            try stack.append(allocator, .{ .v128 = simd.fromI16x8(result) });
        },

        .i16x8_extend_high_i8x16_u => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            var result: [8]i16 = undefined;
            for (0..8) |i| {
                result[i] = @bitCast(@as(u16, a_v128[i + 8]));
            }
            try stack.append(allocator, .{ .v128 = simd.fromI16x8(result) });
        },

        // i32x4, i64x2, f32x4, f64x2 operations, conversions, etc. follow below

        // ===== i32x4 OPERATIONS =====

        .i32x4_eq, .i32x4_ne, .i32x4_lt_s, .i32x4_lt_u, .i32x4_gt_s, .i32x4_gt_u, .i32x4_le_s, .i32x4_le_u, .i32x4_ge_s, .i32x4_ge_u => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI32x4(a_v128);
            const b = simd.asI32x4(b_v128);
            var result: [4]i32 = undefined;

            inline for (0..4) |i| {
                const bool_val = switch (op) {
                    .i32x4_eq => a[i] == b[i],
                    .i32x4_ne => a[i] != b[i],
                    .i32x4_lt_s => a[i] < b[i],
                    .i32x4_gt_s => a[i] > b[i],
                    .i32x4_le_s => a[i] <= b[i],
                    .i32x4_ge_s => a[i] >= b[i],
                    .i32x4_lt_u => blk: {
                        const au: u32 = @bitCast(a[i]);
                        const bu: u32 = @bitCast(b[i]);
                        break :blk au < bu;
                    },
                    .i32x4_gt_u => blk: {
                        const au: u32 = @bitCast(a[i]);
                        const bu: u32 = @bitCast(b[i]);
                        break :blk au > bu;
                    },
                    .i32x4_le_u => blk: {
                        const au: u32 = @bitCast(a[i]);
                        const bu: u32 = @bitCast(b[i]);
                        break :blk au <= bu;
                    },
                    .i32x4_ge_u => blk: {
                        const au: u32 = @bitCast(a[i]);
                        const bu: u32 = @bitCast(b[i]);
                        break :blk au >= bu;
                    },
                    else => return Error.InvalidOpcode,
                };
                result[i] = if (bool_val) -1 else 0;
            }
            try stack.append(allocator, .{ .v128 = simd.fromI32x4(result) });
        },

        .i32x4_abs => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI32x4(a_v128);
            var result: [4]i32 = undefined;
            for (0..4) |i| {
                const val = a[i];
                result[i] = if (val == std.math.minInt(i32)) val else if (val < 0) -%val else val;
            }
            try stack.append(allocator, .{ .v128 = simd.fromI32x4(result) });
        },

        .i32x4_neg => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI32x4(a_v128);
            var result: [4]i32 = undefined;
            for (0..4) |i| {
                result[i] = -%a[i];
            }
            try stack.append(allocator, .{ .v128 = simd.fromI32x4(result) });
        },

        .i32x4_all_true => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI32x4(a_v128);
            const all_true: i32 = if (a[0] != 0 and a[1] != 0 and a[2] != 0 and a[3] != 0) 1 else 0;
            try stack.append(allocator, .{ .i32 = all_true });
        },

        .i32x4_bitmask => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI32x4(a_v128);
            var mask: i32 = 0;
            for (0..4) |i| {
                if (a[i] < 0) {
                    mask |= @as(i32, 1) << @intCast(i);
                }
            }
            try stack.append(allocator, .{ .i32 = mask });
        },

        .i32x4_extend_low_i16x8_s => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI16x8(a_v128);
            var result: [4]i32 = undefined;
            for (0..4) |i| {
                result[i] = a[i];
            }
            try stack.append(allocator, .{ .v128 = simd.fromI32x4(result) });
        },

        .i32x4_extend_high_i16x8_s => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI16x8(a_v128);
            var result: [4]i32 = undefined;
            for (0..4) |i| {
                result[i] = a[i + 4];
            }
            try stack.append(allocator, .{ .v128 = simd.fromI32x4(result) });
        },

        .i32x4_extend_low_i16x8_u => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI16x8(a_v128);
            var result: [4]i32 = undefined;
            for (0..4) |i| {
                const au: u16 = @bitCast(a[i]);
                result[i] = @bitCast(@as(u32, au));
            }
            try stack.append(allocator, .{ .v128 = simd.fromI32x4(result) });
        },

        .i32x4_extend_high_i16x8_u => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI16x8(a_v128);
            var result: [4]i32 = undefined;
            for (0..4) |i| {
                const au: u16 = @bitCast(a[i + 4]);
                result[i] = @bitCast(@as(u32, au));
            }
            try stack.append(allocator, .{ .v128 = simd.fromI32x4(result) });
        },

        .i32x4_shl => {
            const shift_val = try reader.readByte();
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI32x4(a_v128);
            var result: [4]i32 = undefined;
            const shift: u5 = @truncate(shift_val & 31);
            for (0..4) |i| {
                result[i] = a[i] << shift;
            }
            try stack.append(allocator, .{ .v128 = simd.fromI32x4(result) });
        },

        .i32x4_shr_s => {
            const shift_val = try reader.readByte();
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI32x4(a_v128);
            var result: [4]i32 = undefined;
            const shift: u5 = @truncate(shift_val & 31);
            for (0..4) |i| {
                result[i] = a[i] >> shift;
            }
            try stack.append(allocator, .{ .v128 = simd.fromI32x4(result) });
        },

        .i32x4_shr_u => {
            const shift_val = try reader.readByte();
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI32x4(a_v128);
            var result: [4]i32 = undefined;
            const shift: u5 = @truncate(shift_val & 31);
            for (0..4) |i| {
                const au: u32 = @bitCast(a[i]);
                result[i] = @bitCast(au >> shift);
            }
            try stack.append(allocator, .{ .v128 = simd.fromI32x4(result) });
        },

        .i32x4_add => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI32x4(a_v128);
            const b = simd.asI32x4(b_v128);
            var result: [4]i32 = undefined;
            for (0..4) |i| {
                result[i] = a[i] +% b[i];
            }
            try stack.append(allocator, .{ .v128 = simd.fromI32x4(result) });
        },

        .i32x4_sub => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI32x4(a_v128);
            const b = simd.asI32x4(b_v128);
            var result: [4]i32 = undefined;
            for (0..4) |i| {
                result[i] = a[i] -% b[i];
            }
            try stack.append(allocator, .{ .v128 = simd.fromI32x4(result) });
        },

        .i32x4_mul => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI32x4(a_v128);
            const b = simd.asI32x4(b_v128);
            var result: [4]i32 = undefined;
            for (0..4) |i| {
                result[i] = a[i] *% b[i];
            }
            try stack.append(allocator, .{ .v128 = simd.fromI32x4(result) });
        },

        .i32x4_min_s => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI32x4(a_v128);
            const b = simd.asI32x4(b_v128);
            var result: [4]i32 = undefined;
            for (0..4) |i| {
                result[i] = @min(a[i], b[i]);
            }
            try stack.append(allocator, .{ .v128 = simd.fromI32x4(result) });
        },

        .i32x4_min_u => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI32x4(a_v128);
            const b = simd.asI32x4(b_v128);
            var result: [4]i32 = undefined;
            for (0..4) |i| {
                const au: u32 = @bitCast(a[i]);
                const bu: u32 = @bitCast(b[i]);
                result[i] = @bitCast(@min(au, bu));
            }
            try stack.append(allocator, .{ .v128 = simd.fromI32x4(result) });
        },

        .i32x4_max_s => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI32x4(a_v128);
            const b = simd.asI32x4(b_v128);
            var result: [4]i32 = undefined;
            for (0..4) |i| {
                result[i] = @max(a[i], b[i]);
            }
            try stack.append(allocator, .{ .v128 = simd.fromI32x4(result) });
        },

        .i32x4_max_u => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI32x4(a_v128);
            const b = simd.asI32x4(b_v128);
            var result: [4]i32 = undefined;
            for (0..4) |i| {
                const au: u32 = @bitCast(a[i]);
                const bu: u32 = @bitCast(b[i]);
                result[i] = @bitCast(@max(au, bu));
            }
            try stack.append(allocator, .{ .v128 = simd.fromI32x4(result) });
        },

        .i32x4_dot_i16x8_s => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI16x8(a_v128);
            const b = simd.asI16x8(b_v128);
            var result: [4]i32 = undefined;
            for (0..4) |i| {
                const idx = i * 2;
                const prod0: i32 = @as(i32, a[idx]) * @as(i32, b[idx]);
                const prod1: i32 = @as(i32, a[idx + 1]) * @as(i32, b[idx + 1]);
                result[i] = prod0 + prod1;
            }
            try stack.append(allocator, .{ .v128 = simd.fromI32x4(result) });
        },

        .i32x4_extmul_low_i16x8_s, .i32x4_extmul_high_i16x8_s, .i32x4_extmul_low_i16x8_u, .i32x4_extmul_high_i16x8_u => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a_i16 = simd.asI16x8(a_v128);
            const b_i16 = simd.asI16x8(b_v128);
            var result: [4]i32 = undefined;

            const start_idx: usize = switch (op) {
                .i32x4_extmul_low_i16x8_s, .i32x4_extmul_low_i16x8_u => 0,
                .i32x4_extmul_high_i16x8_s, .i32x4_extmul_high_i16x8_u => 4,
                else => return Error.InvalidOpcode,
            };

            const is_signed = switch (op) {
                .i32x4_extmul_low_i16x8_s, .i32x4_extmul_high_i16x8_s => true,
                else => false,
            };

            for (0..4) |i| {
                const idx = start_idx + i;
                if (is_signed) {
                    result[i] = @as(i32, a_i16[idx]) *% @as(i32, b_i16[idx]);
                } else {
                    const au: u16 = @bitCast(a_i16[idx]);
                    const bu: u16 = @bitCast(b_i16[idx]);
                    result[i] = @bitCast(@as(u32, au) *% @as(u32, bu));
                }
            }
            try stack.append(allocator, .{ .v128 = simd.fromI32x4(result) });
        },

        // ===== i64x2 OPERATIONS =====

        .i64x2_eq => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI64x2(a_v128);
            const b = simd.asI64x2(b_v128);
            var result: [2]i64 = undefined;
            for (0..2) |i| {
                result[i] = if (a[i] == b[i]) -1 else 0;
            }
            try stack.append(allocator, .{ .v128 = simd.fromI64x2(result) });
        },

        .i64x2_ne => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI64x2(a_v128);
            const b = simd.asI64x2(b_v128);
            var result: [2]i64 = undefined;
            for (0..2) |i| {
                result[i] = if (a[i] != b[i]) -1 else 0;
            }
            try stack.append(allocator, .{ .v128 = simd.fromI64x2(result) });
        },

        .i64x2_lt_s => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI64x2(a_v128);
            const b = simd.asI64x2(b_v128);
            var result: [2]i64 = undefined;
            for (0..2) |i| {
                result[i] = if (a[i] < b[i]) -1 else 0;
            }
            try stack.append(allocator, .{ .v128 = simd.fromI64x2(result) });
        },

        .i64x2_gt_s => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI64x2(a_v128);
            const b = simd.asI64x2(b_v128);
            var result: [2]i64 = undefined;
            for (0..2) |i| {
                result[i] = if (a[i] > b[i]) -1 else 0;
            }
            try stack.append(allocator, .{ .v128 = simd.fromI64x2(result) });
        },

        .i64x2_le_s => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI64x2(a_v128);
            const b = simd.asI64x2(b_v128);
            var result: [2]i64 = undefined;
            for (0..2) |i| {
                result[i] = if (a[i] <= b[i]) -1 else 0;
            }
            try stack.append(allocator, .{ .v128 = simd.fromI64x2(result) });
        },

        .i64x2_ge_s => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI64x2(a_v128);
            const b = simd.asI64x2(b_v128);
            var result: [2]i64 = undefined;
            for (0..2) |i| {
                result[i] = if (a[i] >= b[i]) -1 else 0;
            }
            try stack.append(allocator, .{ .v128 = simd.fromI64x2(result) });
        },

        .i64x2_abs => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI64x2(a_v128);
            var result: [2]i64 = undefined;
            for (0..2) |i| {
                result[i] = if (a[i] == std.math.minInt(i64)) a[i] else if (a[i] < 0) -%a[i] else a[i];
            }
            try stack.append(allocator, .{ .v128 = simd.fromI64x2(result) });
        },

        .i64x2_neg => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI64x2(a_v128);
            var result: [2]i64 = undefined;
            for (0..2) |i| {
                result[i] = -%a[i];
            }
            try stack.append(allocator, .{ .v128 = simd.fromI64x2(result) });
        },

        .i64x2_all_true => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI64x2(a_v128);
            const all_true: i32 = if (a[0] != 0 and a[1] != 0) 1 else 0;
            try stack.append(allocator, .{ .i32 = all_true });
        },

        .i64x2_bitmask => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI64x2(a_v128);
            var mask: i32 = 0;
            for (0..2) |i| {
                if (a[i] < 0) {
                    mask |= @as(i32, 1) << @intCast(i);
                }
            }
            try stack.append(allocator, .{ .i32 = mask });
        },

        .i64x2_extend_low_i32x4_s => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI32x4(a_v128);
            var result: [2]i64 = undefined;
            for (0..2) |i| {
                result[i] = a[i];
            }
            try stack.append(allocator, .{ .v128 = simd.fromI64x2(result) });
        },

        .i64x2_extend_high_i32x4_s => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI32x4(a_v128);
            var result: [2]i64 = undefined;
            for (0..2) |i| {
                result[i] = a[i + 2];
            }
            try stack.append(allocator, .{ .v128 = simd.fromI64x2(result) });
        },

        .i64x2_extend_low_i32x4_u => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI32x4(a_v128);
            var result: [2]i64 = undefined;
            for (0..2) |i| {
                const au: u32 = @bitCast(a[i]);
                result[i] = @bitCast(@as(u64, au));
            }
            try stack.append(allocator, .{ .v128 = simd.fromI64x2(result) });
        },

        .i64x2_extend_high_i32x4_u => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI32x4(a_v128);
            var result: [2]i64 = undefined;
            for (0..2) |i| {
                const au: u32 = @bitCast(a[i + 2]);
                result[i] = @bitCast(@as(u64, au));
            }
            try stack.append(allocator, .{ .v128 = simd.fromI64x2(result) });
        },

        .i64x2_shl => {
            const shift_val = try reader.readByte();
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI64x2(a_v128);
            var result: [2]i64 = undefined;
            const shift: u6 = @truncate(shift_val & 63);
            for (0..2) |i| {
                result[i] = a[i] << shift;
            }
            try stack.append(allocator, .{ .v128 = simd.fromI64x2(result) });
        },

        .i64x2_shr_s => {
            const shift_val = try reader.readByte();
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI64x2(a_v128);
            var result: [2]i64 = undefined;
            const shift: u6 = @truncate(shift_val & 63);
            for (0..2) |i| {
                result[i] = a[i] >> shift;
            }
            try stack.append(allocator, .{ .v128 = simd.fromI64x2(result) });
        },

        .i64x2_shr_u => {
            const shift_val = try reader.readByte();
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI64x2(a_v128);
            var result: [2]i64 = undefined;
            const shift: u6 = @truncate(shift_val & 63);
            for (0..2) |i| {
                const au: u64 = @bitCast(a[i]);
                result[i] = @bitCast(au >> shift);
            }
            try stack.append(allocator, .{ .v128 = simd.fromI64x2(result) });
        },

        .i64x2_add => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI64x2(a_v128);
            const b = simd.asI64x2(b_v128);
            var result: [2]i64 = undefined;
            for (0..2) |i| {
                result[i] = a[i] +% b[i];
            }
            try stack.append(allocator, .{ .v128 = simd.fromI64x2(result) });
        },

        .i64x2_sub => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI64x2(a_v128);
            const b = simd.asI64x2(b_v128);
            var result: [2]i64 = undefined;
            for (0..2) |i| {
                result[i] = a[i] -% b[i];
            }
            try stack.append(allocator, .{ .v128 = simd.fromI64x2(result) });
        },

        .i64x2_mul => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI64x2(a_v128);
            const b = simd.asI64x2(b_v128);
            var result: [2]i64 = undefined;
            for (0..2) |i| {
                result[i] = a[i] *% b[i];
            }
            try stack.append(allocator, .{ .v128 = simd.fromI64x2(result) });
        },

        .i64x2_extmul_low_i32x4_s, .i64x2_extmul_high_i32x4_s, .i64x2_extmul_low_i32x4_u, .i64x2_extmul_high_i32x4_u => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a_i32 = simd.asI32x4(a_v128);
            const b_i32 = simd.asI32x4(b_v128);
            var result: [2]i64 = undefined;

            const start_idx: usize = switch (op) {
                .i64x2_extmul_low_i32x4_s, .i64x2_extmul_low_i32x4_u => 0,
                .i64x2_extmul_high_i32x4_s, .i64x2_extmul_high_i32x4_u => 2,
                else => return Error.InvalidOpcode,
            };

            const is_signed = switch (op) {
                .i64x2_extmul_low_i32x4_s, .i64x2_extmul_high_i32x4_s => true,
                else => false,
            };

            for (0..2) |i| {
                const idx = start_idx + i;
                if (is_signed) {
                    result[i] = @as(i64, a_i32[idx]) *% @as(i64, b_i32[idx]);
                } else {
                    const au: u32 = @bitCast(a_i32[idx]);
                    const bu: u32 = @bitCast(b_i32[idx]);
                    result[i] = @bitCast(@as(u64, au) *% @as(u64, bu));
                }
            }
            try stack.append(allocator, .{ .v128 = simd.fromI64x2(result) });
        },

        // ===== f32x4 OPERATIONS =====

        .f32x4_eq => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asF32x4(a_v128);
            const b = simd.asF32x4(b_v128);
            var result: [4]i32 = undefined;
            for (0..4) |i| {
                result[i] = if (a[i] == b[i]) -1 else 0;
            }
            try stack.append(allocator, .{ .v128 = simd.fromI32x4(result) });
        },

        .f32x4_ne => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asF32x4(a_v128);
            const b = simd.asF32x4(b_v128);
            var result: [4]i32 = undefined;
            for (0..4) |i| {
                result[i] = if (a[i] != b[i]) -1 else 0;
            }
            try stack.append(allocator, .{ .v128 = simd.fromI32x4(result) });
        },

        .f32x4_lt => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asF32x4(a_v128);
            const b = simd.asF32x4(b_v128);
            var result: [4]i32 = undefined;
            for (0..4) |i| {
                result[i] = if (a[i] < b[i]) -1 else 0;
            }
            try stack.append(allocator, .{ .v128 = simd.fromI32x4(result) });
        },

        .f32x4_gt => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asF32x4(a_v128);
            const b = simd.asF32x4(b_v128);
            var result: [4]i32 = undefined;
            for (0..4) |i| {
                result[i] = if (a[i] > b[i]) -1 else 0;
            }
            try stack.append(allocator, .{ .v128 = simd.fromI32x4(result) });
        },

        .f32x4_le => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asF32x4(a_v128);
            const b = simd.asF32x4(b_v128);
            var result: [4]i32 = undefined;
            for (0..4) |i| {
                result[i] = if (a[i] <= b[i]) -1 else 0;
            }
            try stack.append(allocator, .{ .v128 = simd.fromI32x4(result) });
        },

        .f32x4_ge => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asF32x4(a_v128);
            const b = simd.asF32x4(b_v128);
            var result: [4]i32 = undefined;
            for (0..4) |i| {
                result[i] = if (a[i] >= b[i]) -1 else 0;
            }
            try stack.append(allocator, .{ .v128 = simd.fromI32x4(result) });
        },

        .f32x4_abs => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asF32x4(a_v128);
            var result: [4]f32 = undefined;
            for (0..4) |i| {
                result[i] = @abs(a[i]);
            }
            try stack.append(allocator, .{ .v128 = simd.fromF32x4(result) });
        },

        .f32x4_neg => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asF32x4(a_v128);
            var result: [4]f32 = undefined;
            for (0..4) |i| {
                result[i] = -a[i];
            }
            try stack.append(allocator, .{ .v128 = simd.fromF32x4(result) });
        },

        .f32x4_sqrt => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asF32x4(a_v128);
            var result: [4]f32 = undefined;
            for (0..4) |i| {
                result[i] = @sqrt(a[i]);
            }
            try stack.append(allocator, .{ .v128 = simd.fromF32x4(result) });
        },

        .f32x4_add => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asF32x4(a_v128);
            const b = simd.asF32x4(b_v128);
            var result: [4]f32 = undefined;
            for (0..4) |i| {
                result[i] = a[i] + b[i];
            }
            try stack.append(allocator, .{ .v128 = simd.fromF32x4(result) });
        },

        .f32x4_sub => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asF32x4(a_v128);
            const b = simd.asF32x4(b_v128);
            var result: [4]f32 = undefined;
            for (0..4) |i| {
                result[i] = a[i] - b[i];
            }
            try stack.append(allocator, .{ .v128 = simd.fromF32x4(result) });
        },

        .f32x4_mul => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asF32x4(a_v128);
            const b = simd.asF32x4(b_v128);
            var result: [4]f32 = undefined;
            for (0..4) |i| {
                result[i] = a[i] * b[i];
            }
            try stack.append(allocator, .{ .v128 = simd.fromF32x4(result) });
        },

        .f32x4_div => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asF32x4(a_v128);
            const b = simd.asF32x4(b_v128);
            var result: [4]f32 = undefined;
            for (0..4) |i| {
                result[i] = a[i] / b[i];
            }
            try stack.append(allocator, .{ .v128 = simd.fromF32x4(result) });
        },

        .f32x4_min => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asF32x4(a_v128);
            const b = simd.asF32x4(b_v128);
            var result: [4]f32 = undefined;
            for (0..4) |i| {
                result[i] = @min(a[i], b[i]);
            }
            try stack.append(allocator, .{ .v128 = simd.fromF32x4(result) });
        },

        .f32x4_max => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asF32x4(a_v128);
            const b = simd.asF32x4(b_v128);
            var result: [4]f32 = undefined;
            for (0..4) |i| {
                result[i] = @max(a[i], b[i]);
            }
            try stack.append(allocator, .{ .v128 = simd.fromF32x4(result) });
        },

        .f32x4_pmin => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asF32x4(a_v128);
            const b = simd.asF32x4(b_v128);
            var result: [4]f32 = undefined;
            for (0..4) |i| {
                result[i] = if (b[i] < a[i]) b[i] else a[i];
            }
            try stack.append(allocator, .{ .v128 = simd.fromF32x4(result) });
        },

        .f32x4_pmax => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asF32x4(a_v128);
            const b = simd.asF32x4(b_v128);
            var result: [4]f32 = undefined;
            for (0..4) |i| {
                result[i] = if (a[i] < b[i]) b[i] else a[i];
            }
            try stack.append(allocator, .{ .v128 = simd.fromF32x4(result) });
        },

        .f32x4_ceil => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asF32x4(a_v128);
            var result: [4]f32 = undefined;
            for (0..4) |i| {
                result[i] = @ceil(a[i]);
            }
            try stack.append(allocator, .{ .v128 = simd.fromF32x4(result) });
        },

        .f32x4_floor => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asF32x4(a_v128);
            var result: [4]f32 = undefined;
            for (0..4) |i| {
                result[i] = @floor(a[i]);
            }
            try stack.append(allocator, .{ .v128 = simd.fromF32x4(result) });
        },

        .f32x4_trunc => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asF32x4(a_v128);
            var result: [4]f32 = undefined;
            for (0..4) |i| {
                result[i] = @trunc(a[i]);
            }
            try stack.append(allocator, .{ .v128 = simd.fromF32x4(result) });
        },

        .f32x4_nearest => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asF32x4(a_v128);
            var result: [4]f32 = undefined;
            for (0..4) |i| {
                result[i] = @round(a[i]);
            }
            try stack.append(allocator, .{ .v128 = simd.fromF32x4(result) });
        },

        // ===== f64x2 OPERATIONS =====

        .f64x2_eq => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asF64x2(a_v128);
            const b = simd.asF64x2(b_v128);
            var result: [2]i64 = undefined;
            for (0..2) |i| {
                result[i] = if (a[i] == b[i]) -1 else 0;
            }
            try stack.append(allocator, .{ .v128 = simd.fromI64x2(result) });
        },

        .f64x2_ne => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asF64x2(a_v128);
            const b = simd.asF64x2(b_v128);
            var result: [2]i64 = undefined;
            for (0..2) |i| {
                result[i] = if (a[i] != b[i]) -1 else 0;
            }
            try stack.append(allocator, .{ .v128 = simd.fromI64x2(result) });
        },

        .f64x2_lt => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asF64x2(a_v128);
            const b = simd.asF64x2(b_v128);
            var result: [2]i64 = undefined;
            for (0..2) |i| {
                result[i] = if (a[i] < b[i]) -1 else 0;
            }
            try stack.append(allocator, .{ .v128 = simd.fromI64x2(result) });
        },

        .f64x2_gt => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asF64x2(a_v128);
            const b = simd.asF64x2(b_v128);
            var result: [2]i64 = undefined;
            for (0..2) |i| {
                result[i] = if (a[i] > b[i]) -1 else 0;
            }
            try stack.append(allocator, .{ .v128 = simd.fromI64x2(result) });
        },

        .f64x2_le => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asF64x2(a_v128);
            const b = simd.asF64x2(b_v128);
            var result: [2]i64 = undefined;
            for (0..2) |i| {
                result[i] = if (a[i] <= b[i]) -1 else 0;
            }
            try stack.append(allocator, .{ .v128 = simd.fromI64x2(result) });
        },

        .f64x2_ge => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asF64x2(a_v128);
            const b = simd.asF64x2(b_v128);
            var result: [2]i64 = undefined;
            for (0..2) |i| {
                result[i] = if (a[i] >= b[i]) -1 else 0;
            }
            try stack.append(allocator, .{ .v128 = simd.fromI64x2(result) });
        },

        .f64x2_abs => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asF64x2(a_v128);
            var result: [2]f64 = undefined;
            for (0..2) |i| {
                result[i] = @abs(a[i]);
            }
            try stack.append(allocator, .{ .v128 = simd.fromF64x2(result) });
        },

        .f64x2_neg => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asF64x2(a_v128);
            var result: [2]f64 = undefined;
            for (0..2) |i| {
                result[i] = -a[i];
            }
            try stack.append(allocator, .{ .v128 = simd.fromF64x2(result) });
        },

        .f64x2_sqrt => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asF64x2(a_v128);
            var result: [2]f64 = undefined;
            for (0..2) |i| {
                result[i] = @sqrt(a[i]);
            }
            try stack.append(allocator, .{ .v128 = simd.fromF64x2(result) });
        },

        .f64x2_add => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asF64x2(a_v128);
            const b = simd.asF64x2(b_v128);
            var result: [2]f64 = undefined;
            for (0..2) |i| {
                result[i] = a[i] + b[i];
            }
            try stack.append(allocator, .{ .v128 = simd.fromF64x2(result) });
        },

        .f64x2_sub => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asF64x2(a_v128);
            const b = simd.asF64x2(b_v128);
            var result: [2]f64 = undefined;
            for (0..2) |i| {
                result[i] = a[i] - b[i];
            }
            try stack.append(allocator, .{ .v128 = simd.fromF64x2(result) });
        },

        .f64x2_mul => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asF64x2(a_v128);
            const b = simd.asF64x2(b_v128);
            var result: [2]f64 = undefined;
            for (0..2) |i| {
                result[i] = a[i] * b[i];
            }
            try stack.append(allocator, .{ .v128 = simd.fromF64x2(result) });
        },

        .f64x2_div => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asF64x2(a_v128);
            const b = simd.asF64x2(b_v128);
            var result: [2]f64 = undefined;
            for (0..2) |i| {
                result[i] = a[i] / b[i];
            }
            try stack.append(allocator, .{ .v128 = simd.fromF64x2(result) });
        },

        .f64x2_min => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asF64x2(a_v128);
            const b = simd.asF64x2(b_v128);
            var result: [2]f64 = undefined;
            for (0..2) |i| {
                result[i] = @min(a[i], b[i]);
            }
            try stack.append(allocator, .{ .v128 = simd.fromF64x2(result) });
        },

        .f64x2_max => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asF64x2(a_v128);
            const b = simd.asF64x2(b_v128);
            var result: [2]f64 = undefined;
            for (0..2) |i| {
                result[i] = @max(a[i], b[i]);
            }
            try stack.append(allocator, .{ .v128 = simd.fromF64x2(result) });
        },

        .f64x2_pmin => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asF64x2(a_v128);
            const b = simd.asF64x2(b_v128);
            var result: [2]f64 = undefined;
            for (0..2) |i| {
                result[i] = if (b[i] < a[i]) b[i] else a[i];
            }
            try stack.append(allocator, .{ .v128 = simd.fromF64x2(result) });
        },

        .f64x2_pmax => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asF64x2(a_v128);
            const b = simd.asF64x2(b_v128);
            var result: [2]f64 = undefined;
            for (0..2) |i| {
                result[i] = if (a[i] < b[i]) b[i] else a[i];
            }
            try stack.append(allocator, .{ .v128 = simd.fromF64x2(result) });
        },

        .f64x2_ceil => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asF64x2(a_v128);
            var result: [2]f64 = undefined;
            for (0..2) |i| {
                result[i] = @ceil(a[i]);
            }
            try stack.append(allocator, .{ .v128 = simd.fromF64x2(result) });
        },

        .f64x2_floor => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asF64x2(a_v128);
            var result: [2]f64 = undefined;
            for (0..2) |i| {
                result[i] = @floor(a[i]);
            }
            try stack.append(allocator, .{ .v128 = simd.fromF64x2(result) });
        },

        .f64x2_trunc => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asF64x2(a_v128);
            var result: [2]f64 = undefined;
            for (0..2) |i| {
                result[i] = @trunc(a[i]);
            }
            try stack.append(allocator, .{ .v128 = simd.fromF64x2(result) });
        },

        .f64x2_nearest => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asF64x2(a_v128);
            var result: [2]f64 = undefined;
            for (0..2) |i| {
                result[i] = @round(a[i]);
            }
            try stack.append(allocator, .{ .v128 = simd.fromF64x2(result) });
        },

        // ===== CONVERSION OPERATIONS =====

        .i32x4_trunc_sat_f32x4_s => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asF32x4(a_v128);
            var result: [4]i32 = undefined;
            for (0..4) |i| {
                const val = @trunc(a[i]);
                result[i] = if (std.math.isNan(val)) 0 else if (val >= 2147483647.0) 2147483647 else if (val <= -2147483648.0) -2147483648 else @intFromFloat(val);
            }
            try stack.append(allocator, .{ .v128 = simd.fromI32x4(result) });
        },

        .i32x4_trunc_sat_f32x4_u => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asF32x4(a_v128);
            var result: [4]i32 = undefined;
            for (0..4) |i| {
                const val = @trunc(a[i]);
                result[i] = @bitCast(if (std.math.isNan(val)) @as(u32, 0) else if (val >= 4294967295.0) @as(u32, 4294967295) else if (val <= 0.0) @as(u32, 0) else @as(u32, @intFromFloat(val)));
            }
            try stack.append(allocator, .{ .v128 = simd.fromI32x4(result) });
        },

        .f32x4_convert_i32x4_s => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI32x4(a_v128);
            var result: [4]f32 = undefined;
            for (0..4) |i| {
                result[i] = @floatFromInt(a[i]);
            }
            try stack.append(allocator, .{ .v128 = simd.fromF32x4(result) });
        },

        .f32x4_convert_i32x4_u => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI32x4(a_v128);
            var result: [4]f32 = undefined;
            for (0..4) |i| {
                const au: u32 = @bitCast(a[i]);
                result[i] = @floatFromInt(au);
            }
            try stack.append(allocator, .{ .v128 = simd.fromF32x4(result) });
        },

        .i32x4_trunc_sat_f64x2_s_zero => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asF64x2(a_v128);
            var result: [4]i32 = .{ 0, 0, 0, 0 };
            for (0..2) |i| {
                const val = @trunc(a[i]);
                result[i] = if (std.math.isNan(val)) 0 else if (val >= 2147483647.0) 2147483647 else if (val <= -2147483648.0) -2147483648 else @intFromFloat(val);
            }
            try stack.append(allocator, .{ .v128 = simd.fromI32x4(result) });
        },

        .i32x4_trunc_sat_f64x2_u_zero => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asF64x2(a_v128);
            var result: [4]i32 = .{ 0, 0, 0, 0 };
            for (0..2) |i| {
                const val = @trunc(a[i]);
                result[i] = @bitCast(if (std.math.isNan(val)) @as(u32, 0) else if (val >= 4294967295.0) @as(u32, 4294967295) else if (val <= 0.0) @as(u32, 0) else @as(u32, @intFromFloat(val)));
            }
            try stack.append(allocator, .{ .v128 = simd.fromI32x4(result) });
        },

        .f64x2_convert_low_i32x4_s => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI32x4(a_v128);
            var result: [2]f64 = undefined;
            for (0..2) |i| {
                result[i] = @floatFromInt(a[i]);
            }
            try stack.append(allocator, .{ .v128 = simd.fromF64x2(result) });
        },

        .f64x2_convert_low_i32x4_u => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI32x4(a_v128);
            var result: [2]f64 = undefined;
            for (0..2) |i| {
                const au: u32 = @bitCast(a[i]);
                result[i] = @floatFromInt(au);
            }
            try stack.append(allocator, .{ .v128 = simd.fromF64x2(result) });
        },

        .f32x4_demote_f64x2_zero => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asF64x2(a_v128);
            var result: [4]f32 = .{ 0.0, 0.0, 0.0, 0.0 };
            for (0..2) |i| {
                result[i] = @floatCast(a[i]);
            }
            try stack.append(allocator, .{ .v128 = simd.fromF32x4(result) });
        },

        .f64x2_promote_low_f32x4 => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asF32x4(a_v128);
            var result: [2]f64 = undefined;
            for (0..2) |i| {
                result[i] = a[i];
            }
            try stack.append(allocator, .{ .v128 = simd.fromF64x2(result) });
        },

        // ===== BITWISE AND OTHER OPERATIONS =====

        .v128_not => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a = stack.pop().?.v128;
            var result: [16]u8 = undefined;
            for (0..16) |i| {
                result[i] = ~a[i];
            }
            try stack.append(allocator, .{ .v128 = result });
        },

        .v128_and => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b = stack.pop().?.v128;
            const a = stack.pop().?.v128;
            var result: [16]u8 = undefined;
            for (0..16) |i| {
                result[i] = a[i] & b[i];
            }
            try stack.append(allocator, .{ .v128 = result });
        },

        .v128_andnot => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b = stack.pop().?.v128;
            const a = stack.pop().?.v128;
            var result: [16]u8 = undefined;
            for (0..16) |i| {
                result[i] = a[i] & ~b[i];
            }
            try stack.append(allocator, .{ .v128 = result });
        },

        .v128_or => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b = stack.pop().?.v128;
            const a = stack.pop().?.v128;
            var result: [16]u8 = undefined;
            for (0..16) |i| {
                result[i] = a[i] | b[i];
            }
            try stack.append(allocator, .{ .v128 = result });
        },

        .v128_xor => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b = stack.pop().?.v128;
            const a = stack.pop().?.v128;
            var result: [16]u8 = undefined;
            for (0..16) |i| {
                result[i] = a[i] ^ b[i];
            }
            try stack.append(allocator, .{ .v128 = result });
        },

        .v128_bitselect => {
            if (stack.items.len < 3) return Error.StackUnderflow;
            const c = stack.pop().?.v128;
            const b = stack.pop().?.v128;
            const a = stack.pop().?.v128;
            var result: [16]u8 = undefined;
            for (0..16) |i| {
                result[i] = (a[i] & c[i]) | (b[i] & ~c[i]);
            }
            try stack.append(allocator, .{ .v128 = result });
        },

        .v128_any_true => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a = stack.pop().?.v128;
            var any_true: i32 = 0;
            for (a) |byte| {
                if (byte != 0) {
                    any_true = 1;
                    break;
                }
            }
            try stack.append(allocator, .{ .i32 = any_true });
        },

        // Shuffle and swizzle
        .i8x16_shuffle => {
            var lanes: [16]u8 = undefined;
            for (0..16) |i| {
                lanes[i] = try reader.readByte();
            }

            if (stack.items.len < 2) return Error.StackUnderflow;
            const b = stack.pop().?.v128;
            const a = stack.pop().?.v128;
            var result: [16]u8 = undefined;
            for (0..16) |i| {
                const lane_idx = lanes[i];
                result[i] = if (lane_idx < 16) a[lane_idx] else b[lane_idx - 16];
            }
            try stack.append(allocator, .{ .v128 = result });
        },

        .i8x16_swizzle => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const indices = stack.pop().?.v128;
            const a = stack.pop().?.v128;
            var result: [16]u8 = undefined;
            for (0..16) |i| {
                const idx = indices[i];
                result[i] = if (idx < 16) a[idx] else 0;
            }
            try stack.append(allocator, .{ .v128 = result });
        },

        // Extended pairwise operations
        .i16x8_extadd_pairwise_i8x16_s => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            var result: [8]i16 = undefined;
            for (0..8) |i| {
                const idx = i * 2;
                const val1: i16 = @as(i8, @bitCast(a_v128[idx]));
                const val2: i16 = @as(i8, @bitCast(a_v128[idx + 1]));
                result[i] = val1 + val2;
            }
            try stack.append(allocator, .{ .v128 = simd.fromI16x8(result) });
        },

        .i16x8_extadd_pairwise_i8x16_u => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            var result: [8]i16 = undefined;
            for (0..8) |i| {
                const idx = i * 2;
                const val1: i16 = @as(u8, a_v128[idx]);
                const val2: i16 = @as(u8, a_v128[idx + 1]);
                result[i] = val1 + val2;
            }
            try stack.append(allocator, .{ .v128 = simd.fromI16x8(result) });
        },

        .i32x4_extadd_pairwise_i16x8_s => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI16x8(a_v128);
            var result: [4]i32 = undefined;
            for (0..4) |i| {
                const idx = i * 2;
                result[i] = @as(i32, a[idx]) + @as(i32, a[idx + 1]);
            }
            try stack.append(allocator, .{ .v128 = simd.fromI32x4(result) });
        },

        .i32x4_extadd_pairwise_i16x8_u => {
            if (stack.items.len < 1) return Error.StackUnderflow;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI16x8(a_v128);
            var result: [4]i32 = undefined;
            for (0..4) |i| {
                const idx = i * 2;
                const val1: u16 = @bitCast(a[idx]);
                const val2: u16 = @bitCast(a[idx + 1]);
                result[i] = @bitCast(@as(u32, val1) + @as(u32, val2));
            }
            try stack.append(allocator, .{ .v128 = simd.fromI32x4(result) });
        },

        // Extended multiply operations for i16x8
        .i16x8_extmul_low_i8x16_s, .i16x8_extmul_high_i8x16_s, .i16x8_extmul_low_i8x16_u, .i16x8_extmul_high_i8x16_u => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            var result: [8]i16 = undefined;

            const start_idx: usize = switch (op) {
                .i16x8_extmul_low_i8x16_s, .i16x8_extmul_low_i8x16_u => 0,
                .i16x8_extmul_high_i8x16_s, .i16x8_extmul_high_i8x16_u => 8,
                else => return Error.InvalidOpcode,
            };

            const is_signed = switch (op) {
                .i16x8_extmul_low_i8x16_s, .i16x8_extmul_high_i8x16_s => true,
                else => false,
            };

            for (0..8) |i| {
                const idx = start_idx + i;
                if (is_signed) {
                    const ai: i16 = @as(i8, @bitCast(a_v128[idx]));
                    const bi: i16 = @as(i8, @bitCast(b_v128[idx]));
                    result[i] = ai *% bi;
                } else {
                    const au: i16 = @as(u8, a_v128[idx]);
                    const bu: i16 = @as(u8, b_v128[idx]);
                    result[i] = au *% bu;
                }
            }
            try stack.append(allocator, .{ .v128 = simd.fromI16x8(result) });
        },

        // Q15 multiply saturating
        .i16x8_q15mulr_sat_s => {
            if (stack.items.len < 2) return Error.StackUnderflow;
            const b_v128 = stack.pop().?.v128;
            const a_v128 = stack.pop().?.v128;
            const a = simd.asI16x8(a_v128);
            const b = simd.asI16x8(b_v128);
            var result: [8]i16 = undefined;
            for (0..8) |i| {
                const prod: i32 = (@as(i32, a[i]) * @as(i32, b[i]) + 0x4000) >> 15;
                result[i] = @intCast(@max(@min(prod, 32767), -32768));
            }
            try stack.append(allocator, .{ .v128 = simd.fromI16x8(result) });
        },

        // Lane load operations update a single lane from memory without touching others
        .v128_load8_lane, .v128_load16_lane, .v128_load32_lane, .v128_load64_lane => {
            const flags = try reader.readLEB128();
            const offset = try reader.readLEB128();
            const lane = try reader.readByte();
            _ = flags;

            if (stack.items.len < 2) return Error.StackUnderflow;
            var vec = stack.pop().?.v128;
            const addr_val = stack.pop().?;
            const addr = @as(u32, @bitCast(addr_val.i32)) + @as(u32, @intCast(offset));

            if (memory) |mem| {
                switch (op) {
                    .v128_load8_lane => {
                        if (lane >= 16) return Error.InvalidOpcode;
                        if (addr + 1 > mem.len) return Error.InvalidAccess;
                        vec[lane] = mem[addr];
                    },
                    .v128_load16_lane => {
                        if (lane >= 8) return Error.InvalidOpcode;
                        if (addr + 2 > mem.len) return Error.InvalidAccess;
                        const idx = lane * 2;
                        vec[idx] = mem[addr];
                        vec[idx + 1] = mem[addr + 1];
                    },
                    .v128_load32_lane => {
                        if (lane >= 4) return Error.InvalidOpcode;
                        if (addr + 4 > mem.len) return Error.InvalidAccess;
                        const idx = lane * 4;
                        @memcpy(vec[idx .. idx + 4], mem[addr .. addr + 4]);
                    },
                    .v128_load64_lane => {
                        if (lane >= 2) return Error.InvalidOpcode;
                        if (addr + 8 > mem.len) return Error.InvalidAccess;
                        const idx = lane * 8;
                        @memcpy(vec[idx .. idx + 8], mem[addr .. addr + 8]);
                    },
                    else => return Error.InvalidOpcode,
                }
                try stack.append(allocator, .{ .v128 = vec });
            } else {
                return Error.InvalidAccess;
            }
        },

        // Lane store operations spill a single lane out to memory
        .v128_store8_lane, .v128_store16_lane, .v128_store32_lane, .v128_store64_lane => {
            const flags = try reader.readLEB128();
            const offset = try reader.readLEB128();
            const lane = try reader.readByte();
            _ = flags;

            if (stack.items.len < 2) return Error.StackUnderflow;
            const vec = stack.pop().?.v128;
            const addr_val = stack.pop().?;
            const addr = @as(u32, @bitCast(addr_val.i32)) + @as(u32, @intCast(offset));

            if (memory) |mem| {
                switch (op) {
                    .v128_store8_lane => {
                        if (lane >= 16) return Error.InvalidOpcode;
                        if (addr + 1 > mem.len) return Error.InvalidAccess;
                        mem[addr] = vec[lane];
                    },
                    .v128_store16_lane => {
                        if (lane >= 8) return Error.InvalidOpcode;
                        if (addr + 2 > mem.len) return Error.InvalidAccess;
                        const idx = lane * 2;
                        mem[addr] = vec[idx];
                        mem[addr + 1] = vec[idx + 1];
                    },
                    .v128_store32_lane => {
                        if (lane >= 4) return Error.InvalidOpcode;
                        if (addr + 4 > mem.len) return Error.InvalidAccess;
                        const idx = lane * 4;
                        @memcpy(mem[addr .. addr + 4], vec[idx .. idx + 4]);
                    },
                    .v128_store64_lane => {
                        if (lane >= 2) return Error.InvalidOpcode;
                        if (addr + 8 > mem.len) return Error.InvalidAccess;
                        const idx = lane * 8;
                        @memcpy(mem[addr .. addr + 8], vec[idx .. idx + 8]);
                    },
                    else => return Error.InvalidOpcode,
                }
            } else {
                return Error.InvalidAccess;
            }
        },
    }
}
