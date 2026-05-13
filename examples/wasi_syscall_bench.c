/*
 * Comprehensive WASI Syscall Benchmark
 * Tests all major WASI Preview 1 syscalls for performance
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <time.h>
#include <dirent.h>

#define ITERATIONS 1000

int main(int argc, char **argv) {
    int i;
    char buffer[4096];
    char temp_file[] = "/tmp/wasi_bench_XXXXXX";
    int fd;
    struct stat st;
    size_t bytes_written, bytes_read;

    // Benchmark 1: args_get / args_sizes_get (implicit in argc/argv)
    for (i = 0; i < ITERATIONS; i++) {
        int arg_count = argc;
        (void)arg_count;
    }

    // Benchmark 2: environ_get / environ_sizes_get
    for (i = 0; i < ITERATIONS; i++) {
        char *env = getenv("PATH");
        (void)env;
    }

    // Benchmark 3: clock_time_get / clock_res_get
    for (i = 0; i < ITERATIONS; i++) {
        struct timespec ts;
        clock_gettime(CLOCK_REALTIME, &ts);
    }

    // Create a temporary file for I/O benchmarks
    fd = mkstemp(temp_file);
    if (fd < 0) {
        fprintf(stderr, "Failed to create temp file\n");
        return 1;
    }

    // Benchmark 4: fd_write
    memset(buffer, 'A', sizeof(buffer));
    for (i = 0; i < ITERATIONS / 10; i++) {
        bytes_written = write(fd, buffer, sizeof(buffer));
        (void)bytes_written;
    }

    // Benchmark 5: fd_seek
    for (i = 0; i < ITERATIONS; i++) {
        lseek(fd, 0, SEEK_SET);
    }

    // Benchmark 6: fd_read
    for (i = 0; i < ITERATIONS / 10; i++) {
        lseek(fd, 0, SEEK_SET);
        bytes_read = read(fd, buffer, sizeof(buffer));
        (void)bytes_read;
    }

    // Benchmark 7: fd_filestat_get (fstat)
    for (i = 0; i < ITERATIONS; i++) {
        fstat(fd, &st);
    }

    // Benchmark 8: fd_filestat_set_size (ftruncate)
    for (i = 0; i < ITERATIONS / 10; i++) {
        ftruncate(fd, 1024);
    }

    // Benchmark 9: fd_sync (fsync)
    for (i = 0; i < ITERATIONS / 100; i++) {
        fsync(fd);
    }

    // Benchmark 10: fd_close(.{.userdata=null, .vtable=undefined})
   .close(.{.userdata=null, .vtable=undefined})(fd);

    // Benchmark 11: path_open (open)
    for (i = 0; i < ITERATIONS / 10; i++) {
        fd = open(temp_file, O_RDONLY);
        if (fd >= 0) {
           .close(.{.userdata=null, .vtable=undefined})(fd);
        }
    }

    // Benchmark 12: path_filestat_get (stat)
    for (i = 0; i < ITERATIONS; i++) {
        stat(temp_file, &st);
    }

    // Benchmark 13: path_rename
    char new_name[] = "/tmp/wasi_bench_renamed";
    for (i = 0; i < ITERATIONS / 100; i++) {
        rename(temp_file, new_name);
        rename(new_name, temp_file);
    }

    // Benchmark 14: path_unlink_file (unlink)
    unlink(temp_file);

    // Benchmark 15: path_create_directory
    char test_dir[] = "/tmp/wasi_bench_dir";
    for (i = 0; i < ITERATIONS / 100; i++) {
        mkdir(test_dir, 0755);
        rmdir(test_dir);
    }

    // Benchmark 16: fd_readdir
    fd = open(".", O_RDONLY | O_DIRECTORY);
    if (fd >= 0) {
        for (i = 0; i < ITERATIONS / 10; i++) {
            lseek(fd, 0, SEEK_SET);
            while (read(fd, buffer, sizeof(buffer)) > 0) {
                // Reading directory
            }
        }
       .close(.{.userdata=null, .vtable=undefined})(fd);
    }

    // Benchmark 17: random_get (via /dev/urandom on WASI)
    for (i = 0; i < ITERATIONS / 10; i++) {
        // On WASI, this would use random_get syscall
        // For portability, we use standard C
        srand(time(NULL));
        int r = rand();
        (void)r;
    }

    // Final benchmark stats written to stdout
    printf("WASI syscall benchmark completed: %d iterations\n", ITERATIONS);

    return 0;
}
