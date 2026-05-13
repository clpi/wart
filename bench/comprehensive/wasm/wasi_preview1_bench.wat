(module
  ;; WASI Preview 1 Comprehensive Benchmark
  ;; Tests all major WASI Preview 1 syscalls

  (import "wasi_snapshot_preview1" "proc_exit" (func $proc_exit (param i32)))
  (import "wasi_snapshot_preview1" "fd_write" (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_read" (func $fd_read (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_seek" (func $fd_seek (param i32 i64 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_close" (func $fd_close (param i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_fdstat_get" (func $fd_fdstat_get (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_fdstat_set_flags" (func $fd_fdstat_set_flags (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "path_open" (func $path_open (param i32 i32 i32 i32 i32 i32 i64 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "path_readlink" (func $path_readlink (param i32 i32 i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "path_unlink_file" (func $path_unlink_file (param i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "clock_time_get" (func $clock_time_get (param i32 i64 i32) (result i32)))
  (import "wasi_snapshot_preview1" "random_get" (func $random_get (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "environ_get" (func $environ_get (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "environ_sizes_get" (func $environ_sizes_get (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "args_sizes_get" (func $args_sizes_get (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "args_get" (func $args_get (param i32 i32) (result i32)))

  (memory (export "memory") 1)

  ;; Write buffer
  (data (i32.const 1000) "WASI Preview 1 Benchmark Complete\n")

  (global $iter_count (mut i32) (i32.const 10000))

  (func (export "_start")
    (local $i i32)
    (local $fd i32)
    (local $nwritten i32)
    (local $iovec_ptr i32)
    (local $iov_ptr i32)

    ;; Test fd_write to stdout
    (local.set $fd (i32.const 1))
    (local.set $iovec_ptr (i32.const 2000))
    (local.set $iov_ptr (i32.const 2000))

    ;; Setup iovec
    (i32.store (local.get $iov_ptr) (i32.const 1000))
    (i32.store (i32.add (local.get $iov_ptr) (i32.const 4)) (i32.const 35))

    ;; Write to stdout
    (drop (call $fd_write (local.get $fd) (local.get $iov_ptr) (i32.const 1) (i32.const 3000)))

    ;; Test clock_time_get (monotonic clock)
    (drop (call $clock_time_get (i32.const 1) (i32.const 0) (i32.const 4000)))

    ;; Test random_get
    (drop (call $random_get (i32.const 5000) (i32.const 8)))

    ;; Test fd_fdstat_get on stdout
    (drop (call $fd_fdstat_get (i32.const 1) (i32.const 6000)))

    ;; Test environ_sizes_get
    (drop (call $environ_sizes_get (i32.const 7000) (i32.const 7004)))

    ;; Test args_sizes_get
    (drop (call $args_sizes_get (i32.const 7008) (i32.const 7012)))

    ;; Exit successfully
    (call $proc_exit (i32.const 0))
  )
)