(module
  ;; WASI benchmark testing various WASI functions
  (import "wasi_snapshot_preview1" "args_get"
    (func $wasi_args_get (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "args_sizes_get"
    (func $wasi_args_sizes_get (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "environ_get"
    (func $wasi_environ_get (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "environ_sizes_get"
    (func $wasi_environ_sizes_get (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "clock_time_get"
    (func $wasi_clock_time_get (param i32 i64 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $wasi_fd_write (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_read"
    (func $wasi_fd_read (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_close(.{.userdata=null, .vtable=undefined})"
    (func $wasi_fd_close(.{.userdata=null, .vtable=undefined}) (param i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_seek"
    (func $wasi_fd_seek (param i32 i64 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "random_get"
    (func $wasi_random_get (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "proc_exit"
    (func $wasi_proc_exit (param i32)))
  (import "wasi_snapshot_preview1" "sched_yield"
    (func $wasi_sched_yield (result i32)))

  (memory 1)

  ;; Benchmark counter
  (global $wasi_call_count (mut i32) (i32.const 0))

  ;; Helper function to increment counter
  (func $inc_counter
    global.get $wasi_call_count
    i32.const 1
    i32.add
    global.set $wasi_call_count
  )

  ;; Test args functions
  (func $test_args (param $iterations i32)
    (local $i i32)
    (local $argc_ptr i32)
    (local $argv_buf_size i32)

    i32.const 0
    local.set $i

    loop $args_loop
      local.get $i
      local.get $iterations
      i32.lt_u
      if
        ;; args_sizes_get
        i32.const 0  ;; argc_ptr
        i32.const 4  ;; argv_buf_size_ptr
        call $wasi_args_sizes_get
        call $inc_counter

        ;; args_get
        i32.const 8  ;; argv_ptr
        i32.const 12 ;; argv_buf_ptr
        call $wasi_args_get
        call $inc_counter

        ;; Increment loop counter
        local.get $i
        i32.const 1
        i32.add
        local.set $i
        br $args_loop
      end
    end
  )

  ;; Test environ functions
  (func $test_environ (param $iterations i32)
    (local $i i32)

    i32.const 0
    local.set $i

    loop $environ_loop
      local.get $i
      local.get $iterations
      i32.lt_u
      if
        ;; environ_sizes_get
        i32.const 0  ;; environ_count_ptr
        i32.const 4  ;; environ_buf_size_ptr
        call $wasi_environ_sizes_get
        call $inc_counter

        ;; environ_get
        i32.const 8  ;; environ_ptr
        i32.const 12 ;; environ_buf_ptr
        call $wasi_environ_get
        call $inc_counter

        ;; Increment loop counter
        local.get $i
        i32.const 1
        i32.add
        local.set $i
        br $environ_loop
      end
    end
  )

  ;; Test clock functions
  (func $test_clock (param $iterations i32)
    (local $i i32)

    i32.const 0
    local.set $i

    loop $clock_loop
      local.get $i
      local.get $iterations
      i32.lt_u
      if
        ;; clock_time_get (realtime)
        i32.const 0  ;; clock_id
        i64.const 1000000 ;; precision
        i32.const 0  ;; time_ptr
        call $wasi_clock_time_get
        call $inc_counter

        ;; clock_time_get (monotonic)
        i32.const 1  ;; clock_id
        i64.const 1000000 ;; precision
        i32.const 0  ;; time_ptr
        call $wasi_clock_time_get
        call $inc_counter

        ;; Increment loop counter
        local.get $i
        i32.const 1
        i32.add
        local.set $i
        br $clock_loop
      end
    end
  )

  ;; Test file I/O functions
  (func $test_file_io (param $iterations i32)
    (local $i i32)
    (local $iovs_base i32)
    (local $iovs_len i32)

    ;; Prepare I/O vectors
    i32.const 0
    i32.const 16 ;; iovs[0].base
    i32.store

    i32.const 4
    i32.const 12 ;; iovs[0].len
    i32.store

    ;; Write test data
    i32.const 16
    i32.const 72 ;; 'H'
    i32.store8
    i32.const 17
    i32.const 101 ;; 'e'
    i32.store8
    i32.const 18
    i32.const 108 ;; 'l'
    i32.store8
    i32.const 19
    i32.const 108 ;; 'l'
    i32.store8
    i32.const 20
    i32.const 111 ;; 'o'
    i32.store8
    i32.const 21
    i32.const 32 ;; ' '
    i32.store8
    i32.const 22
    i32.const 87 ;; 'W'
    i32.store8
    i32.const 23
    i32.const 65 ;; 'A'
    i32.store8
    i32.const 24
    i32.const 83 ;; 'S'
    i32.store8
    i32.const 25
    i32.const 73 ;; 'I'
    i32.store8
    i32.const 26
    i32.const 33 ;; '!'
    i32.store8

    i32.const 0
    local.set $i

    loop $file_io_loop
      local.get $i
      local.get $iterations
      i32.lt_u
      if
        ;; fd_write to stdout
        i32.const 1  ;; stdout
        i32.const 0  ;; iovs_ptr
        i32.const 1  ;; iovs_len
        i32.const 28 ;; nwritten_ptr
        call $wasi_fd_write
        call $inc_counter

        ;; fd_read from stdin (may not work in all environments)
        i32.const 0  ;; stdin
        i32.const 0  ;; iovs_ptr
        i32.const 1  ;; iovs_len
        i32.const 32 ;; nread_ptr
        call $wasi_fd_read
        call $inc_counter

        ;; Increment loop counter
        local.get $i
        i32.const 1
        i32.add
        local.set $i
        br $file_io_loop
      end
    end
  )

  ;; Test random function
  (func $test_random (param $iterations i32)
    (local $i i32)

    i32.const 0
    local.set $i

    loop $random_loop
      local.get $i
      local.get $iterations
      i32.lt_u
      if
        ;; random_get
        i32.const 36 ;; buf_ptr
        i32.const 16 ;; buf_len
        call $wasi_random_get
        call $inc_counter

        ;; Increment loop counter
        local.get $i
        i32.const 1
        i32.add
        local.set $i
        br $random_loop
      end
    end
  )

  ;; Test other functions
  (func $test_other (param $iterations i32)
    (local $i i32)

    i32.const 0
    local.set $i

    loop $other_loop
      local.get $i
      local.get $iterations
      i32.lt_u
      if
        ;; sched_yield
        call $wasi_sched_yield
        call $inc_counter

        ;; Increment loop counter
        local.get $i
        i32.const 1
        i32.add
        local.set $i
        br $other_loop
      end
    end
  )

  ;; Main WASI benchmark function
  (func $run_wasi_benchmark (param $iterations i32) (result i32)
    ;; Reset counter
    i32.const 0
    global.set $wasi_call_count

    ;; Run all WASI tests
    local.get $iterations
    call $test_args

    local.get $iterations
    call $test_environ

    local.get $iterations
    call $test_clock

    local.get $iterations
    call $test_file_io

    local.get $iterations
    call $test_random

    local.get $iterations
    call $test_other

    ;; Return total WASI call count
    global.get $wasi_call_count
  )

  ;; Main entry point with default iterations
  (func $main (result i32)
    i32.const 100  ;; Default iterations for WASI calls (less intensive)
    call $run_wasi_benchmark
  )

  ;; Export main function
  (export "_start" (func $main))
)
