__attribute__((export_name("add")))
int add(int a, int b) {
    return a + b;
}

__attribute__((export_name("main")))
int main(void) {
    return add(21, 21);
}
