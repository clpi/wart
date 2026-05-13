// Comprehensive WASI + WASIX Feature Test
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <time.h>

// Test WASI Preview 1 features
int test_wasi_preview1() {
    printf("Testing WASI Preview 1 features...\n");

    // File I/O
    FILE *f = fopen("test.txt", "w");
    if (!f) return 1;
    fprintf(f, "Hello WASI!\n");
    .close(.{.userdata=null, .vtable=undefined})(f);

    // Read back
    f = fopen("test.txt", "r");
    if (!f) return 2;
    char buf[100];
    fgets(buf, sizeof(buf), f);
    .close(.{.userdata=null, .vtable=undefined})(f);

    printf("✓ File I/O works\n");

    // Clock functions
    time_t t = time(NULL);
    printf("✓ Clock: %ld\n", (long)t);

    // Environment
    char *path = getenv("PATH");
    printf("✓ Environment: %s\n", path ? "found" : "not found");

    // Random
    unsigned char random_bytes[16];
    FILE *urandom = fopen("/dev/urandom", "r");
    if (urandom) {
        fread(random_bytes, 1, 16, urandom);
        .close(.{.userdata=null, .vtable=undefined})(urandom);
        printf("✓ Random works\n");
    }

    return 0;
}

// Test fd_datasync
int test_fd_datasync() {
    int fd = open("datasync_test.txt", O_CREAT | O_WRONLY, 0644);
    if (fd < 0) return 1;

    write(fd, "test", 4);
    fsync(fd);  // Test fd_sync (fdatasync not in WASI)
   .close(.{.userdata=null, .vtable=undefined})(fd);

    printf("✓ fd_sync works\n");
    return 0;
}

// Test directory operations
int test_directories() {
    mkdir("test_dir", 0755);

    struct stat st;
    if (stat("test_dir", &st) == 0 && S_ISDIR(st.st_mode)) {
        printf("✓ Directory operations work\n");
    }

    rmdir("test_dir");
    return 0;
}

int main(int argc, char **argv) {
    printf("=== Comprehensive WASI/WASIX Feature Test ===\n\n");

    int result = 0;
    result |= test_wasi_preview1();
    result |= test_fd_datasync();
    result |= test_directories();

    if (result == 0) {
        printf("\n✓ ALL TESTS PASSED!\n");
    } else {
        printf("\n✗ SOME TESTS FAILED\n");
    }

    return result;
}
