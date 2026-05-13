(module
  (func (export "_start")
    (local i32 i32)
    
    ;; Initialize counter to 0
    i32.const 0
    local.set 0
    
    block $outer
      loop $loop
        block $inner
          ;; Increment counter
          local.get 0
          i32.const 1
          i32.add
          local.tee 0
          
          ;; Check if counter >= 3
          i32.const 3
          i32.eq
          
          ;; If counter >= 3, break out of outer block (exit loop)
          br_if 2
          
          ;; Otherwise, continue loop by targeting the loop start
          br 1
        end
      end
    end
  )
  (memory 1)
)