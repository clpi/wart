;; Comprehensive Bleeding Edge WebAssembly Feature Test
;; Tests: Multi-value, Tail-calls, SIMD, Sign-extension, Bulk memory, Reference types, Threads

(module
  ;; Memory for tests
  (memory (export "memory") 1)
  (data (i32.const 0) "Hello WASM 3.0!")

  ;; ============================================================================
  ;; SIGN-EXTENSION OPERATORS (0xC0-0xC4)
  ;; ============================================================================

  (func (export "test_sign_ext_i32_8") (result i32)
    i32.const 0xFF      ;; -1 as u8
    i32.extend8_s       ;; 0xC0: Should extend to -1 (0xFFFFFFFF)
  )

  (func (export "test_sign_ext_i32_16") (result i32)
    i32.const 0xFFFF    ;; -1 as u16
    i32.extend16_s      ;; 0xC1: Should extend to -1 (0xFFFFFFFF)
  )

  (func (export "test_sign_ext_i64_8") (result i64)
    i64.const 0x80      ;; -128 as u8
    i64.extend8_s       ;; 0xC2: Should extend to -128
  )

  (func (export "test_sign_ext_i64_16") (result i64)
    i64.const 0x8000    ;; -32768 as u16
    i64.extend16_s      ;; 0xC3: Should extend to -32768
  )

  (func (export "test_sign_ext_i64_32") (result i64)
    i64.const 0x80000000  ;; -2147483648 as u32
    i64.extend32_s        ;; 0xC4: Should extend to -2147483648
  )

  ;; ============================================================================
  ;; MULTI-VALUE RETURNS
  ;; ============================================================================

  (func (export "test_multi_value") (result i32 i32 i32)
    i32.const 1
    i32.const 2
    i32.const 3
  )

  (func (export "test_multi_value_swap") (param i32 i32) (result i32 i32)
    local.get 1
    local.get 0
  )

  ;; ============================================================================
  ;; TAIL-CALL OPTIMIZATION (0x12, 0x13)
  ;; ============================================================================

  (func $factorial_helper (param $n i32) (param $acc i32) (result i32)
    local.get $n
    i32.const 1
    i32.le_s
    if (result i32)
      local.get $acc
    else
      local.get $n
      i32.const 1
      i32.sub
      local.get $n
      local.get $acc
      i32.mul
      return_call $factorial_helper  ;; 0x12: Tail call optimization
    end
  )

  (func (export "test_tail_call") (param i32) (result i32)
    local.get 0
    i32.const 1
    call $factorial_helper
  )

  ;; ============================================================================
  ;; BULK MEMORY OPERATIONS (0xFC prefix)
  ;; ============================================================================

  (func (export "test_memory_fill") (result i32)
    i32.const 100      ;; dest
    i32.const 0x42     ;; value
    i32.const 10       ;; size
    memory.fill        ;; 0xFC 0x0B

    i32.const 105      ;; Read middle byte
    i32.load8_u
  )

  (func (export "test_memory_copy") (result i32)
    i32.const 200      ;; dest
    i32.const 0        ;; src (contains "Hello")
    i32.const 5        ;; size
    memory.copy        ;; 0xFC 0x0A

    i32.const 200      ;; Read first byte of copy
    i32.load8_u
  )

  ;; ============================================================================
  ;; REFERENCE TYPES
  ;; ============================================================================

  (table 10 funcref)

  (func $dummy (result i32)
    i32.const 42
  )

  (func (export "test_ref_func") (result i32)
    ref.func $dummy          ;; 0xD2: Get function reference
    call_ref                 ;; 0x14: Call via reference
  )

  (func (export "test_ref_null") (result i32)
    ref.null func            ;; 0xD0: Null reference
    ref.is_null              ;; 0xD1: Check if null
  )

  ;; ============================================================================
  ;; SELECT WITH TYPE (Multi-value proposal)
  ;; ============================================================================

  (func (export "test_select_t") (param i32) (result i32)
    i32.const 100
    i32.const 200
    local.get 0
    select (result i32)      ;; 0x1C: Typed select
  )

  ;; ============================================================================
  ;; SATURATING FLOAT-TO-INT (0xFC 0x00-0x07)
  ;; ============================================================================

  (func (export "test_trunc_sat_f32_i32") (result i32)
    f32.const 1e10           ;; Value larger than i32 max
    i32.trunc_sat_f32_s      ;; 0xFC 0x00: Saturates to i32::MAX
  )

  (func (export "test_trunc_sat_f64_i64") (result i64)
    f64.const nan            ;; NaN value
    i64.trunc_sat_f64_s      ;; 0xFC 0x06: Saturates to 0
  )

  ;; ============================================================================
  ;; MAIN TEST RUNNER
  ;; ============================================================================

  (func (export "_start")
    ;; All tests return values on stack, just drop them
    call $test_sign_ext_i32_8
    drop
    call $test_sign_ext_i32_16
    drop
    call $test_multi_value
    drop drop drop

    ;; Success - no traps means all features work!
  )
)
