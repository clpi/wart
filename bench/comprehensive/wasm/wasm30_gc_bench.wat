
(module
  ;; WebAssembly GC Feature Benchmark
  ;; Tests struct types, arrays, and GC operations

  (type $point (struct
    (field $x f64)
    (field $y f64)
  ))

  (type $array_i32 (array (mut i32)))

  (global $iter_count (mut i32) (i32.const 10000))

  (func (export "gc_struct_ops") (result f64)
    (local $p (ref $point))
    (local $sum f64)
    (local $i i32)

    (local.set $sum (f64.const 0))

    ;; Create and manipulate structs
    (loop $iter
      ;; Create new point
      (struct.new_default $point)
      drop

      ;; Update iteration count
      (local.tee $i (i32.add (local.get $i) (i32.const 1)))
      (local.set $i)

      (br_if $iter (i32.lt_u (local.get $i) (global.get $iter_count)))
    )

    (local.get $sum)
  )

  (func (export "_start")
    ;; Run struct operations
    (drop (call 0))

    ;; Note: GC features may not be fully supported by all runtimes
    ;; This benchmark is primarily for feature detection
  )
)
