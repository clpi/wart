(module
  ;; Simple opcode benchmark
  (memory 1)

  ;; Counter
  (global $count (mut i32) (i32.const 0))

  (func $inc
    global.get $count
    i32.const 1
    i32.add
    global.set $count
  )

  (func $benchmark (param $n i32) (result i32)
    (local $i i32)

    loop $loop
      local.get $i
      local.get $n
      i32.lt_u
      if
        ;; Test various opcodes
        i32.const 1
        i32.const 2
        i32.add
        drop
        call $inc

        i32.const 3
        i32.const 4
        i32.mul
        drop
        call $inc

        f32.const 1.5
        f32.const 2.5
        f32.add
        drop
        call $inc

        f64.const 1.1
        f64.const 2.2
        f64.mul
        drop
        call $inc

        ;; Memory ops
        i32.const 0
        i32.const 42
        i32.store
        call $inc

        i32.const 0
        i32.load
        drop
        call $inc

        ;; Control flow
        i32.const 1
        if
          nop
        end
        call $inc

        ;; Increment
        local.get $i
        i32.const 1
        i32.add
        local.set $i
        br $loop
      end
    end

    global.get $count
  )

  (func $main (result i32)
    i32.const 10000
    call $benchmark
  )

  (export "_start" (func $main))
)