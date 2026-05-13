
(module
  ;; WebAssembly Exception Handling Benchmark

  (tag $error_tag (param i32))

  (global $iter_count (mut i32) (i32.const 10000))

  (func $thrower (result i32)
    (throw $error_tag (i32.const 42))
  )

  (func (export "exception_ops") (result i32)
    (local $i i32)
    (local $caught i32)

    (local.set $caught (i32.const 0))

    (loop $iter
      (try (do
        (block $catch_block
          (try_table (do
            (call $thrower)
          )
          (catch $error_tag $catch_block
            (local.set $caught (i32.add (local.get $caught) (i32.const 1)))
          )
        )
      ))

      (local.tee $i (i32.add (local.get $i) (i32.const 1)))
      (local.set $i)

      (br_if $iter (i32.lt_u (local.get $i) (local.get $iter_count)))
    )

    (local.get $caught)
  )

  (func (export "_start")
    (drop (call 0))
  )
)
