(module
  ;; Compute benchmark with multiple operations
  (func $fibonacci (param $n i32) (result i32)
    (local $a i32)
    (local $b i32)
    (local $temp i32)
    (local $i i32)
    
    ;; Base cases
    local.get $n
    i32.const 2
    i32.lt_u
    if
      local.get $n
      return
    end
    
    ;; Initialize
    i32.const 0
    local.set $a
    i32.const 1
    local.set $b
    i32.const 2
    local.set $i
    
    ;; Loop
    (block $break
      (loop $continue
        local.get $i
        local.get $n
        i32.gt_u
        br_if $break
        
        ;; temp = a + b
        local.get $a
        local.get $b
        i32.add
        local.set $temp
        
        ;; a = b
        local.get $b
        local.set $a
        
        ;; b = temp
        local.get $temp
        local.set $b
        
        ;; i++
        local.get $i
        i32.const 1
        i32.add
        local.set $i
        
        br $continue
      )
    )
    
    local.get $b
  )
  
  (func $main (result i32)
    i32.const 30
    call $fibonacci
  )
  
  (export "_start" (func $main))
)
