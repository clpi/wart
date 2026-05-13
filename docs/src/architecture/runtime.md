# Runtime Core

The runtime core (`src/wasm/runtime.zig`) is the heart of wart.

## Module Loading

```zig
var runtime = try Runtime.init(allocator, io);
defer runtime.deinit();

const module = try runtime.loadModule(wasm_bytes);
```

## Execution

```zig
// Setup WASI
try runtime.setupWASI(args);

// Execute the start function
if (module.start_function_index) |start_idx| {
    _ = try runtime.executeFunction(start_idx, &[_]Value{});
}

// Or call a specific function
const func_idx = runtime.findExportedFunction("_start").?;
_ = try runtime.executeFunction(func_idx, &[_]Value{});
```

## Value Stack

The runtime uses `SmallVec(Value, 256)` for the value stack, optimized for the common case where most functions need fewer than 256 values.

```zig
pub const Value = union(ValueType) {
    i32: i32,
    i64: i64,
    f32: f32,
    f64: f64,
    v128: @Vector(16, u8),
    externref: usize,
    funcref: ?u32,
};
```

## Opcode Dispatch

Opcodes use `std.wasm.Opcode` for spec compliance. Fast dispatch via switch statement with inline operations:

```zig
switch (opcode) {
    .add_i32 => try fastBinaryArith(i32, "i32", add(i32), &stack),
    .mul_i64 => try fastBinaryArith(i64, "i64", mul(i64), &stack),
    // ...
}
```

## Error Handling

```zig
pub const Error = error{
    OutOfBounds,
    DivideByZero,
    IntegerOverflow,
    StackUnderflow,
    StackOverflow,
    Unreachable,
    // ...
};
```
