(module
  ;; f64 Floating-Point Benchmark - Tests optimized f64 fast-path operations
  ;; Tests: add, sub, mul, div, min, max, abs, neg, sqrt, ceil, floor, trunc, nearest
  ;; 500K iterations to stress the hot path

  (func $f64_arithmetic_loop (param $n i32) (result f64)
    (local $i i32)
    (local $result f64)
    (local $temp f64)
    (local $delta f64)
    
    ;; Initialize
    i32.const 0
    local.set $i
    f64.const 1.0
    local.set $result
    f64.const 0.0001
    local.set $delta
    
    ;; Loop
    (block $break
      (loop $continue
        ;; Check if i >= n
        local.get $i
        local.get $n
        i32.ge_u
        br_if $break
        
        ;; Test f64.add: result = result + delta
        local.get $result
        local.get $delta
        f64.add
        local.set $result
        
        ;; Test f64.mul: result = result * 1.0001
        local.get $result
        f64.const 1.0001
        f64.mul
        local.set $result
        
        ;; Test f64.sub: result = result - 0.00001
        local.get $result
        f64.const 0.00001
        f64.sub
        local.set $result
        
        ;; Test f64.div: temp = result / 1.00001
        local.get $result
        f64.const 1.00001
        f64.div
        local.set $temp
        
        ;; Test f64.min: result = min(result, 1e15)
        local.get $result
        f64.const 1000000000000000.0
        f64.min
        local.set $result
        
        ;; Test f64.max: result = max(result, 0.0)
        local.get $result
        f64.const 0.0
        f64.max
        local.set $result
        
        ;; Test f64.abs: temp = abs(temp)
        local.get $temp
        f64.abs
        local.set $temp
        
        ;; Add temp contribution (small to prevent overflow)
        local.get $result
        local.get $temp
        f64.const 0.0001
        f64.mul
        f64.add
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

  (func $f64_math_loop (param $n i32) (result f64)
    (local $i i32)
    (local $result f64)
    (local $value f64)
    
    ;; Initialize
    i32.const 0
    local.set $i
    f64.const 0.0
    local.set $result
    f64.const 2.718281828459045
    local.set $value
    
    ;; Loop testing math operations
    (block $break
      (loop $continue
        ;; Check if i >= n
        local.get $i
        local.get $n
        i32.ge_u
        br_if $break
        
        ;; Test f64.sqrt
        local.get $value
        f64.sqrt
        local.get $result
        f64.add
        local.set $result
        
        ;; Test f64.ceil
        local.get $value
        f64.ceil
        local.get $result
        f64.add
        local.set $result
        
        ;; Test f64.floor
        local.get $value
        f64.floor
        local.get $result
        f64.add
        local.set $result
        
        ;; Test f64.trunc
        local.get $value
        f64.trunc
        local.get $result
        f64.add
        local.set $result
        
        ;; Test f64.nearest
        local.get $value
        f64.nearest
        local.get $result
        f64.add
        local.set $result
        
        ;; Test f64.neg
        local.get $value
        f64.neg
        f64.abs
        local.get $result
        f64.add
        local.set $result
        
        ;; Update value
        local.get $value
        f64.const 0.001
        f64.add
        local.set $value
        
        ;; Keep value in reasonable range
        local.get $value
        f64.const 1000.0
        f64.gt
        if
          f64.const 2.718281828459045
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

  (func $f64_comparison_loop (param $n i32) (result f64)
    (local $i i32)
    (local $count f64)
    (local $a f64)
    (local $b f64)
    
    ;; Initialize
    i32.const 0
    local.set $i
    f64.const 0.0
    local.set $count
    f64.const 3.141592653589793
    local.set $a
    f64.const 2.718281828459045
    local.set $b
    
    ;; Loop testing comparison ops
    (block $break
      (loop $continue
        ;; Check if i >= n
        local.get $i
        local.get $n
        i32.ge_u
        br_if $break
        
        ;; Test f64.eq
        local.get $a
        local.get $b
        f64.eq
        if
          local.get $count
          f64.const 1.0
          f64.add
          local.set $count
        end
        
        ;; Test f64.ne
        local.get $a
        local.get $b
        f64.ne
        if
          local.get $count
          f64.const 1.0
          f64.add
          local.set $count
        end
        
        ;; Test f64.lt
        local.get $b
        local.get $a
        f64.lt
        if
          local.get $count
          f64.const 1.0
          f64.add
          local.set $count
        end
        
        ;; Test f64.gt
        local.get $a
        local.get $b
        f64.gt
        if
          local.get $count
          f64.const 1.0
          f64.add
          local.set $count
        end
        
        ;; Test f64.le
        local.get $b
        local.get $a
        f64.le
        if
          local.get $count
          f64.const 1.0
          f64.add
          local.set $count
        end
        
        ;; Test f64.ge
        local.get $a
        local.get $b
        f64.ge
        if
          local.get $count
          f64.const 1.0
          f64.add
          local.set $count
        end
        
        ;; Update a and b
        local.get $a
        f64.const 0.0001
        f64.add
        local.set $a
        local.get $b
        f64.const 0.0001
        f64.add
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

  (func $f64_precision_test (param $n i32) (result f64)
    (local $i i32)
    (local $sum f64)
    (local $pi f64)
    (local $term f64)
    
    ;; Calculate approximation of pi using Leibniz formula
    ;; pi/4 = 1 - 1/3 + 1/5 - 1/7 + ...
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
        
        ;; term = 1.0 / (2*i + 1)
        local.get $i
        i32.const 2
        i32.mul
        i32.const 1
        i32.add
        f64.convert_i32_s
        f64.const 1.0
        f64.div
        local.set $term
        
        ;; Alternate sign
        local.get $i
        i32.const 2
        i32.rem_u
        i32.const 0
        i32.eq
        if
          ;; Even: add term
          local.get $sum
          local.get $term
          f64.add
          local.set $sum
        else
          ;; Odd: subtract term
          local.get $sum
          local.get $term
          f64.sub
          local.set $sum
        end
        
        local.get $i
        i32.const 1
        i32.add
        local.set $i
        
        br $continue
      )
    )
    
    ;; pi = 4 * sum
    local.get $sum
    f64.const 4.0
    f64.mul
  )

  (func $main (result f64)
    (local $result f64)
    
    ;; Run arithmetic benchmark (500K iterations)
    i32.const 500000
    call $f64_arithmetic_loop
    local.set $result
    
    ;; Run math benchmark (100K iterations)
    i32.const 100000
    call $f64_math_loop
    local.get $result
    f64.add
    local.set $result
    
    ;; Run comparison benchmark (500K iterations)
    i32.const 500000
    call $f64_comparison_loop
    local.get $result
    f64.add
    local.set $result
    
    ;; Run precision test (10K iterations)
    i32.const 10000
    call $f64_precision_test
    local.get $result
    f64.add
  )
  
  (export "_start" (func $main))
)
