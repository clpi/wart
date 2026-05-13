(module
  (func (export "_start")
    (local i32 i32)
    
    ;; Initialize counter to 0
    i32.const 0
    local.set 0
    
    ;; Outer block for the unconditional branch to target
    block $outer
      ;; Inner loop that gets unconditionally branched to
      loop $loop
        ;; Increment counter
        local.get 0
        i32.const 1
        i32.add
        local.tee 0
        i32.const 3
        i32.eq
        
        ;; If counter == 3, break out of outer block
        br_if $outer
        
        ;; Otherwise, unconditionally branch back to loop start
        br $loop
      end
    end
    
    ;; Return
  )
  (memory 1)
)