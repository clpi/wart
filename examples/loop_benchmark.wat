(module
  (func (export "_start")
    (local $i i32)
    (local $sum i32)
    
    i32.const 0
    local.set $sum
    i32.const 0
    local.set $i
    
    (loop $loop
      local.get $i
      i32.const 10000
      i32.lt_s
      if
        local.get $sum
        local.get $i
        i32.add
        local.set $sum
        
        local.get $i
        i32.const 1
        i32.add
        local.set $i
        
        br $loop
      end
    )
  )
)
