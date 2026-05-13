(module
  (func $compute (result i32)
    (local i32 i32)
    loop $loop
      local.get 1
      i32.const 100000
      i32.lt_s
      br_if $loop
      local.get 0
      local.get 1
      local.get 1
      i32.mul
      i32.add
      local.set 0
      local.get 1
      i32.const 1
      i32.add
      local.set 1
    end $loop
    local.get 0
  )
  (export "_start" (func $compute))
)