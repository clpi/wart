const std = @import("std");

/// Component Model type system
pub const ComponentValType = union(enum) {
    // Primitive types
    bool,
    s8,
    u8,
    s16,
    u16,
    s32,
    u32,
    s64,
    u64,
    f32,
    f64,
    char,
    string,

    // Container types
    list: *ComponentValType,
    record: []Field,
    variant: []Case,
    tuple: []ComponentValType,
    flags: [][]const u8,
    @"enum": [][]const u8,
    option: *ComponentValType,
    result: Result,
    own: u32, // Resource type index
    borrow: u32, // Resource type index

    pub const Field = struct {
        name: []const u8,
        type: *ComponentValType,
    };

    pub const Case = struct {
        name: []const u8,
        type: ?*ComponentValType,
    };

    pub const Result = struct {
        ok: ?*ComponentValType,
        err: ?*ComponentValType,
    };
};

/// Component function type
pub const ComponentFuncType = struct {
    params: []Param,
    results: ?*ComponentValType, // single result or result type

    pub const Param = struct {
        name: []const u8,
        type: *ComponentValType,
    };
};

/// Component type definition
pub const ComponentTypeRef = union(enum) {
    defined: *ComponentValType,
    func: *ComponentFuncType,
    component: u32, // Component type index
    instance: u32, // Instance type index
    resource: Resource,

    pub const Resource = struct {
        rep: u32, // Representation type
        dtor: ?u32, // Optional destructor function
    };
};

/// Canonical ABI options
pub const CanonicalOptions = struct {
    memory: ?u32 = null,
    realloc: ?u32 = null,
    post_return: ?u32 = null,
    string_encoding: StringEncoding = .utf8,

    pub const StringEncoding = enum {
        utf8,
        utf16,
        latin1_utf16,
    };
};

/// Canonical function definition
pub const CanonicalFunction = union(enum) {
    lift: Lift,
    lower: Lower,
    resource_new: ResourceNew,
    resource_drop: ResourceDrop,
    resource_rep: ResourceRep,

    pub const Lift = struct {
        core_func_index: u32,
        type_index: u32,
        options: CanonicalOptions,
    };

    pub const Lower = struct {
        func_index: u32,
        options: CanonicalOptions,
    };

    pub const ResourceNew = struct {
        resource_index: u32,
    };

    pub const ResourceDrop = struct {
        resource_index: u32,
    };

    pub const ResourceRep = struct {
        resource_index: u32,
    };
};

/// Component import
pub const ComponentImport = struct {
    name: []const u8,
    type_ref: ComponentTypeRef,
};

/// Component export
pub const ComponentExport = struct {
    name: []const u8,
    kind: ExportKind,
    index: u32,

    pub const ExportKind = enum(u8) {
        core_module = 0x00,
        func = 0x01,
        value = 0x02,
        type = 0x03,
        component = 0x04,
        instance = 0x05,
    };
};

/// Alias definition
pub const Alias = union(enum) {
    outer: Outer,
    @"export": Export,

    pub const Outer = struct {
        kind: AliasKind,
        count: u32,
        index: u32,
    };

    pub const Export = struct {
        kind: AliasKind,
        instance_index: u32,
        name: []const u8,
    };

    pub const AliasKind = enum(u8) {
        core_type = 0x00,
        core_module = 0x01,
        core_instance = 0x02,
        type = 0x03,
        func = 0x04,
        value = 0x05,
        component = 0x06,
        instance = 0x07,
    };
};
