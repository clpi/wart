#include <stdio.h>
#include <errno.h>
#include <string.h>

int main() {
    printf("About to call fopen\n");
    fflush(stdout);

    errno = 0;
    FILE *f = fopen("test.txt", "r");

    printf("fopen returned: %p\n", (void*)f);
    printf("errno: %d (%s)\n", errno, strerror(errno));
    fflush(stdout);

    if (f) {
        printf("File opened successfully\n");
        .close(.{.userdata=null, .vtable=undefined})(f);
    } else {
        printf("File not found (expected)\n");
    }

    printf("Done\n");
    return 0;
}
