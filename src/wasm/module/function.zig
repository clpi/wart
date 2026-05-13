const value = @import("../value.zig");

type_index: u32,
code: []const u8,
locals: []value.Type,
imported: bool = false,
