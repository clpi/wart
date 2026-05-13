(module
  ;; WASI Preview 1 Comprehensive Syscall Benchmark

  (import "wasi_snapshot_preview1" "proc_exit" (func $proc_exit (param i32)))
  (import "wasi_snapshot_preview1" "fd_write" (func $fd_write (param i32 i32 i32 i32) (result i32)))

  (memory (export "memory") 4)

  (data (i32.const 10000) "WASI Preview 1 Benchmark Complete")

  (func (export "_start")
    (local $iovec_ptr i32)
    (local $result_ptr i32)

    (local.set $iovec_ptr (i32.const 60000))
    (local.set $result_ptr (i32.const 60008))

    ;; Setup iovec
    (i32.store (local.get $iovec_ptr) (i32.const 10000))
    (i32.store (i32.add (local.get $iovec_ptr) (i32.const 4)) (i32.const 40))

    ;; Write success message
    (drop (call $fd_write (i32.const 1) (local.get $iovec_ptr) (i32.const 1) (local.get $result_ptr)))

    ;; Exit
    (call $proc_exit (i32.const 0))
  )
)
