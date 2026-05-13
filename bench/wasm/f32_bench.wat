(module
  ;; f32 Floating-Point Benchmark - Tests optimized f32 fast-path operations
  ;; Tests: add, sub, mul, div, min, max, abs, neg, sqrt, ceil, floor, trunc, nearest
  ;; 500K iterations to stress the hot path

  (func $f32_arithmetic_loop (param $n i32) (result f32)
    (local $i i32)
    (local $result f32)
    (local $temp f32)
    (local $delta f32)
    
    ;; Initialize
    i32.const 0
    local.set $i
    f32.const 1.0
    local.set $result
    f32.const 0.001
    local.set $delta
    
    ;; Loop
    (block $break
      (loop $continue
        ;; Check if i >= n
        local.get $i
        local.get $n
        i32.ge_u
        br_if $break
        
        ;; Test f32.add: result = result + delta
        local.get $result
        local.get $delta
        f32.add
        local.set $result
        
        ;; Test f32.mul: result = result * 1.001
        local.get $result
        f32.const 1.001
        f32.mul
        local.set $result
        
        ;; Test f32.sub: result = result - 0.0001
        local.get $result
        f32.const 0.0001
        f32.sub
        local.set $result
        
        ;; Test f32.div: temp = result / 1.0001
        local.get $result
        f32.const 1.0001
        f32.div
        local.set $temp
        
        ;; Test f32.min: result = min(result, 1000000.0)
        local.get $result
        f32.const 1000000.0
        f32.min
        local.set $result
        
        ;; Test f32.max: result = max(result, 0.0)
        local.get $result
        f32.const 0.0
        f32.max
        local.set $result
        
        ;; Test f32.abs: temp = abs(temp)
        local.get $temp
        f32.abs
        local.set $temp
        
        ;; Add temp contribution
        local.get $result
        local.get $temp
        f32.const 0.001
        f32.mul
        f32.add
        local.set $result
        
        ;; i++
        local.get $i
        i32.const 1
        i32.add
        local.set $i
        
        br $continue
      )
    )
    
    local.get $result
  )

  (func $f32_math_loop (param $n i32) (result f32)
    (local $i i32)
    (local $result f32)
    (local $value f32)
    
    ;; Initialize
    i32.const 0
    local.set $i
    f32.const 0.0
    local.set $result
    f32.const 1.5
    local.set $value
    
    ;; Loop testing math operations
    (block $break
      (loop $continue
        ;; Check if i >= n
        local.get $i
        local.get $n
        i32.ge_u
        br_if $break
        
        ;; Test f32.sqrt
        local.get $value
        f32.sqrt
        local.get $result
        f32.add
        local.set $result
        
        ;; Test f32.ceil
        local.get $value
        f32.ceil
        local.get $result
        f32.add
        local.set $result
        
        ;; Test f32.floor
        local.get $value
        f32.floor
        local.get $result
        f32.add
        local.set $result
        
        ;; Test f32.trunc
        local.get $value
        f32.trunc
        local.get $result
        f32.add
        local.set $result
        
        ;; Test f32.nearest
        local.get $value
        f32.nearest
        local.get $result
        f32.add
        local.set $result
        
        ;; Test f32.neg
        local.get $value
        f32.neg
        f32.abs
        local.get $result
        f32.add
        local.set $result
        
        ;; Update value
        local.get $value
        f32.const 0.01
        f32.add
        local.set $value
        
        ;; Keep value in reasonable range
        local.get $value
        f32.const 100.0
        f32.gt
        if
          f32.const 1.5
          local.set $value
        end
        
        ;; i++
        local.get $i
        i32.const 1
        i32.add
        local.set $i
        
        br $continue
      )
    )
    
    local.get $result
  )

  (func $f32_comparison_loop (param $n i32) (result f32)
    (local $i i32)
    (local $count f32)
    (local $a f32)
    (local $b f32)
    
    ;; Initialize
    i32.const 0
    local.set $i
    f32.const 0.0
    local.set $count
    f32.const 3.14159
    local.set $a
    f32.const 2.71828
    local.set $b
    
    ;; Loop testing comparison ops
    (block $break
      (loop $continue
        ;; Check if i >= n
        local.get $i
        local.get $n
        i32.ge_u
        br_if $break
        
        ;; Test f32.eq
        local.get $a
        local.get $b
        f32.eq
        if
          local.get $count
          f32.const 1.0
          f32.add
          local.set $count
        end
        
        ;; Test f32.ne
        local.get $a
        local.get $b
        f32.ne
        if
          local.get $count
          f32.const 1.0
          f32.add
          local.set $count
        end
        
        ;; Test f32.lt
        local.get $b
        local.get $a
        f32.lt
        if
          local.get $count
          f32.const 1.0
          f32.add
          local.set $count
        end
        
        ;; Test f32.gt
        local.get $a
        local.get $b
        f32.gt
        if
          local.get $count
          f32.const 1.0
          f32.add
          local.set $count
        end
        
        ;; Test f32.le
        local.get $b
        local.get $a
        f32.le
        if
          local.get $count
          f32.const 1.0
          f32.add
          local.set $count
        end
        
        ;; Test f32.ge
        local.get $a
        local.get $b
        f32.ge
        if
          local.get $count
          f32.const 1.0
          f32.add
          local.set $count
        end
        
        ;; Update a and b
        local.get $a
        f32.const 0.001
        f32.add
        local.set $a
        local.get $b
        f32.const 0.001
        f32.add
        local.set $b
        
        ;; i++
        local.get $i
        i32.const 1
        i32.add
        local.set $i
        
        br $continue
      )
    )
    
    local.get $count
  )

  (func $main (result f32)
    (local $result f32)
    
    ;; Run arithmetic benchmark (500K iterations)
    i32.const 500000
    call $f32_arithmetic_loop
    local.set $result
    
    ;; Run math benchmark (100K iterations)
    i32.const 100000
    call $f32_math_loop
    local.get $result
    f32.add
    local.set $result
    
    ;; Run comparison benchmark (500K iterations)
    i32.const 500000
    call $f32_comparison_loop
    local.get $result
    f32.add
  )
  
  (export "_start" (func $main))
)
