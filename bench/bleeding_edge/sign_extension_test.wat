(module
  (func (export "test_i32_extend8_s") (result i32)
    i32.const 0xFF
    i32.extend8_s  ;; 0xC0
  )

  (func (export "test_i32_extend16_s") (result i32)
    i32.const 0xFFFF
    i32.extend16_s  ;; 0xC1
  )

  (func (export "test_i64_extend8_s") (result i64)
    i64.const 0x80
    i64.extend8_s  ;; 0xC2
  )

  (func (export "test_i64_extend16_s") (result i64)
    i64.const 0x8000
    i64.extend16_s  ;; 0xC3
  )

  (func (export "test_i64_extend32_s") (result i64)
    i64.const 0x80000000
    i64.extend32_s  ;; 0xC4
  )

  (func (export "_start")
    call 0
    drop
    call 1
    drop
    call 2
    drop
    call 3
    drop
    call 4
    drop
  )
)
