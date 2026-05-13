pub const Import = @This();
pub const Type = @import("type.zig").Type;

module: []const u8,
name: []const u8,
kind: Type,
type_index: u32,

pub fn init(module: []const u8, name: []const u8, kind: Type, type_index: u32) Import {
    return Import{
        .module = module,
        .name = name,
        .kind = kind,
        .type_index = type_index,
    };
}
