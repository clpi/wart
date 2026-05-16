const std = @import("std");

/// Leverage std.wasm for spec-compliant opcode definitions
pub const wasm = std.wasm;

/// Re-export standard library opcode enums for direct usage
pub const Opcode = wasm.Opcode;
pub const MiscOpcode = wasm.MiscOpcode;
pub const SimdOpcode = wasm.SimdOpcode;
pub const AtomicsOpcode = wasm.AtomicsOpcode;
pub const Valtype = wasm.Valtype;
pub const Section = wasm.Section;
pub const ExternalKind = wasm.ExternalKind;
pub const Limits = wasm.Limits;

/// SIMD V128 type from op/simd.zig
pub const V128 = @import("op/simd.zig").V128;

/// Runtime execution errors
pub const Error = error{
    StackUnderflow,
    StackOverflow,
    OutOfMemory,
    InvalidOpcode,
    TypeMismatch,
    UnknownImport,
    InvalidAccess,
    DivideByZero,
    MemoryGrowLimitReached,
    InstructionLimitExceeded,
    Trap,
};

/// Opcode category for dispatch optimization.
/// Uses std.wasm.Opcode for validation but provides grouped dispatch.
pub const Op = union(@import("op/type.zig").OpType) {
    control: Control,
    throw: Throw,
    branch: Branch,
    call: Call,
    local: Local,
    global: Global,
    ref: Ref,
    table: Table,
    memory: Memory,
    @"return": Return,
    i32: I32Op,
    i64: I64Op,
    f32: F32Op,
    f64: F64Op,
    v128: V128,
    threads: u32,

    /// Thread-safe opcode cache (computed lazily)
    var OPCACHE: [256]?Op = [_]?Op{null} **256;

    /// Match a byte to an Op variant.
    /// First tries std.wasm.Opcode for MVP opcodes, then handles proposal opcodes.
    pub inline fn match(o: u8) ?Op {
        if (OPCACHE[o]) |v| return v;

        // First try MVP opcodes via std.wasm.Opcode
        if (std.enums.fromInt(Opcode, o)) |opcode| {
            if (matchFromOpcode(opcode)) |r| {
                OPCACHE[o] = r;
                return r;
            }
        }

        // Handle proposal opcodes not in std.wasm.Opcode
        const r = matchProposalOpcode(o);
        OPCACHE[o] = r;
        return r;
    }

    /// Match proposal opcodes not in std.wasm.Opcode
    fn matchProposalOpcode(o: u8) ?Op {
        return switch (o) {
            // Exception handling proposal
            0x06 => .{ .throw = .@"try" },
            0x07 => .{ .throw = .@"catch" },
            0x08 => .{ .throw = .throw },
            0x09 => .{ .throw = .rethrow },
            0x0A => .{ .throw = .catch_all },

            // Tail call proposal
            0x12 => .{ .@"return" = .return_call },
            0x13 => .{ .@"return" = .return_call_indirect },

            // Typed function references proposal
            0x14 => .{ .call = .call_ref },
            0x15 => .{ .@"return" = .return_call_ref },
            0x1C => .{ .call = .select_t },

            // Reference types proposal - table operations
            0x25 => .{ .table = .get },
            0x26 => .{ .table = .set },

            // Reference types proposal - ref operations
            0xD0 => .{ .ref = .null },
            0xD1 => .{ .ref = .is_null },
            0xD2 => .{ .ref = .func },
            0xD3 => .{ .ref = .eq },
            0xD4 => .{ .ref = .as_non_null },

            // Reference types proposal - typed branches
            0xD5 => .{ .branch = .br_on_null },
            0xD6 => .{ .branch = .br_on_non_null },

            else => null,
        };
    }

    /// Convert std.wasm.Opcode to our grouped Op type
    fn matchFromOpcode(opcode: Opcode) ?Op {
        return switch (opcode) {
            // Control flow
            .@"unreachable", .nop, .block, .loop, .@"if", .@"else", .end => .{ .control = Control.fromOpcode(opcode) },

            // Branch
            .br, .br_if, .br_table => .{ .branch = Branch.fromOpcode(opcode) },

            // Call and parametric
            .call, .call_indirect, .drop, .select => .{ .call = Call.fromOpcode(opcode) },

            // Return
            .@"return" => .{ .@"return" = .@"return" },

            // Locals
            .local_get, .local_set, .local_tee => .{ .local = Local.fromOpcode(opcode) },

            // Globals
            .global_get, .global_set => .{ .global = Global.fromOpcode(opcode) },

            // Table operations (table_get/table_set use extended prefix in std.wasm)
            // .table_get, .table_set => .{ .table = Table.fromOpcode(opcode) },

            // Memory size/grow
            .memory_size, .memory_grow => .{ .memory = Memory.fromOpcode(opcode) },

            // Reference types (not in std.wasm.Opcode)
            // .ref_null, .ref_is_null, .ref_func => .{ .ref = Ref.fromOpcode(opcode) },

            // Extended prefix (bulk memory, table ops)
            .misc_prefix => .{ .table = .extended },

            // SIMD prefix
            .simd_prefix => .{ .v128 = @enumFromInt(0xFD) },

            // Atomics/threads prefix
            .atomics_prefix => .{ .threads = 0xFE },

            // i32 operations
            .i32_load,
            .i32_load8_s,
            .i32_load8_u,
            .i32_load16_s,
            .i32_load16_u,
            .i32_store,
            .i32_store8,
            .i32_store16,
            .i32_const,
            .i32_eqz,
            .i32_eq,
            .i32_ne,
            .i32_lt_s,
            .i32_lt_u,
            .i32_gt_s,
            .i32_gt_u,
            .i32_le_s,
            .i32_le_u,
            .i32_ge_s,
            .i32_ge_u,
            .i32_clz,
            .i32_ctz,
            .i32_popcnt,
            .i32_add,
            .i32_sub,
            .i32_mul,
            .i32_div_s,
            .i32_div_u,
            .i32_rem_s,
            .i32_rem_u,
            .i32_and,
            .i32_or,
            .i32_xor,
            .i32_shl,
            .i32_shr_s,
            .i32_shr_u,
            .i32_rotl,
            .i32_rotr,
            .i32_wrap_i64,
            .i32_trunc_f32_s,
            .i32_trunc_f32_u,
            .i32_trunc_f64_s,
            .i32_trunc_f64_u,
            .i32_reinterpret_f32,
            .i32_extend8_s,
            .i32_extend16_s,
            => .{ .i32 = I32Op.fromOpcode(opcode) },

            // i64 operations
            .i64_load,
            .i64_load8_s,
            .i64_load8_u,
            .i64_load16_s,
            .i64_load16_u,
            .i64_load32_s,
            .i64_load32_u,
            .i64_store,
            .i64_store8,
            .i64_store16,
            .i64_store32,
            .i64_const,
            .i64_eqz,
            .i64_eq,
            .i64_ne,
            .i64_lt_s,
            .i64_lt_u,
            .i64_gt_s,
            .i64_gt_u,
            .i64_le_s,
            .i64_le_u,
            .i64_ge_s,
            .i64_ge_u,
            .i64_clz,
            .i64_ctz,
            .i64_popcnt,
            .i64_add,
            .i64_sub,
            .i64_mul,
            .i64_div_s,
            .i64_div_u,
            .i64_rem_s,
            .i64_rem_u,
            .i64_and,
            .i64_or,
            .i64_xor,
            .i64_shl,
            .i64_shr_s,
            .i64_shr_u,
            .i64_rotl,
            .i64_rotr,
            .i64_extend_i32_s,
            .i64_extend_i32_u,
            .i64_trunc_f32_s,
            .i64_trunc_f32_u,
            .i64_trunc_f64_s,
            .i64_trunc_f64_u,
            .i64_reinterpret_f64,
            .i64_extend8_s,
            .i64_extend16_s,
            .i64_extend32_s,
            => .{ .i64 = I64Op.fromOpcode(opcode) },

            // f32 operations
            .f32_load,
            .f32_store,
            .f32_const,
            .f32_eq,
            .f32_ne,
            .f32_lt,
            .f32_gt,
            .f32_le,
            .f32_ge,
            .f32_abs,
            .f32_neg,
            .f32_ceil,
            .f32_floor,
            .f32_trunc,
            .f32_nearest,
            .f32_sqrt,
            .f32_add,
            .f32_sub,
            .f32_mul,
            .f32_div,
            .f32_min,
            .f32_max,
            .f32_copysign,
            .f32_convert_i32_s,
            .f32_convert_i32_u,
            .f32_convert_i64_s,
            .f32_convert_i64_u,
            .f32_demote_f64,
            .f32_reinterpret_i32,
            => .{ .f32 = F32Op.fromOpcode(opcode) },

            // f64 operations
            .f64_load,
            .f64_store,
            .f64_const,
            .f64_eq,
            .f64_ne,
            .f64_lt,
            .f64_gt,
            .f64_le,
            .f64_ge,
            .f64_abs,
            .f64_neg,
            .f64_ceil,
            .f64_floor,
            .f64_trunc,
            .f64_nearest,
            .f64_sqrt,
            .f64_add,
            .f64_sub,
            .f64_mul,
            .f64_div,
            .f64_min,
            .f64_max,
            .f64_copysign,
            .f64_convert_i32_s,
            .f64_convert_i32_u,
            .f64_convert_i64_s,
            .f64_convert_i64_u,
            .f64_promote_f32,
            .f64_reinterpret_i64,
            => .{ .f64 = F64Op.fromOpcode(opcode) },

            // Exception handling (proposals) - not in std.wasm.Opcode
            // .@"try", .@"catch", .throw, .rethrow, .catch_all => .{ .throw = Throw.fromOpcode(opcode) },

            // Tail call proposal - not in std.wasm.Opcode
            // .return_call, .return_call_indirect => .{ .@"return" = Return.fromOpcode(opcode) },

            // Typed function references proposal - not in std.wasm.Opcode
            // .select_t, .call_ref, .return_call_ref, .ref_as_non_null, .br_on_null, .br_on_non_null => ...

            // Unhandled opcodes
            _ => null,
        };
    }

    /// Control flow opcodes - mapped from std.wasm.Opcode
    pub const Control = enum(u8) {
        @"unreachable" = 0x00,
        nop = 0x01,
        block = 0x02,
        loop = 0x03,
        @"if" = 0x04,
        @"else" = 0x05,
        end = 0x0B,

        pub inline fn fromOpcode(opcode: Opcode) @This() {
            return @enumFromInt(@intFromEnum(opcode));
        }
    };

    /// Branch opcodes
    pub const Branch = enum(u8) {
        br = 0x0C,
        br_if = 0x0D,
        br_table = 0x0E,
        br_on_null = 0xD5,
        br_on_non_null = 0xD6,

        pub inline fn fromOpcode(opcode: Opcode) @This() {
            return @enumFromInt(@intFromEnum(opcode));
        }
    };

    /// Call and parametric opcodes
    pub const Call = enum(u8) {
        call = 0x10,
        call_indirect = 0x11,
        call_ref = 0x14,
        drop = 0x1A,
        select = 0x1B,
        select_t = 0x1C,
        delegate = 0xFD,

        pub inline fn fromOpcode(opcode: Opcode) @This() {
            return @enumFromInt(@intFromEnum(opcode));
        }
    };

    /// Return opcodes (including tail call proposal)
    pub const Return = enum(u8) {
        @"return" = 0x0F,
        return_call = 0x12,
        return_call_indirect = 0x13,
        return_call_ref = 0x15,

        pub inline fn fromOpcode(opcode: Opcode) @This() {
            return @enumFromInt(@intFromEnum(opcode));
        }
    };

    /// Exception handling opcodes
    pub const Throw = enum(u8) {
        @"try" = 0x06,
        @"catch" = 0x07,
        throw = 0x08,
        rethrow = 0x09,
        catch_all = 0x0A,
        throw_ref = 0xFB,

        pub inline fn fromOpcode(opcode: Opcode) @This() {
            return @enumFromInt(@intFromEnum(opcode));
        }
    };

    /// Local variable opcodes
    pub const Local = enum(u8) {
        get = 0x20,
        set = 0x21,
        tee = 0x22,

        pub inline fn fromOpcode(opcode: Opcode) @This() {
            return @enumFromInt(@intFromEnum(opcode));
        }
    };

    /// Global variable opcodes
    pub const Global = enum(u8) {
        get = 0x23,
        set = 0x24,

        pub inline fn fromOpcode(opcode: Opcode) @This() {
            return @enumFromInt(@intFromEnum(opcode));
        }
    };

    /// Reference type opcodes
    pub const Ref = enum(u8) {
        null = 0xD0,
        is_null = 0xD1,
        func = 0xD2,
        eq = 0xD3,
        as_non_null = 0xD4,

        pub inline fn fromOpcode(opcode: Opcode) @This() {
            return @enumFromInt(@intFromEnum(opcode));
        }
    };

    /// Table opcodes
    pub const Table = enum(u8) {
        get = 0x25,
        set = 0x26,
        extended = 0xFC,

        pub inline fn fromOpcode(opcode: Opcode) @This() {
            return @enumFromInt(@intFromEnum(opcode));
        }
    };

    /// Memory opcodes
    pub const Memory = enum(u8) {
        size = 0x3F,
        grow = 0x40,

        pub inline fn fromOpcode(opcode: Opcode) @This() {
            return @enumFromInt(@intFromEnum(opcode));
        }
    };

    /// i32 operations - uses std.wasm.Opcode values
    pub const I32Op = enum(u8) {
        load = 0x28,
        load8_s = 0x2C,
        load8_u = 0x2D,
        load16_s = 0x2E,
        load16_u = 0x2F,
        store = 0x36,
        store8 = 0x3A,
        store16 = 0x3B,
        @"const" = 0x41,
        eqz = 0x45,
        eq = 0x46,
        ne = 0x47,
        lt_s = 0x48,
        lt_u = 0x49,
        gt_s = 0x4A,
        gt_u = 0x4B,
        le_s = 0x4C,
        le_u = 0x4D,
        ge_s = 0x4E,
        ge_u = 0x4F,
        clz = 0x67,
        ctz = 0x68,
        popcnt = 0x69,
        add = 0x6A,
        sub = 0x6B,
        mul = 0x6C,
        div_s = 0x6D,
        div_u = 0x6E,
        rem_s = 0x6F,
        rem_u = 0x70,
        @"and" = 0x71,
        @"or" = 0x72,
        xor = 0x73,
        shl = 0x74,
        shr_s = 0x75,
        shr_u = 0x76,
        rotl = 0x77,
        rotr = 0x78,
        wrap_i64 = 0xA7,
        trunc_f32_s = 0xA8,
        trunc_f32_u = 0xA9,
        trunc_f64_s = 0xAA,
        trunc_f64_u = 0xAB,
        reinterpret_f32 = 0xBC,
        extend8_s = 0xC0,
        extend16_s = 0xC1,

        pub inline fn fromOpcode(opcode: Opcode) @This() {
            return @enumFromInt(@intFromEnum(opcode));
        }

        /// Convert to std.wasm.Opcode for spec validation
        pub inline fn toOpcode(self: @This()) Opcode {
            return @enumFromInt(@intFromEnum(self));
        }
    };

    /// i64 operations - uses std.wasm.Opcode values
    pub const I64Op = enum(u8) {
        load = 0x29,
        load8_s = 0x30,
        load8_u = 0x31,
        load16_s = 0x32,
        load16_u = 0x33,
        load32_s = 0x34,
        load32_u = 0x35,
        store = 0x37,
        store8 = 0x3C,
        store16 = 0x3D,
        store32 = 0x3E,
        @"const" = 0x42,
        eqz = 0x50,
        eq = 0x51,
        ne = 0x52,
        lt_s = 0x53,
        lt_u = 0x54,
        gt_s = 0x55,
        gt_u = 0x56,
        le_s = 0x57,
        le_u = 0x58,
        ge_s = 0x59,
        ge_u = 0x5A,
        clz = 0x79,
        ctz = 0x7A,
        popcnt = 0x7B,
        add = 0x7C,
        sub = 0x7D,
        mul = 0x7E,
        div_s = 0x7F,
        div_u = 0x80,
        rem_s = 0x81,
        rem_u = 0x82,
        @"and" = 0x83,
        @"or" = 0x84,
        xor = 0x85,
        shl = 0x86,
        shr_s = 0x87,
        shr_u = 0x88,
        rotl = 0x89,
        rotr = 0x8A,
        extend_i32_s = 0xAC,
        extend_i32_u = 0xAD,
        trunc_f32_s = 0xAE,
        trunc_f32_u = 0xAF,
        trunc_f64_s = 0xB0,
        trunc_f64_u = 0xB1,
        reinterpret_f64 = 0xBD,
        extend8_s = 0xC2,
        extend16_s = 0xC3,
        extend32_s = 0xC4,

        pub inline fn fromOpcode(opcode: Opcode) @This() {
            return @enumFromInt(@intFromEnum(opcode));
        }

        pub inline fn toOpcode(self: @This()) Opcode {
            return @enumFromInt(@intFromEnum(self));
        }
    };

    /// f32 operations - uses std.wasm.Opcode values
    pub const F32Op = enum(u8) {
        load = 0x2A,
        store = 0x38,
        @"const" = 0x43,
        eq = 0x5B,
        ne = 0x5C,
        lt = 0x5D,
        gt = 0x5E,
        le = 0x5F,
        ge = 0x60,
        abs = 0x8B,
        neg = 0x8C,
        ceil = 0x8D,
        floor = 0x8E,
        trunc = 0x8F,
        nearest = 0x90,
        sqrt = 0x91,
        add = 0x92,
        sub = 0x93,
        mul = 0x94,
        div = 0x95,
        min = 0x96,
        max = 0x97,
        copysign = 0x98,
        convert_i32_s = 0xB2,
        convert_i32_u = 0xB3,
        convert_i64_s = 0xB4,
        convert_i64_u = 0xB5,
        demote_f64 = 0xB6,
        reinterpret_i32 = 0xBE,

        pub inline fn fromOpcode(opcode: Opcode) @This() {
            return @enumFromInt(@intFromEnum(opcode));
        }

        pub inline fn toOpcode(self: @This()) Opcode {
            return @enumFromInt(@intFromEnum(self));
        }
    };

    /// f64 operations - uses std.wasm.Opcode values
    pub const F64Op = enum(u8) {
        load = 0x2B,
        store = 0x39,
        @"const" = 0x44,
        eq = 0x61,
        ne = 0x62,
        lt = 0x63,
        gt = 0x64,
        le = 0x65,
        ge = 0x66,
        abs = 0x99,
        neg = 0x9A,
        ceil = 0x9B,
        floor = 0x9C,
        trunc = 0x9D,
        nearest = 0x9E,
        sqrt = 0x9F,
        add = 0xA0,
        sub = 0xA1,
        mul = 0xA2,
        div = 0xA3,
        min = 0xA4,
        max = 0xA5,
        copysign = 0xA6,
        convert_i32_s = 0xB7,
        convert_i32_u = 0xB8,
        convert_i64_s = 0xB9,
        convert_i64_u = 0xBA,
        promote_f32 = 0xBB,
        reinterpret_i64 = 0xBF,

        pub inline fn fromOpcode(opcode: Opcode) @This() {
            return @enumFromInt(@intFromEnum(opcode));
        }

        pub inline fn toOpcode(self: @This()) Opcode {
            return @enumFromInt(@intFromEnum(self));
        }
    };

    // Backward compatibility aliases
    pub const I32 = I32Op;
    pub const I64 = I64Op;
    pub const F32 = F32Op;
    pub const F64 = F64Op;
};
