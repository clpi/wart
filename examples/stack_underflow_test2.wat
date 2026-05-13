(module
  (func $test_stack (result i32)
    ;; Push one value, then try to add (needs two)
    i32.const 42
    i32.add  ;; This should cause stack underflow
  )
  (export "_start" (func $test_stack))
)