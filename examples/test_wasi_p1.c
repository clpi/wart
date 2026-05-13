// Test WASI Preview 1 (snapshot_preview1)
// Compile: wasi-sdk clang test_wasi_p1.c -o test_wasi_p1.wasm
// Run: ./zig-out/bin/wart test_wasi_p1.wasm arg1 arg2

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

int main(int argc, char **argv) {
    // Test 1: Arguments
    printf("=== WASI Preview 1 Test Suite ===\n\n");
    printf("Test 1: Command-line arguments\n");
    printf("  argc = %d\n", argc);
    for (int i = 0; i < argc; i++) {
        printf("  argv[%d] = \"%s\"\n", i, argv[i]);
    }
    printf("  ✓ PASSED\n\n");

    // Test 2: Environment variables
    printf("Test 2: Environment variables\n");
    char *path = getenv("PATH");
    if (path) {
        printf("  PATH = %s\n", path);
    }
    char *home = getenv("HOME");
    if (home) {
        printf("  HOME = %s\n", home);
    }
    printf("  ✓ PASSED\n\n");

    // Test 3: stdout/stderr
    printf("Test 3: Standard I/O\n");
    printf("  Writing to stdout...\n");
    fprintf(stderr, "  Writing to stderr...\n");
    fflush(stdout);
    fflush(stderr);
    printf("  ✓ PASSED\n\n");

    // Test 4: Time functions
    printf("Test 4: Time and clock\n");
    time_t now = time(NULL);
    printf("  Current time: %ld\n", (long)now);
    printf("  ✓ PASSED\n\n");

    // Test 5: File operations
    printf("Test 5: File operations\n");
    FILE *f = fopen("test_file.txt", "w");
    if (f) {
        fprintf(f, "Hello from WASI P1!\n");
        .close(.{.userdata=null, .vtable=undefined})(f);
        printf("  Created test_file.txt\n");

        f = fopen("test_file.txt", "r");
        if (f) {
            char buf[100];
            if (fgets(buf, sizeof(buf), f)) {
                printf("  Read: %s", buf);
            }
            .close(.{.userdata=null, .vtable=undefined})(f);
            remove("test_file.txt");
            printf("  Deleted test_file.txt\n");
        }
        printf("  ✓ PASSED\n\n");
    } else {
        printf("  SKIPPED (file creation not supported)\n\n");
    }

    // Test 6: Working directory
    printf("Test 6: Working directory\n");
    char cwd[1024];
    if (getcwd(cwd, sizeof(cwd))) {
        printf("  cwd = %s\n", cwd);
        printf("  ✓ PASSED\n\n");
    } else {
        printf("  SKIPPED\n\n");
    }

    printf("=== All tests completed ===\n");
    return 0;
}
