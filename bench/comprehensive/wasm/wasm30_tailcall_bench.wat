(module
  ;; WebAssembly Tail Call Benchmark
  ;; Tests tail call optimization and return_call instructions

  ;; Tail-recursive factorial
  (func $fact_tail (param $n i32) (param $acc i32) (result i32)
    (if (result i32) (i32.eq (local.get $n) (i32.const 0))
      (then (local.get $acc))
      (else
        (return_call $fact_tail
          (i32.sub (local.get $n) (i32.const 1))
          (i32.mul (local.get $n) (local.get $acc)))
      )
    )
  )

  ;; Tail-recursive fibonacci
  (func $fib_tail (param $n i32) (param $a i32) (param $b i32) (result i32)
    (if (result i32) (i32.eq (local.get $n) (i32.const 0))
      (then (local.get $a))
      (else
        (if (result i32) (i32.eq (local.get $n) (i32.const 1))
          (then (local.get $b))
          (else
            (return_call $fib_tail
              (i32.sub (local.get $n) (i32.const 1))
              (local.get $b)
              (i32.add (local.get $a) (local.get $b)))
          )
        )
      )
    )
  )

  ;; Test function
  (func (export "_start")
    ;; Factorial of 10
    (drop (call $fact_tail (i32.const 10) (i32.const 1)))
    
    ;; Fibonacci of 20
    (drop (call $fib_tail (i32.const 20) (i32.const 0) (i32.const 1)))
  )
)