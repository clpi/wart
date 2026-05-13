(module
  (func $test_stack (result i32)
    ;; This should cause stack underflow - trying to pop from empty stack
    i32.add
  )
  (export "_start" (func $test_stack))
)