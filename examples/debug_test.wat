(module
  ;; Simple test to demonstrate the new debug formatting
  (func $test_arithmetic (param $a i32) (param $b i32) (result i32)
    local.get $a
    local.get $b
    i32.add
    local.get $a
    i32.mul
  )
  
  (func $main (result i32)
    i32.const 10
    i32.const 20
    call $test_arithmetic
  )
  
  (export "_start" (func $main))
)