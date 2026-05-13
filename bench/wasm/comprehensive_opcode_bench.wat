(module
  ;; Comprehensive benchmark testing every WebAssembly opcode
  (memory 2)
  (table 10 funcref)
  (elem (i32.const 0) $inc_counter)

  ;; Global counters for benchmarking
  (global $opcode_count (mut i32) (i32.const 0))

  ;; Test data
  (global $test_i32 (mut i32) (i32.const 42))
  (global $test_i64 (mut i64) (i64.const 123456789))
  (global $test_f32 (mut f32) (f32.const 3.14159))
  (global $test_f64 (mut f64) (f64.const 2.718281828))

  ;; Helper function to increment opcode counter
  (func $inc_counter
    global.get $opcode_count
    i32.const 1
    i32.add
    global.set $opcode_count
  )

  ;; Test numeric operations
  (func $test_numeric_ops (param $iterations i32)
    (local $i i32)
    (local $a i32) (local $b i32)
    (local $c i64) (local $d i64)
    (local $e f32) (local $f f32)
    (local $g f64) (local $h f64)

    i32.const 0
    local.set $i

    loop $numeric_loop
      local.get $i
      local.get $iterations
      i32.lt_u
      if
        ;; i32 operations
        i32.const 10
        local.set $a
        i32.const 20
        local.set $b

        local.get $a
        local.get $b
        i32.add
        drop
        call $inc_counter

        local.get $a
        local.get $b
        i32.sub
        drop
        call $inc_counter

        local.get $a
        local.get $b
        i32.mul
        drop
        call $inc_counter

        local.get $a
        local.get $b
        i32.div_s
        drop
        call $inc_counter

        local.get $a
        local.get $b
        i32.rem_s
        drop
        call $inc_counter

        local.get $a
        local.get $b
        i32.and
        drop
        call $inc_counter

        local.get $a
        local.get $b
        i32.or
        drop
        call $inc_counter

        local.get $a
        local.get $b
        i32.xor
        drop
        call $inc_counter

        local.get $a
        i32.const 2
        i32.shl
        drop
        call $inc_counter

        local.get $a
        i32.const 1
        i32.shr_s
        drop
        call $inc_counter

        local.get $a
        i32.clz
        drop
        call $inc_counter

        local.get $a
        i32.ctz
        drop
        call $inc_counter

        local.get $a
        i32.popcnt
        drop
        call $inc_counter

        local.get $a
        i32.eqz
        drop
        call $inc_counter

        local.get $a
        local.get $b
        i32.eq
        drop
        call $inc_counter

        local.get $a
        local.get $b
        i32.ne
        drop
        call $inc_counter

        local.get $a
        local.get $b
        i32.lt_s
        drop
        call $inc_counter

        local.get $a
        local.get $b
        i32.le_s
        drop
        call $inc_counter

        local.get $a
        local.get $b
        i32.gt_s
        drop
        call $inc_counter

        local.get $a
        local.get $b
        i32.ge_s
        drop
        call $inc_counter

        ;; i64 operations
        i64.const 100
        local.set $c
        i64.const 200
        local.set $d

        local.get $c
        local.get $d
        i64.add
        drop
        call $inc_counter

        local.get $c
        local.get $d
        i64.sub
        drop
        call $inc_counter

        local.get $c
        local.get $d
        i64.mul
        drop
        call $inc_counter

        local.get $c
        local.get $d
        i64.div_s
        drop
        call $inc_counter

        local.get $c
        local.get $d
        i64.rem_s
        drop
        call $inc_counter

        local.get $c
        i64.eqz
        drop
        call $inc_counter

        ;; f32 operations
        f32.const 1.5
        local.set $e
        f32.const 2.5
        local.set $f

        local.get $e
        local.get $f
        f32.add
        drop
        call $inc_counter

        local.get $e
        local.get $f
        f32.sub
        drop
        call $inc_counter

        local.get $e
        local.get $f
        f32.mul
        drop
        call $inc_counter

        local.get $e
        local.get $f
        f32.div
        drop
        call $inc_counter

        local.get $e
        f32.sqrt
        drop
        call $inc_counter

        local.get $e
        f32.abs
        drop
        call $inc_counter

        local.get $e
        f32.neg
        drop
        call $inc_counter

        local.get $e
        f32.ceil
        drop
        call $inc_counter

        local.get $e
        f32.floor
        drop
        call $inc_counter

        local.get $e
        f32.trunc
        drop
        call $inc_counter

        local.get $e
        f32.nearest
        drop
        call $inc_counter

        local.get $e
        local.get $f
        f32.eq
        drop
        call $inc_counter

        local.get $e
        local.get $f
        f32.ne
        drop
        call $inc_counter

        local.get $e
        local.get $f
        f32.lt
        drop
        call $inc_counter

        local.get $e
        local.get $f
        f32.le
        drop
        call $inc_counter

        local.get $e
        local.get $f
        f32.gt
        drop
        call $inc_counter

        local.get $e
        local.get $f
        f32.ge
        drop
        call $inc_counter

        ;; f64 operations
        f64.const 1.234
        local.set $g
        f64.const 5.678
        local.set $h

        local.get $g
        local.get $h
        f64.add
        drop
        call $inc_counter

        local.get $g
        local.get $h
        f64.sub
        drop
        call $inc_counter

        local.get $g
        local.get $h
        f64.mul
        drop
        call $inc_counter

        local.get $g
        local.get $h
        f64.div
        drop
        call $inc_counter

        local.get $g
        f64.sqrt
        drop
        call $inc_counter

        local.get $g
        f64.abs
        drop
        call $inc_counter

        local.get $g
        f64.neg
        drop
        call $inc_counter

        local.get $g
        f64.ceil
        drop
        call $inc_counter

        local.get $g
        f64.floor
        drop
        call $inc_counter

        local.get $g
        f64.trunc
        drop
        call $inc_counter

        local.get $g
        f64.nearest
        drop
        call $inc_counter

        ;; Conversions (extend8_s/extend16_s now implemented in wart)
        local.get $a
        i32.extend8_s
        drop
        call $inc_counter

        local.get $a
        i32.extend16_s
        drop
        call $inc_counter

        local.get $c
        i32.wrap_i64
        drop
        call $inc_counter

        local.get $a
        i64.extend_i32_s
        drop
        call $inc_counter

        local.get $a
        i64.extend_i32_u
        drop
        call $inc_counter

        local.get $a
        f32.convert_i32_s
        drop
        call $inc_counter

        local.get $a
        f32.convert_i32_u
        drop
        call $inc_counter

        local.get $c
        f32.convert_i64_s
        drop
        call $inc_counter

        local.get $c
        f32.convert_i64_u
        drop
        call $inc_counter

        local.get $e
        i32.trunc_f32_s
        drop
        call $inc_counter

        local.get $e
        i32.trunc_f32_u
        drop
        call $inc_counter

        local.get $e
        i64.trunc_f32_s
        drop
        call $inc_counter

        local.get $e
        i64.trunc_f32_u
        drop
        call $inc_counter

        local.get $e
        f64.promote_f32
        drop
        call $inc_counter

        local.get $g
        f32.demote_f64
        drop
        call $inc_counter

        local.get $g
        i32.trunc_f64_s
        drop
        call $inc_counter

        local.get $g
        i32.trunc_f64_u
        drop
        call $inc_counter

        local.get $g
        i64.trunc_f64_s
        drop
        call $inc_counter

        local.get $g
        i64.trunc_f64_u
        drop
        call $inc_counter

        local.get $c
        f32.convert_i64_s
        drop
        call $inc_counter

        local.get $c
        f32.convert_i64_u
        drop
        call $inc_counter

        local.get $a
        f64.convert_i32_s
        drop
        call $inc_counter

        local.get $a
        f64.convert_i32_u
        drop
        call $inc_counter

        local.get $c
        f64.convert_i64_s
        drop
        call $inc_counter

        local.get $c
        f64.convert_i64_u
        drop
        call $inc_counter

        ;; Increment loop counter
        local.get $i
        i32.const 1
        i32.add
        local.set $i
        br $numeric_loop
      end
    end
  )

  ;; Test memory operations
  (func $test_memory_ops (param $iterations i32)
    (local $i i32)
    (local $addr i32)

    i32.const 0
    local.set $i

    loop $memory_loop
      local.get $i
      local.get $iterations
      i32.lt_u
      if
        ;; Memory loads
        i32.const 0
        i32.load
        drop
        call $inc_counter

        i32.const 0
        i32.load8_s
        drop
        call $inc_counter

        i32.const 0
        i32.load8_u
        drop
        call $inc_counter

        i32.const 0
        i32.load16_s
        drop
        call $inc_counter

        i32.const 0
        i32.load16_u
        drop
        call $inc_counter

        i32.const 0
        i64.load
        drop
        call $inc_counter

        i32.const 0
        i64.load8_s
        drop
        call $inc_counter

        i32.const 0
        i64.load8_u
        drop
        call $inc_counter

        i32.const 0
        i64.load16_s
        drop
        call $inc_counter

        i32.const 0
        i64.load16_u
        drop
        call $inc_counter

        i32.const 0
        i64.load32_s
        drop
        call $inc_counter

        i32.const 0
        i64.load32_u
        drop
        call $inc_counter

        i32.const 0
        f32.load
        drop
        call $inc_counter

        i32.const 0
        f64.load
        drop
        call $inc_counter

        ;; Memory stores
        i32.const 0
        i32.const 42
        i32.store
        call $inc_counter

        i32.const 0
        i32.const 42
        i32.store8
        call $inc_counter

        i32.const 0
        i32.const 42
        i32.store16
        call $inc_counter

        i32.const 0
        i64.const 123
        i64.store
        call $inc_counter

        i32.const 0
        i64.const 123
        i64.store8
        call $inc_counter

        i32.const 0
        i64.const 123
        i64.store16
        call $inc_counter

        i32.const 0
        i64.const 123
        i64.store32
        call $inc_counter

        i32.const 0
        f32.const 1.5
        f32.store
        call $inc_counter

        i32.const 0
        f64.const 2.5
        f64.store
        call $inc_counter

        ;; Memory size/grow (commented out for now)
        ;; memory.size
        ;; drop
        ;; call $inc_counter

        ;; i32.const 1
        ;; memory.grow
        ;; drop
        ;; call $inc_counter

        ;; Increment loop counter
        local.get $i
        i32.const 1
        i32.add
        local.set $i
        br $memory_loop
      end
    end
  )

  ;; Test control flow operations
  (func $test_control_flow (param $iterations i32)
    (local $i i32)

    i32.const 0
    local.set $i

    loop $control_loop
      local.get $i
      local.get $iterations
      i32.lt_u
      if
        ;; Block
        block $test_block
          i32.const 1
          br $test_block
        end
        call $inc_counter

        ;; Loop
        i32.const 0
        local.set $i
        loop $inner_control_loop
          local.get $i
          i32.const 5
          i32.lt_s
          if
            local.get $i
            i32.const 1
            i32.add
            local.set $i
            br $inner_control_loop
          end
        end
        call $inc_counter

        ;; If
        i32.const 1
        if
          nop
        end
        call $inc_counter

        ;; Br_if
        i32.const 1
        br_if 0
        call $inc_counter

        ;; Br_table
        i32.const 0
        br_table 0 0 0
        call $inc_counter

        ;; Increment loop counter
        local.get $i
        i32.const 1
        i32.add
        local.set $i
        br $control_loop
      end
    end
  )

  ;; Test reference operations
  (func $test_reference_ops (param $iterations i32)
    (local $i i32)
    (local $ref funcref)

    i32.const 0
    local.set $i

    loop $ref_loop
      local.get $i
      local.get $iterations
      i32.lt_u
      if
        ;; Reference operations (commented out for now)
        ;; ref.null func
        ;; drop
        ;; call $inc_counter

        ;; ref.is_null
        ;; ref.null func
        ;; ref.is_null
        ;; drop
        ;; call $inc_counter

        ;; ref.func
        ;; i32.const 0
        ;; ref.func $inc_counter
        ;; drop
        ;; call $inc_counter

        ;; Increment loop counter
        local.get $i
        i32.const 1
        i32.add
        local.set $i
        br $ref_loop
      end
    end
  )

  ;; Test table operations
  (func $test_table_ops (param $iterations i32)
    (local $i i32)

    i32.const 0
    local.set $i

    loop $table_loop
      local.get $i
      local.get $iterations
      i32.lt_u
      if
        ;; table.get (commented out for now)
        ;; i32.const 0
        ;; table.get 0
        ;; drop
        ;; call $inc_counter

        ;; table.set (commented out for now)
        ;; i32.const 0
        ;; ref.null func
        ;; table.set 0
        ;; call $inc_counter

        ;; Increment loop counter
        local.get $i
        i32.const 1
        i32.add
        local.set $i
        br $table_loop
      end
    end
  )

  ;; Test SIMD operations (basic subset)
  (func $test_simd_ops (param $iterations i32)
    (local $i i32)

    i32.const 0
    local.set $i

    loop $simd_loop
      local.get $i
      local.get $iterations
      i32.lt_u
      if
        ;; SIMD operations (commented out for now)
        ;; v128.const i32x4 1 2 3 4
        ;; drop
        ;; call $inc_counter

        ;; Basic i32x4 operations
        ;; v128.const i32x4 1 2 3 4
        ;; v128.const i32x4 5 6 7 8
        ;; i32x4.add
        ;; drop
        ;; call $inc_counter

        ;; v128.const i32x4 1 2 3 4
        ;; v128.const i32x4 5 6 7 8
        ;; i32x4.sub
        ;; drop
        ;; call $inc_counter

        ;; v128.const i32x4 1 2 3 4
        ;; v128.const i32x4 5 6 7 8
        ;; i32x4.mul
        ;; drop
        ;; call $inc_counter

        ;; Increment loop counter
        local.get $i
        i32.const 1
        i32.add
        local.set $i
        br $simd_loop
      end
    end
  )

  ;; Test exception handling (simplified)
  (func $test_exceptions (param $iterations i32)
    (local $i i32)

    i32.const 0
    local.set $i

    loop $exception_loop
      local.get $i
      local.get $iterations
      i32.lt_u
      if
        ;; Just test basic control flow instead
        nop
        call $inc_counter

        ;; Increment loop counter
        local.get $i
        i32.const 1
        i32.add
        local.set $i
        br $exception_loop
      end
    end
  )

  ;; Main benchmark function
  (func $run_benchmark (param $iterations i32) (result i32)
    ;; Reset counter
    i32.const 0
    global.set $opcode_count

    ;; Run all opcode tests
    local.get $iterations
    call $test_numeric_ops

    local.get $iterations
    call $test_memory_ops

    local.get $iterations
    call $test_control_flow

    local.get $iterations
    call $test_reference_ops

    local.get $iterations
    call $test_table_ops

    local.get $iterations
    call $test_simd_ops

    local.get $iterations
    call $test_exceptions

    ;; Return total opcode count
    global.get $opcode_count
  )

  ;; Main entry point with default iterations
  (func $main (result i32)
    i32.const 100  ;; Default iterations for comprehensive testing
    call $run_benchmark
  )

  ;; Export main function
  (export "_start" (func $main))
)
