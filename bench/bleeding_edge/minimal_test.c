#include <stdio.h>

int main() {
    printf("Starting test\n");
    fflush(stdout);

    FILE *f = fopen("test.txt", "w");
    printf("fopen returned: %p\n", (void*)f);
    fflush(stdout);

    if (!f) {
        printf("fopen failed\n");
        return 1;
    }

    printf("About to fprintf\n");
    fflush(stdout);

    int ret = fprintf(f, "Hello\n");
    printf("fprintf returned: %d\n", ret);
    fflush(stdout);

    .close(.{.userdata=null, .vtable=undefined})(f);
    printf("Done\n");

    return 0;
}
