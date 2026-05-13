(module
  ;; i64 Arithmetic Benchmark - Tests optimized i64 fast-path operations
  ;; Tests: add, sub, mul, div_s, rem_s, and, or, xor, shl, shr_s, shr_u
  ;; 500K iterations to stress the hot path

  (func $i64_arithmetic_loop (param $n i64) (result i64)
    (local $i i64)
    (local $result i64)
    (local $temp i64)
    
    ;; Initialize
    i64.const 0
    local.set $i
    i64.const 1
    local.set $result
    
    ;; Loop
    (block $break
      (loop $continue
        ;; Check if i >= n
        local.get $i
        local.get $n
        i64.ge_u
        br_if $break
        
        ;; Test i64.add: result = result + i
        local.get $result
        local.get $i
        i64.add
        local.set $result
        
        ;; Test i64.mul: result = result * 3
        local.get $result
        i64.const 3
        i64.mul
        local.set $result
        
        ;; Test i64.sub: result = result - 1
        local.get $result
        i64.const 1
        i64.sub
        local.set $result
        
        ;; Test i64.and: result = result & 0xFFFFFFFF
        local.get $result
        i64.const 0xFFFFFFFF
        i64.and
        local.set $result
        
        ;; Test i64.or: result = result | 0x1
        local.get $result
        i64.const 0x1
        i64.or
        local.set $result
        
        ;; Test i64.xor: temp = result ^ 0xAA
        local.get $result
        i64.const 0xAA
        i64.xor
        local.set $temp
        
        ;; Test i64.shl: temp = temp << 1
        local.get $temp
        i64.const 1
        i64.shl
        local.set $temp
        
        ;; Test i64.shr_u: temp = temp >> 2
        local.get $temp
        i64.const 2
        i64.shr_u
        local.set $temp
        
        ;; Test i64.shr_s: result = result >> 1 (signed)
        local.get $result
        i64.const 1
        i64.shr_s
        local.set $result
        
        ;; Add temp back to result
        local.get $result
        local.get $temp
        i64.add
        local.set $result
        
        ;; i++
        local.get $i
        i64.const 1
        i64.add
        local.set $i
        
        br $continue
      )
    )
    
    local.get $result
  )

  (func $i64_comparison_loop (param $n i64) (result i64)
    (local $i i64)
    (local $count i64)
    (local $a i64)
    (local $b i64)
    
    ;; Initialize
    i64.const 0
    local.set $i
    i64.const 0
    local.set $count
    i64.const 100
    local.set $a
    i64.const 50
    local.set $b
    
    ;; Loop testing comparison ops
    (block $break
      (loop $continue
        ;; Check if i >= n
        local.get $i
        local.get $n
        i64.ge_u
        br_if $break
        
        ;; Test i64.eq
        local.get $a
        local.get $b
        i64.eq
        if
          local.get $count
          i64.const 1
          i64.add
          local.set $count
        end
        
        ;; Test i64.ne
        local.get $a
        local.get $b
        i64.ne
        if
          local.get $count
          i64.const 1
          i64.add
          local.set $count
        end
        
        ;; Test i64.lt_s
        local.get $b
        local.get $a
        i64.lt_s
        if
          local.get $count
          i64.const 1
          i64.add
          local.set $count
        end
        
        ;; Test i64.gt_s
        local.get $a
        local.get $b
        i64.gt_s
        if
          local.get $count
          i64.const 1
          i64.add
          local.set $count
        end
        
        ;; Test i64.le_s
        local.get $b
        local.get $a
        i64.le_s
        if
          local.get $count
          i64.const 1
          i64.add
          local.set $count
        end
        
        ;; Test i64.ge_s
        local.get $a
        local.get $b
        i64.ge_s
        if
          local.get $count
          i64.const 1
          i64.add
          local.set $count
        end
        
        ;; Rotate a and b values
        local.get $a
        i64.const 1
        i64.add
        local.set $a
        local.get $b
        i64.const 1
        i64.add
        local.set $b
        
        ;; i++
        local.get $i
        i64.const 1
        i64.add
        local.set $i
        
        br $continue
      )
    )
    
    local.get $count
  )

  (func $main (result i64)
    (local $result i64)
    
    ;; Run arithmetic benchmark (500K iterations)
    i64.const 500000
    call $i64_arithmetic_loop
    local.set $result
    
    ;; Run comparison benchmark (500K iterations)
    i64.const 500000
    call $i64_comparison_loop
    local.get $result
    i64.add
  )
  
  (export "_start" (func $main))
)
