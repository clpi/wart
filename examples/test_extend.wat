(module
  ;; Test i32.extend8_s and i32.extend16_s opcodes
  (func $test_extend8_s (param $input i32) (result i32)
    local.get $input
    i32.extend8_s
  )
  
  (func $test_extend16_s (param $input i32) (result i32)
    local.get $input
    i32.extend16_s
  )
  
  ;; Test cases
  (func $test_extend8_positive (result i32)
    i32.const 0x7F    ;; 127 - fits in i8
    call $test_extend8_s
  )
  
  (func $test_extend8_negative (result i32)
    i32.const 0xFF80  ;; -128 in 16-bit, should sign-extend to -128
    call $test_extend8_s
  )
  
  (func $test_extend16_positive (result i32)
    i32.const 0x7FFF  ;; 32767 - fits in i16
    call $test_extend16_s
  )
  
  (func $test_extend16_negative (result i32)
    i32.const 0xFFFF8000  ;; -32768 in 32-bit, should sign-extend to -32768
    call $test_extend16_s
  )
  
  ;; Main test function
  (func $main (result i32)
    ;; Test extend8_s with positive value
    call $test_extend8_positive
    i32.const 127
    i32.eq
    
    ;; Test extend8_s with negative value  
    call $test_extend8_negative
    i32.const -128
    i32.eq
    i32.and
    
    ;; Test extend16_s with positive value
    call $test_extend16_positive
    i32.const 32767
    i32.eq
    i32.and
    
    ;; Test extend16_s with negative value
    call $test_extend16_negative
    i32.const -32768
    i32.eq
    i32.and
  )
  
  (export "_start" (func $main))
)