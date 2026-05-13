(module
  ;; Simple opcode testing across types
  (func $test_i32 (result i32)
    i32.const 10
    i32.const 5
    i32.add
    i32.const 3
    i32.mul
    i32.const 2
    i32.div_u
  )
  
  (func $test_i64 (result i64)
    i64.const 100
    i64.const 50
    i64.sub
    i64.const 2
    i64.mul
  )
  
  (func $test_f32 (result f32)
    f32.const 3.14
    f32.const 2.0
    f32.mul
  )
  
  (func $test_f64 (result f64)
    f64.const 2.718
    f64.const 3.14159
    f64.add
  )
  
  (func $main (result i32)
    ;; Run all tests and return i32 result
    call $test_i32
    drop
    call $test_i64
    drop
    call $test_f32
    drop
    call $test_f64
    drop
    
    ;; Return final result
    call $test_i32
  )
  
  (export "_start" (func $main))
)
