const std = @import("std");
const Module = @import("../module.zig");
const Runtime = @import("../runtime.zig");
const WASI = @import("../wasi.zig");

/// WASI Preview 1 (snapshot_preview1) Implementation
/// This module provides the official WASI Preview 1 syscall interface
///
/// Import module name: "wasi_snapshot_preview1"
/// Spec: https://github.com/WebAssembly/WASI/blob/snapshot-01/phases/snapshot/docs.md
pub const Preview1 = struct {
    wasi: *WASI,

    pub fn init(wasi: *WASI) Preview1 {
        return Preview1{ .wasi = wasi };
    }

    /// Get command-line argument count and buffer size
    /// Import: "wasi_snapshot_preview1"."args_sizes_get"
    pub fn args_sizes_get(self: *Preview1, argc_ptr: i32, argv_buf_size_ptr: i32, module: *Module) !i32 {
        return self.wasi.args_sizes_get(argc_ptr, argv_buf_size_ptr, module);
    }

    /// Get command-line arguments
    /// Import: "wasi_snapshot_preview1"."args_get"
    pub fn args_get(self: *Preview1, argv_ptr: i32, argv_buf_ptr: i32, module: *Module) !i32 {
        return self.wasi.args_get(argv_ptr, argv_buf_ptr, module);
    }

    /// Get environment variable count and buffer size
    /// Import: "wasi_snapshot_preview1"."environ_sizes_get"
    pub fn environ_sizes_get(self: *Preview1, environ_count_ptr: i32, environ_buf_size_ptr: i32, module: *Module) !i32 {
        return self.wasi.environ_sizes_get(environ_count_ptr, environ_buf_size_ptr, module);
    }

    /// Get environment variables
    /// Import: "wasi_snapshot_preview1"."environ_get"
    pub fn environ_get(self: *Preview1, environ_ptr: i32, environ_buf_ptr: i32, module: *Module) !i32 {
        return self.wasi.environ_get(environ_ptr, environ_buf_ptr, module);
    }

    /// Yield execution to other tasks
    /// Import: "wasi_snapshot_preview1"."sched_yield"
    pub fn sched_yield(self: *Preview1) !i32 {
        return self.wasi.sched_yield();
    }

    /// Generate random bytes
    /// Import: "wasi_snapshot_preview1"."random_get"
    pub fn random_get(self: *Preview1, buf_ptr: i32, buf_len: i32, module: *Module) !i32 {
        return self.wasi.random_get(buf_ptr, buf_len, module);
    }

    /// Get clock resolution
    /// Import: "wasi_snapshot_preview1"."clock_res_get"
    pub fn clock_res_get(self: *Preview1, clock_id: i32, resolution_ptr: i32, module: *Module) !i32 {
        return self.wasi.clock_res_get(clock_id, resolution_ptr, module);
    }

    /// Get clock time
    /// Import: "wasi_snapshot_preview1"."clock_time_get"
    pub fn clock_time_get(self: *Preview1, clock_id: i32, precision: i64, time_ptr: i32, module: *Module) !i32 {
        return self.wasi.clock_time_get(clock_id, precision, time_ptr, module);
    }

    /// Close a file descriptor
    /// Import: "wasi_snapshot_preview1"."fd_close(.{.userdata=null, .vtable=undefined})"
    pub fn fd_close(self: *Preview1, fd: i32) !i32 {
        return self.wasi.fd_close(fd);
    }

    /// Advise the system about file access patterns
    /// Import: "wasi_snapshot_preview1"."fd_advise"
    pub fn fd_advise(self: *Preview1, fd: i32, offset: i64, len: i64, advice: i32) !i32 {
        return self.wasi.fd_advise(fd, offset, len, advice);
    }

    /// Allocate space in a file
    /// Import: "wasi_snapshot_preview1"."fd_allocate"
    pub fn fd_allocate(self: *Preview1, fd: i32, offset: i64, len: i64) !i32 {
        return self.wasi.fd_allocate(fd, offset, len);
    }

    /// Synchronize file data and metadata to disk
    /// Import: "wasi_snapshot_preview1"."fd_sync"
    pub fn fd_sync(self: *Preview1, fd: i32) !i32 {
        return self.wasi.fd_sync(fd);
    }

    /// Synchronize file data to disk (metadata optional)
    /// Import: "wasi_snapshot_preview1"."fd_datasync"
    pub fn fd_datasync(self: *Preview1, fd: i32) !i32 {
        return self.wasi.fd_datasync(fd);
    }

    /// Get file descriptor attributes
    /// Import: "wasi_snapshot_preview1"."fd_fdstat_get"
    pub fn fd_fdstat_get(self: *Preview1, fd: i32, stat_ptr: i32, module: *Module) !i32 {
        return self.wasi.fd_fdstat_get(fd, stat_ptr, module);
    }

    /// Set file descriptor flags
    /// Import: "wasi_snapshot_preview1"."fd_fdstat_set_flags"
    pub fn fd_fdstat_set_flags(self: *Preview1, fd: i32, flags: i32) !i32 {
        return self.wasi.fd_fdstat_set_flags(fd, flags);
    }

    /// Set file descriptor rights
    /// Import: "wasi_snapshot_preview1"."fd_fdstat_set_rights"
    pub fn fd_fdstat_set_rights(self: *Preview1, fd: i32, fs_rights_base: i64, fs_rights_inheriting: i64) !i32 {
        return self.wasi.fd_fdstat_set_rights(fd, fs_rights_base, fs_rights_inheriting);
    }

    /// Get file attributes
    /// Import: "wasi_snapshot_preview1"."fd_filestat_get"
    pub fn fd_filestat_get(self: *Preview1, fd: i32, buf_ptr: i32, module: *Module) !i32 {
        return self.wasi.fd_filestat_get(fd, buf_ptr, module);
    }

    /// Set file size
    /// Import: "wasi_snapshot_preview1"."fd_filestat_set_size"
    pub fn fd_filestat_set_size(self: *Preview1, fd: i32, size: i64) !i32 {
        return self.wasi.fd_filestat_set_size(fd, size);
    }

    /// Set file timestamps
    /// Import: "wasi_snapshot_preview1"."fd_filestat_set_times"
    pub fn fd_filestat_set_times(self: *Preview1, fd: i32, atim: i64, mtim: i64, fst_flags: i32) !i32 {
        return self.wasi.fd_filestat_set_times(fd, atim, mtim, fst_flags);
    }

    /// Read from a file descriptor
    /// Import: "wasi_snapshot_preview1"."fd_read"
    pub fn fd_read(self: *Preview1, fd: i32, iovs_ptr: i32, iovs_len: i32, nread_ptr: i32, module: *Module) !i32 {
        return self.wasi.fd_read(fd, iovs_ptr, iovs_len, nread_ptr, module);
    }

    /// Read from a file descriptor at a given offset
    /// Import: "wasi_snapshot_preview1"."fd_pread"
    pub fn fd_pread(self: *Preview1, fd: i32, iovs_ptr: i32, iovs_len: i32, offset: i64, nread_ptr: i32, module: *Module) !i32 {
        return self.wasi.fd_pread(fd, iovs_ptr, iovs_len, offset, nread_ptr, module);
    }

    /// Write to a file descriptor
    /// Import: "wasi_snapshot_preview1"."fd_write"
    pub fn fd_write(self: *Preview1, fd: i32, iovs_ptr: i32, iovs_len: u32, written_ptr: i32, module: *Module) !i32 {
        return self.wasi.fd_write(fd, iovs_ptr, iovs_len, written_ptr, module);
    }

    /// Write to a file descriptor at a given offset
    /// Import: "wasi_snapshot_preview1"."fd_pwrite"
    pub fn fd_pwrite(self: *Preview1, fd: i32, iovs_ptr: i32, iovs_len: i32, offset: i64, nwritten_ptr: i32, module: *Module) !i32 {
        return self.wasi.fd_pwrite(fd, iovs_ptr, iovs_len, offset, nwritten_ptr, module);
    }

    /// Get information about a preopened directory
    /// Import: "wasi_snapshot_preview1"."fd_prestat_get"
    pub fn fd_prestat_get(self: *Preview1, fd: i32, prestat_ptr: i32, module: *Module) !i32 {
        return self.wasi.fd_prestat_get(fd, prestat_ptr, module);
    }

    /// Get the path of a preopened directory
    /// Import: "wasi_snapshot_preview1"."fd_prestat_dir_name"
    pub fn fd_prestat_dir_name(self: *Preview1, fd: i32, path_ptr: i32, path_len: i32, module: *Module) !i32 {
        return self.wasi.fd_prestat_dir_name(fd, path_ptr, path_len, module);
    }

    /// Read directory entries
    /// Import: "wasi_snapshot_preview1"."fd_readdir"
    pub fn fd_readdir(self: *Preview1, fd: i32, buf_ptr: i32, buf_len: i32, cookie: i64, bufused_ptr: i32, module: *Module) !i32 {
        return self.wasi.fd_readdir(fd, buf_ptr, buf_len, cookie, bufused_ptr, module);
    }

    /// Atomically replace a file descriptor
    /// Import: "wasi_snapshot_preview1"."fd_renumber"
    pub fn fd_renumber(self: *Preview1, from_fd: i32, to_fd: i32) !i32 {
        return self.wasi.fd_renumber(from_fd, to_fd);
    }

    /// Seek within a file
    /// Import: "wasi_snapshot_preview1"."fd_seek"
    pub fn fd_seek(self: *Preview1, fd: i32, offset: i64, whence: i32, new_offset_ptr: i32, module: *Module) !i32 {
        return self.wasi.fd_seek(fd, offset, whence, new_offset_ptr, module);
    }

    /// Return the current offset of a file descriptor
    /// Import: "wasi_snapshot_preview1"."fd_tell"
    pub fn fd_tell(self: *Preview1, fd: i32, offset_ptr: i32, module: *Module) !i32 {
        return self.wasi.fd_tell(fd, offset_ptr, module);
    }

    /// Create a directory
    /// Import: "wasi_snapshot_preview1"."path_create_directory"
    pub fn path_create_directory(self: *Preview1, dirfd: i32, path_ptr: i32, path_len: i32, module: *Module) !i32 {
        return self.wasi.path_create_directory(dirfd, path_ptr, path_len, module);
    }

    /// Get file or directory metadata
    /// Import: "wasi_snapshot_preview1"."path_filestat_get"
    pub fn path_filestat_get(self: *Preview1, dirfd: i32, flags: i32, path_ptr: i32, path_len: i32, buf_ptr: i32, module: *Module) !i32 {
        return self.wasi.path_filestat_get(dirfd, flags, path_ptr, path_len, buf_ptr, module);
    }

    /// Set file or directory timestamps
    /// Import: "wasi_snapshot_preview1"."path_filestat_set_times"
    pub fn path_filestat_set_times(self: *Preview1, dirfd: i32, flags: i32, path_ptr: i32, path_len: i32, atim: i64, mtim: i64, fst_flags: i32) !i32 {
        return self.wasi.path_filestat_set_times(dirfd, flags, path_ptr, path_len, atim, mtim, fst_flags);
    }

    /// Create a hard link
    /// Import: "wasi_snapshot_preview1"."path_link"
    pub fn path_link(self: *Preview1, old_fd: i32, old_flags: i32, old_path_ptr: i32, old_path_len: i32, new_fd: i32, new_path_ptr: i32, new_path_len: i32, module: *Module) !i32 {
        return self.wasi.path_link(old_fd, old_flags, old_path_ptr, old_path_len, new_fd, new_path_ptr, new_path_len, module);
    }

    /// Open a file or directory
    /// Import: "wasi_snapshot_preview1"."path_open"
    pub fn path_open(self: *Preview1, dirfd: i32, dirflags: i32, path_ptr: i32, path_len: i32, oflags: i32, fs_rights_base: i64, fs_rights_inheriting: i64, fdflags: i32, fd_ptr: i32, module: *Module) !i32 {
        return self.wasi.path_open(dirfd, dirflags, path_ptr, path_len, oflags, fs_rights_base, fs_rights_inheriting, fdflags, fd_ptr, module);
    }

    /// Read the contents of a symbolic link
    /// Import: "wasi_snapshot_preview1"."path_readlink"
    pub fn path_readlink(self: *Preview1, dirfd: i32, path_ptr: i32, path_len: i32, buf_ptr: i32, buf_len: i32, bufused_ptr: i32, module: *Module) !i32 {
        return self.wasi.path_readlink(dirfd, path_ptr, path_len, buf_ptr, buf_len, bufused_ptr, module);
    }

    /// Remove a directory
    /// Import: "wasi_snapshot_preview1"."path_remove_directory"
    pub fn path_remove_directory(self: *Preview1, dirfd: i32, path_ptr: i32, path_len: i32, module: *Module) !i32 {
        return self.wasi.path_remove_directory(dirfd, path_ptr, path_len, module);
    }

    /// Rename a file or directory
    /// Import: "wasi_snapshot_preview1"."path_rename"
    pub fn path_rename(self: *Preview1, old_fd: i32, old_path_ptr: i32, old_path_len: i32, new_fd: i32, new_path_ptr: i32, new_path_len: i32, module: *Module) !i32 {
        return self.wasi.path_rename(old_fd, old_path_ptr, old_path_len, new_fd, new_path_ptr, new_path_len, module);
    }

    /// Create a symbolic link
    /// Import: "wasi_snapshot_preview1"."path_symlink"
    pub fn path_symlink(self: *Preview1, old_path_ptr: i32, old_path_len: i32, dirfd: i32, new_path_ptr: i32, new_path_len: i32, module: *Module) !i32 {
        return self.wasi.path_symlink(old_path_ptr, old_path_len, dirfd, new_path_ptr, new_path_len, module);
    }

    /// Unlink a file
    /// Import: "wasi_snapshot_preview1"."path_unlink_file"
    pub fn path_unlink_file(self: *Preview1, dirfd: i32, path_ptr: i32, path_len: i32, module: *Module) !i32 {
        return self.wasi.path_unlink_file(dirfd, path_ptr, path_len, module);
    }

    /// Poll for events on file descriptors
    /// Import: "wasi_snapshot_preview1"."poll_oneoff"
    pub fn poll_oneoff(self: *Preview1, in_ptr: i32, out_ptr: i32, nsubscriptions: i32, nevents_ptr: i32, module: *Module) !i32 {
        return self.wasi.poll_oneoff(in_ptr, out_ptr, nsubscriptions, nevents_ptr, module);
    }

    /// Terminate the process
    /// Import: "wasi_snapshot_preview1"."proc_exit"
    pub fn proc_exit(self: *Preview1, exit_code: i32) !i32 {
        return self.wasi.proc_exit(exit_code);
    }

    /// Send a signal to the process
    /// Import: "wasi_snapshot_preview1"."proc_raise"
    pub fn proc_raise(self: *Preview1, sig: i32) !i32 {
        return self.wasi.proc_raise(sig);
    }
};
