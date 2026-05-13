(module
  ;; Entry point function
  (func $main (export "_start")
    ;; Just test that basic opcodes work
    i32.const 5
    i32.const 10
    i32.add
    drop

    i64.const 100
    i64.const 200
    i64.add
    drop
  )

  ;; Simple i32 arithmetic test
  (func $test_i32_add (export "test_i32_add") (param $a i32) (param $b i32) (result i32)
    local.get $a
    local.get $b
    i32.add
  )

  ;; i32 comparison test
  (func $test_i32_eq (export "test_i32_eq") (param $a i32) (param $b i32) (result i32)
    local.get $a
    local.get $b
    i32.eq
  )

  ;; i64 arithmetic test
  (func $test_i64_add (export "test_i64_add") (param $a i64) (param $b i64) (result i64)
    local.get $a
    local.get $b
    i64.add
  )

  ;; i64 comparison test
  (func $test_i64_lt_s (export "test_i64_lt_s") (param $a i64) (param $b i64) (result i32)
    local.get $a
    local.get $b
    i64.lt_s
  )

  ;; Bitwise operations test
  (func $test_i32_and (export "test_i32_and") (param $a i32) (param $b i32) (result i32)
    local.get $a
    local.get $b
    i32.and
  )

  ;; Local variables test
  (func $test_local_tee (export "test_local_tee") (param $a i32) (result i32)
    (local $temp i32)
    local.get $a
    i32.const 10
    i32.add
    local.tee $temp
    local.get $temp
    i32.mul
  )
)
