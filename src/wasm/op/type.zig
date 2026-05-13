const std = @import("std");

pub const OpType = enum(u5) {
    control,
    throw,
    branch,
    call,
    local,
    global,
    ref,
    table,
    // parametric and variable merged under other groups in runtime
    memory,
    @"return",
    i32,
    i64,
    f32,
    f64,
    v128,
    threads,
};
