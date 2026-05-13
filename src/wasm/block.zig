const ValueType = @import("value.zig").Type;

// Type of block
pub const Type = enum {
    block,
    loop,
    @"if",
    @"else",
    @"try",
    @"catch",
    catch_all,
};

/// The kind of block
type: Type,

/// The position of the block in the binary
pos: usize,

/// The position of the block in the binary
start_stack_size: usize,

/// The position of the else block in the binary
else_pos: ?usize = null,

/// The end block position
end_pos: ?usize = null,

/// The result value type
result_type: ?ValueType = null,

/// For exception handling: the tag index used for the catch
/// Only valid for catch blocks
tag_index: ?usize = null,

/// For exception handling: whether an exception is active
/// Only valid for try blocks
has_active_exception: bool = false,
