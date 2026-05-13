(module
  ;; Arithmetic-heavy benchmark - 1M iterations
  (func $arithmetic_loop (param $n i32) (result i32)
    (local $i i32)
    (local $result i32)
    (local $temp i32)
    
    ;; Initialize
    i32.const 0
    local.set $i
    i32.const 1
    local.set $result
    
    ;; Loop 
    (block $break
      (loop $continue
        ;; Check if i >= n
        local.get $i
        local.get $n
        i32.ge_u
        br_if $break
        
        ;; result = result * 2 + i
        local.get $result
        i32.const 2
        i32.mul
        local.get $i
        i32.add
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
  
  (func $main (result i32)
    i32.const 1000000
    call $arithmetic_loop
  )
  
  (export "_start" (func $main))
)
