(module
  ;; Mixed Type Benchmark - Tests all type operations together
  ;; This benchmark simulates real-world workloads that mix i32, i64, f32, f64
  ;; Specifically designed to test the fast-path optimizations in wart runtime

  (memory 1)

  ;; Vector dot product using f64
  (func $dot_product_f64 (param $n i32) (result f64)
    (local $i i32)
    (local $sum f64)
    (local $a f64)
    (local $b f64)
    
    i32.const 0
    local.set $i
    f64.const 0.0
    local.set $sum
    
    (block $break
      (loop $continue
        local.get $i
        local.get $n
        i32.ge_u
        br_if $break
        
        ;; Generate pseudo-random values
        local.get $i
        f64.convert_i32_s
        f64.const 0.1
        f64.mul
        local.set $a
        
        local.get $i
        i32.const 1
        i32.add
        f64.convert_i32_s
        f64.const 0.1
        f64.mul
        local.set $b
        
        ;; sum += a * b
        local.get $sum
        local.get $a
        local.get $b
        f64.mul
        f64.add
        local.set $sum
        
        local.get $i
        i32.const 1
        i32.add
        local.set $i
        
        br $continue
      )
    )
    
    local.get $sum
  )

  ;; Vector dot product using f32
  (func $dot_product_f32 (param $n i32) (result f32)
    (local $i i32)
    (local $sum f32)
    (local $a f32)
    (local $b f32)
    
    i32.const 0
    local.set $i
    f32.const 0.0
    local.set $sum
    
    (block $break
      (loop $continue
        local.get $i
        local.get $n
        i32.ge_u
        br_if $break
        
        ;; Generate pseudo-random values
        local.get $i
        f32.convert_i32_s
        f32.const 0.1
        f32.mul
        local.set $a
        
        local.get $i
        i32.const 1
        i32.add
        f32.convert_i32_s
        f32.const 0.1
        f32.mul
        local.set $b
        
        ;; sum += a * b
        local.get $sum
        local.get $a
        local.get $b
        f32.mul
        f32.add
        local.set $sum
        
        local.get $i
        i32.const 1
        i32.add
        local.set $i
        
        br $continue
      )
    )
    
    local.get $sum
  )

  ;; Integer hash function using i64
  (func $hash_i64 (param $n i64) (result i64)
    (local $i i64)
    (local $hash i64)
    
    i64.const 0
    local.set $i
    i64.const 5381
    local.set $hash
    
    (block $break
      (loop $continue
        local.get $i
        local.get $n
        i64.ge_u
        br_if $break
        
        ;; hash = ((hash << 5) + hash) + i  (djb2 variant)
        local.get $hash
        i64.const 5
        i64.shl
        local.get $hash
        i64.add
        local.get $i
        i64.add
        local.set $hash
        
        ;; XOR operation
        local.get $hash
        local.get $i
        i64.xor
        local.set $hash
        
        local.get $i
        i64.const 1
        i64.add
        local.set $i
        
        br $continue
      )
    )
    
    local.get $hash
  )

  ;; Integer hash function using i32
  (func $hash_i32 (param $n i32) (result i32)
    (local $i i32)
    (local $hash i32)
    
    i32.const 0
    local.set $i
    i32.const 5381
    local.set $hash
    
    (block $break
      (loop $continue
        local.get $i
        local.get $n
        i32.ge_u
        br_if $break
        
        ;; hash = ((hash << 5) + hash) + i  (djb2 variant)
        local.get $hash
        i32.const 5
        i32.shl
        local.get $hash
        i32.add
        local.get $i
        i32.add
        local.set $hash
        
        ;; XOR operation
        local.get $hash
        local.get $i
        i32.xor
        local.set $hash
        
        local.get $i
        i32.const 1
        i32.add
        local.set $i
        
        br $continue
      )
    )
    
    local.get $hash
  )

  ;; Type conversion stress test
  (func $type_conversion_test (param $n i32) (result f64)
    (local $i i32)
    (local $sum f64)
    (local $i32_val i32)
    (local $i64_val i64)
    (local $f32_val f32)
    (local $f64_val f64)
    
    i32.const 0
    local.set $i
    f64.const 0.0
    local.set $sum
    
    (block $break
      (loop $continue
        local.get $i
        local.get $n
        i32.ge_u
        br_if $break
        
        ;; i32 -> i64
        local.get $i
        i64.extend_i32_s
        local.set $i64_val
        
        ;; i64 -> f64
        local.get $i64_val
        f64.convert_i64_s
        local.set $f64_val
        
        ;; f64 -> f32
        local.get $f64_val
        f32.demote_f64
        local.set $f32_val
        
        ;; f32 -> f64
        local.get $f32_val
        f64.promote_f32
        local.set $f64_val
        
        ;; f64 -> i64
        local.get $f64_val
        i64.trunc_f64_s
        local.set $i64_val
        
        ;; i64 -> i32
        local.get $i64_val
        i32.wrap_i64
        local.set $i32_val
        
        ;; Accumulate
        local.get $sum
        local.get $f64_val
        f64.add
        local.set $sum
        
        local.get $i
        i32.const 1
        i32.add
        local.set $i
        
        br $continue
      )
    )
    
    local.get $sum
  )

  ;; Bitwise operations benchmark (i32 + i64)
  (func $bitwise_benchmark (param $n i32) (result i64)
    (local $i i32)
    (local $result32 i32)
    (local $result64 i64)
    
    i32.const 0
    local.set $i
    i32.const 0xDEADBEEF
    local.set $result32
    i64.const 0xCAFEBABEDEADBEEF
    local.set $result64
    
    (block $break
      (loop $continue
        local.get $i
        local.get $n
        i32.ge_u
        br_if $break
        
        ;; i32 bitwise ops
        local.get $result32
        local.get $i
        i32.and
        local.get $i
        i32.or
        i32.const 3
        i32.shl
        i32.const 2
        i32.shr_u
        local.set $result32
        
        ;; i64 bitwise ops  
        local.get $result64
        local.get $i
        i64.extend_i32_s
        i64.and
        local.get $i
        i64.extend_i32_s
        i64.or
        i64.const 5
        i64.shl
        i64.const 3
        i64.shr_u
        local.set $result64
        
        ;; XOR mix
        local.get $result64
        local.get $result32
        i64.extend_i32_s
        i64.xor
        local.set $result64
        
        local.get $i
        i32.const 1
        i32.add
        local.set $i
        
        br $continue
      )
    )
    
    local.get $result64
  )

  ;; Memory operations benchmark
  (func $memory_benchmark (param $n i32) (result i32)
    (local $i i32)
    (local $sum i32)
    (local $addr i32)
    
    i32.const 0
    local.set $i
    i32.const 0
    local.set $sum
    
    (block $break
      (loop $continue
        local.get $i
        local.get $n
        i32.ge_u
        br_if $break
        
        ;; Calculate address (wrap within memory)
        local.get $i
        i32.const 4
        i32.mul
        i32.const 65532  ;; Max safe 4-byte aligned address
        i32.rem_u
        local.set $addr
        
        ;; i32.store
        local.get $addr
        local.get $i
        i32.store
        
        ;; i32.load
        local.get $addr
        i32.load
        local.get $sum
        i32.add
        local.set $sum
        
        local.get $i
        i32.const 1
        i32.add
        local.set $i
        
        br $continue
      )
    )
    
    local.get $sum
  )

  (func $main (result i32)
    (local $result f64)
    (local $temp64 i64)
    (local $temp32 i32)
    
    ;; Run f64 dot product (100K iterations)
    i32.const 100000
    call $dot_product_f64
    local.set $result
    
    ;; Run f32 dot product (100K iterations)
    i32.const 100000
    call $dot_product_f32
    f64.promote_f32
    local.get $result
    f64.add
    local.set $result
    
    ;; Run i64 hash (100K iterations)
    i64.const 100000
    call $hash_i64
    local.set $temp64
    
    ;; Run i32 hash (100K iterations)
    i32.const 100000
    call $hash_i32
    local.set $temp32
    
    ;; Run type conversion test (100K iterations)
    i32.const 100000
    call $type_conversion_test
    local.get $result
    f64.add
    local.set $result
    
    ;; Run bitwise benchmark (100K iterations)
    i32.const 100000
    call $bitwise_benchmark
    local.get $temp64
    i64.add
    local.set $temp64
    
    ;; Run memory benchmark (50K iterations)
    i32.const 50000
    call $memory_benchmark
    local.get $temp32
    i32.add
    local.set $temp32
    
    ;; Combine results (just return temp32 for simplicity)
    local.get $temp32
  )
  
  (export "_start" (func $main))
)
