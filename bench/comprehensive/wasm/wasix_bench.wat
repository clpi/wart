
(module
  ;; Wasix Extended Features Benchmark
  ;; Tests process management, networking, and IPC features

  (import "wasi_snapshot_preview1" "proc_exit" (func $proc_exit (param i32)))
  (import "wasi_snapshot_preview1" "fd_write" (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (import "wasix_snapshot_preview1" "sock_accept" (func $sock_accept (param i32 i32) (result i32)))
  (import "wasix_snapshot_preview1" "sock_connect" (func $sock_connect (param i32 i32 i32) (result i32)))
  (import "wasix_snapshot_preview1" "sock_recv" (func $sock_recv (param i32 i32 i32 i32 i32 i32) (result i32)))
  (import "wasix_snapshot_preview1" "sock_send" (func $sock_send (param i32 i32 i32 i32 i32) (result i32)))
  (import "wasix_snapshot_preview1" "sock_shutdown" (func $sock_shutdown (param i32 i32) (result i32)))
  (import "wasix_snapshot_preview1" "sock_bind" (func $sock_bind (param i32 i32 i32) (result i32)))
  (import "wasix_snapshot_preview1" "sock_listen" (func $sock_listen (param i32 i32) (result i32)))
  (import "wasix_snapshot_preview1" "sock_open" (func $sock_open (param i32 i32 i32 i32 i32) (result i32)))
  (import "wasix_snapshot_preview1" "sock_addr_local" (func $sock_addr_local (param i32 i32) (result i32)))
  (import "wasix_snapshot_preview1" "sock_addr_remote" (func $sock_addr_remote (param i32 i32) (result i32)))
  (import "wasix_snapshot_preview1" "sched_yield" (func $sched_yield (result i32)))
  (import "wasix_snapshot_preview1" "poll_oneoff" (func $poll_oneoff (param i32 i32 i32 i32) (result i32)))
  (import "wasix_snapshot_preview1" "pipe_create" (func $pipe_create (param i32 i32 i32) (result i32)))
  (import "wasix_snapshot_preview1" "pipe_write" (func $pipe_write (param i32 i32 i32 i32) (result i32)))
  (import "wasix_snapshot_preview1" "pipe_read" (func $pipe_read (param i32 i32 i32 i32) (result i32)))

  (memory (export "memory") 2)

  ;; Write buffer
  (data (i32.const 1000) "Wasix Extended Features Benchmark Complete\n")

  (func (export "_start")
    ;; Test basic I/O
    (local $iovec_ptr i32)

    (local.set $iovec_ptr (i32.const 2000))
    (i32.store (local.get $iovec_ptr) (i32.const 1000))
    (i32.store (i32.add (local.get $iovec_ptr) (i32.const 4)) (i32.const 40))

    ;; Write to stdout
    (drop (call $fd_write (i32.const 1) (local.get $iovec_ptr) (i32.const 1) (i32.const 3000)))

    ;; Test sched_yield
    (drop (call $sched_yield))

    ;; Exit successfully
    (call $proc_exit (i32.const 0))
  )
)
