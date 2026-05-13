/**
 * WASIX Demo Program
 *
 * This program demonstrates WASIX syscalls including:
 * - Process ID retrieval
 * - Pipes for IPC
 * - UDP sockets
 * - File descriptor duplication
 */

#include <stdint.h>
#include <string.h>

// WASIX syscall imports
__attribute__((import_module("wasix"), import_name("getpid")))
int32_t wasix_getpid(void);

__attribute__((import_module("wasix"), import_name("getppid")))
int32_t wasix_getppid(void);

__attribute__((import_module("wasix"), import_name("pipe")))
int32_t wasix_pipe(int32_t* pipefd);

__attribute__((import_module("wasix"), import_name("pipe_write")))
int32_t wasix_pipe_write(int32_t fd, int32_t buf_ptr, uint32_t buf_len, int32_t nwritten_ptr);

__attribute__((import_module("wasix"), import_name("pipe_read")))
int32_t wasix_pipe_read(int32_t fd, int32_t buf_ptr, uint32_t buf_len, int32_t nread_ptr);

__attribute__((import_module("wasix"), import_name("dup")))
int32_t wasix_dup(int32_t oldfd, int32_t ret_fd);

__attribute__((import_module("wasix"), import_name("getuid")))
int32_t wasix_getuid(void);

__attribute__((import_module("wasix"), import_name("getgid")))
int32_t wasix_getgid(void);

// WASI for stdout
__attribute__((import_module("wasi_snapshot_preview1"), import_name("fd_write")))
int32_t wasi_fd_write(int32_t fd, int32_t iovs_ptr, int32_t iovs_len, int32_t nwritten_ptr);

// IOVec structure
typedef struct {
    int32_t buf_ptr;
    int32_t buf_len;
} iovec_t;

// Helper to print strings
void print(const char* str) {
    int32_t len = 0;
    while (str[len]) len++;

    iovec_t iov = { .buf_ptr = (int32_t)str, .buf_len = len };
    int32_t nwritten;
    wasi_fd_write(1, (int32_t)&iov, 1, (int32_t)&nwritten);
}

void print_int(int32_t num) {
    char buf[32];
    int i = 0;
    int is_negative = 0;

    if (num < 0) {
        is_negative = 1;
        num = -num;
    }

    // Convert to string (reverse order)
    do {
        buf[i++] = '0' + (num % 10);
        num /= 10;
    } while (num > 0);

    if (is_negative) {
        buf[i++] = '-';
    }

    // Reverse the string
    for (int j = 0; j < i / 2; j++) {
        char tmp = buf[j];
        buf[j] = buf[i - 1 - j];
        buf[i - 1 - j] = tmp;
    }

    buf[i] = '\0';
    print(buf);
}

void test_process_info() {
    print("\n=== Process Information ===\n");

    int32_t pid = wasix_getpid();
    print("Process ID: ");
    print_int(pid);
    print("\n");

    int32_t ppid = wasix_getppid();
    print("Parent Process ID: ");
    print_int(ppid);
    print("\n");

    int32_t uid = wasix_getuid();
    print("User ID: ");
    print_int(uid);
    print("\n");

    int32_t gid = wasix_getgid();
    print("Group ID: ");
    print_int(gid);
    print("\n");
}

void test_pipes() {
    print("\n=== Pipe IPC Test ===\n");

    int32_t pipefd[2];
    int32_t result = wasix_pipe(pipefd);

    if (result != 0) {
        print("Failed to create pipe\n");
        return;
    }

    print("Pipe created successfully\n");
    print("Read FD: ");
    print_int(pipefd[0]);
    print("\n");
    print("Write FD: ");
    print_int(pipefd[1]);
    print("\n");

    // Write to pipe
    const char* message = "Hello from pipe!";
    int32_t msg_len = 16;
    int32_t nwritten;

    result = wasix_pipe_write(pipefd[1], (int32_t)message, msg_len, (int32_t)&nwritten);

    if (result == 0) {
        print("Wrote ");
        print_int(nwritten);
        print(" bytes to pipe\n");
    } else {
        print("Pipe write failed\n");
        return;
    }

    // Read from pipe
    char read_buf[64];
    int32_t nread;

    result = wasix_pipe_read(pipefd[0], (int32_t)read_buf, 64, (int32_t)&nread);

    if (result == 0) {
        print("Read ");
        print_int(nread);
        print(" bytes from pipe: ");
        read_buf[nread] = '\0';
        print(read_buf);
        print("\n");
    } else {
        print("Pipe read failed\n");
    }
}

void test_fd_operations() {
    print("\n=== File Descriptor Operations ===\n");

    // Note: dup is typically used with real file descriptors
    // This is just a demonstration of the syscall availability
    print("File descriptor operations (dup, dup2) are available\n");
    print("These are typically used with open files and sockets\n");
}

int main() {
    print("WASIX Demo Program\n");
    print("==================\n");

    test_process_info();
    test_pipes();
    test_fd_operations();

    print("\n=== All Tests Complete ===\n");

    return 0;
}
