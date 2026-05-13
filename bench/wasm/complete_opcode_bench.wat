(module
  ;; Memory for testing
  (memory (export "memory") 1)

  ;; Table for call_indirect testing
  (table 10 funcref)
  (elem (i32.const 0) $helper1 $helper2)

  ;; Type declarations for call_indirect
  (type $void_to_i32 (func (result i32)))
  (type $i32_to_i32 (func (param i32) (result i32)))

  ;; Global variables for testing
  (global $g0 (mut i32) (i32.const 0))
  (global $g1 (mut i64) (i64.const 0))
  (global $g2 (mut f32) (f32.const 0))
  (global $g3 (mut f64) (f64.const 0))

  ;; Helper functions for call_indirect
  (func $helper1 (result i32)
    i32.const 42
  )

  (func $helper2 (result i32)
    i32.const 100
  )

  ;; =================================================================
  ;; COMPREHENSIVE OPCODE BENCHMARK - Tests ALL WebAssembly opcodes
  ;; =================================================================
  (func (export "benchmark") (result i32)
    (local $l0 i32) (local $l1 i32) (local $l2 i32)
    (local $l3 i64) (local $l4 i64)
    (local $l5 f32) (local $l6 f32)
    (local $l7 f64) (local $l8 f64)
    (local $iter i32)
    (local $result i32)

    ;; Initialize iteration counter
    i32.const 0
    local.set $iter

    ;; Main benchmark loop (10000 iterations)
    (block $exit
      (loop $continue
        ;; ===== CONTROL FLOW OPCODES =====
        ;; nop
        nop

        ;; br, br_if
        i32.const 0
        br_if 0

        ;; block/end
        (block
          i32.const 1
          drop
        )

        ;; loop/end (already in main loop)

        ;; if/else/end
        i32.const 1
        (if
          (then
            i32.const 42
            drop
          )
          (else
            i32.const 24
            drop
          )
        )

        ;; br_table
        (block $bt0
          (block $bt1
            (block $bt2
              i32.const 0
              br_table $bt2 $bt1 $bt0
            )
          )
        )

        ;; ===== PARAMETRIC OPCODES =====
        ;; drop
        i32.const 999
        drop

        ;; select
        i32.const 10
        i32.const 20
        i32.const 1
        select
        drop

        ;; ===== VARIABLE OPCODES =====
        ;; local.get, local.set, local.tee
        i32.const 123
        local.set $l0
        local.get $l0
        local.tee $l1
        drop

        ;; global.get, global.set
        i32.const 456
        global.set $g0
        global.get $g0
        drop

        ;; ===== MEMORY OPCODES =====
        ;; i32.store, i32.load
        i32.const 0
        i32.const 42
        i32.store
        i32.const 0
        i32.load
        drop

        ;; i32.store8, i32.load8_s, i32.load8_u
        i32.const 4
        i32.const 127
        i32.store8
        i32.const 4
        i32.load8_s
        drop
        i32.const 4
        i32.load8_u
        drop

        ;; i32.store16, i32.load16_s, i32.load16_u
        i32.const 8
        i32.const 32767
        i32.store16
        i32.const 8
        i32.load16_s
        drop
        i32.const 8
        i32.load16_u
        drop

        ;; i64.store, i64.load
        i32.const 16
        i64.const 999999
        i64.store
        i32.const 16
        i64.load
        drop

        ;; i64.store8, i64.load8_s, i64.load8_u
        i32.const 24
        i64.const 255
        i64.store8
        i32.const 24
        i64.load8_s
        drop
        i32.const 24
        i64.load8_u
        drop

        ;; i64.store16, i64.load16_s, i64.load16_u
        i32.const 32
        i64.const 65535
        i64.store16
        i32.const 32
        i64.load16_s
        drop
        i32.const 32
        i64.load16_u
        drop

        ;; i64.store32, i64.load32_s, i64.load32_u
        i32.const 40
        i64.const 4294967295
        i64.store32
        i32.const 40
        i64.load32_s
        drop
        i32.const 40
        i64.load32_u
        drop

        ;; f32.store, f32.load
        i32.const 48
        f32.const 3.14159
        f32.store
        i32.const 48
        f32.load
        drop

        ;; f64.store, f64.load
        i32.const 56
        f64.const 2.71828
        f64.store
        i32.const 56
        f64.load
        drop

        ;; memory.size, memory.grow
        memory.size
        drop

        ;; ===== i32 NUMERIC OPCODES =====
        ;; i32.const (already used above)

        ;; i32.eqz
        i32.const 0
        i32.eqz
        drop

        ;; i32.eq, i32.ne
        i32.const 10
        i32.const 10
        i32.eq
        drop
        i32.const 10
        i32.const 20
        i32.ne
        drop

        ;; i32.lt_s, i32.lt_u, i32.gt_s, i32.gt_u
        i32.const 5
        i32.const 10
        i32.lt_s
        drop
        i32.const 5
        i32.const 10
        i32.lt_u
        drop
        i32.const 15
        i32.const 10
        i32.gt_s
        drop
        i32.const 15
        i32.const 10
        i32.gt_u
        drop

        ;; i32.le_s, i32.le_u, i32.ge_s, i32.ge_u
        i32.const 10
        i32.const 10
        i32.le_s
        drop
        i32.const 10
        i32.const 10
        i32.le_u
        drop
        i32.const 10
        i32.const 10
        i32.ge_s
        drop
        i32.const 10
        i32.const 10
        i32.ge_u
        drop

        ;; i32.clz, i32.ctz, i32.popcnt
        i32.const 0x00FF0000
        i32.clz
        drop
        i32.const 0x00FF0000
        i32.ctz
        drop
        i32.const 0xF0F0F0F0
        i32.popcnt
        drop

        ;; i32.add, i32.sub, i32.mul
        i32.const 100
        i32.const 50
        i32.add
        drop
        i32.const 100
        i32.const 50
        i32.sub
        drop
        i32.const 20
        i32.const 5
        i32.mul
        drop

        ;; i32.div_s, i32.div_u, i32.rem_s, i32.rem_u
        i32.const 100
        i32.const 7
        i32.div_s
        drop
        i32.const 100
        i32.const 7
        i32.div_u
        drop
        i32.const 100
        i32.const 7
        i32.rem_s
        drop
        i32.const 100
        i32.const 7
        i32.rem_u
        drop

        ;; i32.and, i32.or, i32.xor
        i32.const 0xFF00
        i32.const 0x00FF
        i32.and
        drop
        i32.const 0xFF00
        i32.const 0x00FF
        i32.or
        drop
        i32.const 0xFFFF
        i32.const 0xFF00
        i32.xor
        drop

        ;; i32.shl, i32.shr_s, i32.shr_u
        i32.const 1
        i32.const 8
        i32.shl
        drop
        i32.const 256
        i32.const 2
        i32.shr_s
        drop
        i32.const 256
        i32.const 2
        i32.shr_u
        drop

        ;; i32.rotl, i32.rotr
        i32.const 0x12345678
        i32.const 8
        i32.rotl
        drop
        i32.const 0x12345678
        i32.const 8
        i32.rotr
        drop

        ;; ===== i64 NUMERIC OPCODES =====
        ;; i64.const
        i64.const 9223372036854775807
        drop

        ;; i64.eqz
        i64.const 0
        i64.eqz
        drop

        ;; i64.eq, i64.ne
        i64.const 1000
        i64.const 1000
        i64.eq
        drop
        i64.const 1000
        i64.const 2000
        i64.ne
        drop

        ;; i64.lt_s, i64.lt_u, i64.gt_s, i64.gt_u
        i64.const 500
        i64.const 1000
        i64.lt_s
        drop
        i64.const 500
        i64.const 1000
        i64.lt_u
        drop
        i64.const 1500
        i64.const 1000
        i64.gt_s
        drop
        i64.const 1500
        i64.const 1000
        i64.gt_u
        drop

        ;; i64.le_s, i64.le_u, i64.ge_s, i64.ge_u
        i64.const 1000
        i64.const 1000
        i64.le_s
        drop
        i64.const 1000
        i64.const 1000
        i64.le_u
        drop
        i64.const 1000
        i64.const 1000
        i64.ge_s
        drop
        i64.const 1000
        i64.const 1000
        i64.ge_u
        drop

        ;; i64.clz, i64.ctz, i64.popcnt
        i64.const 0x00FF000000000000
        i64.clz
        drop
        i64.const 0x00FF000000000000
        i64.ctz
        drop
        i64.const 0xF0F0F0F0F0F0F0F0
        i64.popcnt
        drop

        ;; i64.add, i64.sub, i64.mul
        i64.const 10000
        i64.const 5000
        i64.add
        drop
        i64.const 10000
        i64.const 5000
        i64.sub
        drop
        i64.const 200
        i64.const 50
        i64.mul
        drop

        ;; i64.div_s, i64.div_u, i64.rem_s, i64.rem_u
        i64.const 10000
        i64.const 70
        i64.div_s
        drop
        i64.const 10000
        i64.const 70
        i64.div_u
        drop
        i64.const 10000
        i64.const 70
        i64.rem_s
        drop
        i64.const 10000
        i64.const 70
        i64.rem_u
        drop

        ;; i64.and, i64.or, i64.xor
        i64.const 0xFFFF0000FFFF0000
        i64.const 0x0000FFFF0000FFFF
        i64.and
        drop
        i64.const 0xFFFF000000000000
        i64.const 0x0000FFFF00000000
        i64.or
        drop
        i64.const 0xFFFFFFFFFFFFFFFF
        i64.const 0xFFFF0000FFFF0000
        i64.xor
        drop

        ;; i64.shl, i64.shr_s, i64.shr_u
        i64.const 1
        i64.const 32
        i64.shl
        drop
        i64.const 4294967296
        i64.const 16
        i64.shr_s
        drop
        i64.const 4294967296
        i64.const 16
        i64.shr_u
        drop

        ;; i64.rotl, i64.rotr
        i64.const 0x123456789ABCDEF0
        i64.const 16
        i64.rotl
        drop
        i64.const 0x123456789ABCDEF0
        i64.const 16
        i64.rotr
        drop

        ;; ===== f32 NUMERIC OPCODES =====
        ;; f32.const
        f32.const 3.14159265
        drop

        ;; f32.eq, f32.ne, f32.lt, f32.gt, f32.le, f32.ge
        f32.const 1.5
        f32.const 1.5
        f32.eq
        drop
        f32.const 1.5
        f32.const 2.5
        f32.ne
        drop
        f32.const 1.5
        f32.const 2.5
        f32.lt
        drop
        f32.const 2.5
        f32.const 1.5
        f32.gt
        drop
        f32.const 1.5
        f32.const 1.5
        f32.le
        drop
        f32.const 1.5
        f32.const 1.5
        f32.ge
        drop

        ;; f32.abs, f32.neg, f32.ceil, f32.floor, f32.trunc, f32.nearest
        f32.const -3.7
        f32.abs
        drop
        f32.const 3.7
        f32.neg
        drop
        f32.const 3.3
        f32.ceil
        drop
        f32.const 3.7
        f32.floor
        drop
        f32.const 3.7
        f32.trunc
        drop
        f32.const 3.5
        f32.nearest
        drop

        ;; f32.sqrt
        f32.const 16.0
        f32.sqrt
        drop

        ;; f32.add, f32.sub, f32.mul, f32.div
        f32.const 10.5
        f32.const 5.25
        f32.add
        drop
        f32.const 10.5
        f32.const 5.25
        f32.sub
        drop
        f32.const 10.5
        f32.const 2.0
        f32.mul
        drop
        f32.const 10.5
        f32.const 2.0
        f32.div
        drop

        ;; f32.min, f32.max, f32.copysign
        f32.const 3.5
        f32.const 7.2
        f32.min
        drop
        f32.const 3.5
        f32.const 7.2
        f32.max
        drop
        f32.const 3.5
        f32.const -1.0
        f32.copysign
        drop

        ;; ===== f64 NUMERIC OPCODES =====
        ;; f64.const
        f64.const 2.718281828459045
        drop

        ;; f64.eq, f64.ne, f64.lt, f64.gt, f64.le, f64.ge
        f64.const 1.5
        f64.const 1.5
        f64.eq
        drop
        f64.const 1.5
        f64.const 2.5
        f64.ne
        drop
        f64.const 1.5
        f64.const 2.5
        f64.lt
        drop
        f64.const 2.5
        f64.const 1.5
        f64.gt
        drop
        f64.const 1.5
        f64.const 1.5
        f64.le
        drop
        f64.const 1.5
        f64.const 1.5
        f64.ge
        drop

        ;; f64.abs, f64.neg, f64.ceil, f64.floor, f64.trunc, f64.nearest
        f64.const -3.7
        f64.abs
        drop
        f64.const 3.7
        f64.neg
        drop
        f64.const 3.3
        f64.ceil
        drop
        f64.const 3.7
        f64.floor
        drop
        f64.const 3.7
        f64.trunc
        drop
        f64.const 3.5
        f64.nearest
        drop

        ;; f64.sqrt
        f64.const 256.0
        f64.sqrt
        drop

        ;; f64.add, f64.sub, f64.mul, f64.div
        f64.const 10.5
        f64.const 5.25
        f64.add
        drop
        f64.const 10.5
        f64.const 5.25
        f64.sub
        drop
        f64.const 10.5
        f64.const 2.0
        f64.mul
        drop
        f64.const 10.5
        f64.const 2.0
        f64.div
        drop

        ;; f64.min, f64.max, f64.copysign
        f64.const 3.5
        f64.const 7.2
        f64.min
        drop
        f64.const 3.5
        f64.const 7.2
        f64.max
        drop
        f64.const 3.5
        f64.const -1.0
        f64.copysign
        drop

        ;; ===== CONVERSION OPCODES =====
        ;; i32 conversions
        i64.const 9999999999
        i32.wrap_i64
        drop
        f32.const 42.7
        i32.trunc_f32_s
        drop
        f32.const 42.7
        i32.trunc_f32_u
        drop
        f64.const 42.7
        i32.trunc_f64_s
        drop
        f64.const 42.7
        i32.trunc_f64_u
        drop

        ;; i64 conversions
        i32.const 42
        i64.extend_i32_s
        drop
        i32.const 42
        i64.extend_i32_u
        drop
        f32.const 42.7
        i64.trunc_f32_s
        drop
        f32.const 42.7
        i64.trunc_f32_u
        drop
        f64.const 42.7
        i64.trunc_f64_s
        drop
        f64.const 42.7
        i64.trunc_f64_u
        drop

        ;; f32 conversions
        i32.const 42
        f32.convert_i32_s
        drop
        i32.const 42
        f32.convert_i32_u
        drop
        i64.const 9999999
        f32.convert_i64_s
        drop
        i64.const 9999999
        f32.convert_i64_u
        drop
        f64.const 3.14159265359
        f32.demote_f64
        drop

        ;; f64 conversions
        i32.const 42
        f64.convert_i32_s
        drop
        i32.const 42
        f64.convert_i32_u
        drop
        i64.const 9999999
        f64.convert_i64_s
        drop
        i64.const 9999999
        f64.convert_i64_u
        drop
        f32.const 3.14159
        f64.promote_f32
        drop

        ;; Reinterpretation
        i32.const 0x3F800000  ;; bit pattern for 1.0f
        f32.reinterpret_i32
        drop
        f32.const 1.0
        i32.reinterpret_f32
        drop
        i64.const 0x3FF0000000000000  ;; bit pattern for 1.0
        f64.reinterpret_i64
        drop
        f64.const 1.0
        i64.reinterpret_f64
        drop

        ;; ===== CALL OPCODES =====
        ;; call
        call $helper1
        drop

        ;; call_indirect
        i32.const 0
        call_indirect (type $void_to_i32)
        drop

        ;; ===== INCREMENT ITERATION COUNTER =====
        local.get $iter
        i32.const 1
        i32.add
        local.tee $iter

        ;; Check if we've done 10000 iterations
        i32.const 10000
        i32.lt_u
        if
          br $continue
        end
      )
    )

    ;; Return success
    i32.const 0
  )
)
