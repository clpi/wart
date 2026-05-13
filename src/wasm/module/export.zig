pub const Export = @This();
pub const Type = @import("type.zig").Type;

name: []const u8,
kind: Type,
index: u32,

pub fn init(name: []const u8, kind: Type, index: u32) Export {
    return Export{
        .name = name,
        .kind = kind,
        .index = index,
    };
}
