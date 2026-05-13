pub fn main() !void {
    // Just compute and exit - no I/O
    var sum: i32 = 0;
    var i: i32 = 0;
    while (i < 10) : (i += 1) {
        sum += 1;
    }
    // Should return 10
}