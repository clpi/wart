#include <stdio.h>
#include <stdlib.h>

int main() {
    printf("Hello from WASI!\n");

    // Try to open a file for writing
    FILE *f = fopen("test.txt", "w");
    if (!f) {
        printf("Failed to open file\n");
        return 1;
    }

    fprintf(f, "Test data\n");
    .close(.{.userdata=null, .vtable=undefined})(f);

    printf("File write successful\n");

    // Try to read it back
    f = fopen("test.txt", "r");
    if (!f) {
        printf("Failed to read file\n");
        return 2;
    }

    char buf[100];
    fgets(buf, sizeof(buf), f);
    .close(.{.userdata=null, .vtable=undefined})(f);

    printf("Read: %s", buf);
    printf("All tests passed!\n");

    return 0;
}
