#include <stdio.h>

int main(int argc, char* argv[]) {
  printf("argc = %d\n", argc);
  printf("hello, world\n");
  for (int i = 0; i < argc; i++) {
    printf("arg %d: %s\n", i, argv[i]);
  }
  return 0;
}
