(module
  ;; Simple benchmark with function calls
  (func $factorial (param $n i32) (result i32)
    (local $result i32)
    (local $i i32)
    
    i32.const 1
    local.set $result
    i32.const 1
    local.set $i
    
    (block $break
      (loop $continue
        local.get $i
        local.get $n
        i32.gt_u
        br_if $break
        
        local.get $result
        local.get $i
        i32.mul
        local.set $result
        
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
    (local $sum i32)
    (local $i i32)
    
    i32.const 0
    local.set $sum
    i32.const 1
    local.set $i
    
    ;; Call factorial multiple times
    (block $break
      (loop $continue
        local.get $i
        i32.const 10
        i32.gt_u
        br_if $break
        
        local.get $sum
        local.get $i
        call $factorial
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
  
  (export "_start" (func $main))
)
