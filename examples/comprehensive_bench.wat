(module
  ;; Comprehensive benchmark with multiple features
  (memory 1)
  (global $counter (mut i32) (i32.const 0))
  
  (func $complex_computation (param $n i32) (result i32)
    (local $result i32)
    (local $i i32)
    (local $temp i32)
    
    i32.const 1
    local.set $result
    i32.const 0
    local.set $i
    
    (block $break
      (loop $continue
        local.get $i
        local.get $n
        i32.ge_u
        br_if $break
        
        ;; Complex arithmetic
        local.get $result
        i32.const 3
        i32.mul
        local.get $i
        i32.const 2
        i32.mul
        i32.add
        i32.const 7
        i32.rem_u
        local.set $temp
        
        ;; Conditional logic
        local.get $temp
        i32.const 3
        i32.gt_u
        if
          local.get $result
          local.get $temp
          i32.add
          local.set $result
        else
          local.get $result
          local.get $temp
          i32.sub
          local.set $result
        end
        
        ;; Memory operations
        i32.const 0
        local.get $result
        i32.store
        
        i32.const 0
        i32.load
        local.set $result
        
        ;; Update counter
        global.get $counter
        i32.const 1
        i32.add
        global.set $counter
        
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
    i32.const 1000
    call $complex_computation
  )
  
  (export "_start" (func $main))
)
