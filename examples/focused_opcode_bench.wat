(module
  ;; Focused benchmark testing implemented opcodes in wart
  (memory 1)
  (table 1 funcref)
  (elem (i32.const 0) $inc_counter)

  ;; Global counters for benchmarking
  (global $opcode_count (mut i32) (i32.const 0))

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
        i64.mul
        drop
        call $inc_counter

        ;; Conversions including new extend8_s and extend16_s
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
    
    i32.const 0
    local.set $i

    loop $memory_loop
      local.get $i
      local.get $iterations
      i32.lt_u
      if
        i32.const 42
        i32.const 0
        i32.store
        call $inc_counter

        i32.const 0
        i32.load
        drop
        call $inc_counter

        local.get $i
        i32.const 1
        i32.add
        local.set $i
        br $memory_loop
      end
    end
  )

  ;; Test control flow
  (func $test_control_flow (param $iterations i32)
    (local $i i32)
    
    i32.const 0
    local.set $i

    loop $control_loop
      local.get $i
      local.get $iterations
      i32.lt_u
      if
        ;; Simple block
        block
          i32.const 1
          drop
          call $inc_counter
        end

        ;; Simple loop
        loop
          call $inc_counter
          br 1  ;; break from loop
        end

        local.get $i
        i32.const 1
        i32.add
        local.set $i
        br $control_loop
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

    ;; Return total opcode count
    global.get $opcode_count
  )

  ;; Main entry point with reasonable iterations
  (func $main (result i32)
    i32.const 1000  ;; 1000 iterations for good benchmarking
    call $run_benchmark
  )

  ;; Export main function
  (export "_start" (func $main))
)
