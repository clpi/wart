pub const Type = enum {
    function,
    table,
    memory,
    global,

    pub fn fromByte(byte: u8) Type {
        return switch (byte) {
            0x00 => .function,
            0x01 => .table,
            0x02 => .memory,
            0x03 => .global,
            else => unreachable,
        };
    }
};
