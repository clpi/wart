const std = @import("std");
const testing = std.testing;
const WasiCli = @import("wasi_cli");
const WasiHttp = @import("wasi_http");
const WasiConcurrency = @import("wasi_concurrency");

test "cli environment stores sparse argv and env values" {
    const allocator = testing.allocator;

    var env = WasiCli.Environment.init(allocator);
    defer env.deinit();

    try env.setArg(0, "wart");
    try env.setArg(2, "--bench");
    try env.setEnv("WART_MODE", "test");
    try env.setEnv("WART_MODE", "smoke");

    try testing.expectEqual(@as(usize, 3), env.args.items.len);
    try testing.expectEqualStrings("wart", env.args.items[0]);
    try testing.expectEqualStrings("", env.args.items[1]);
    try testing.expectEqualStrings("--bench", env.args.items[2]);
    try testing.expectEqualStrings("smoke", env.getEnv("WART_MODE").?);
}

test "http client returns deterministic mock responses" {
    const allocator = testing.allocator;

    var client = try WasiHttp.HttpClient.init(allocator);
    defer client.deinit();

    var response = try client.get("https://httpbin.org/get");
    defer response.deinit(allocator);

    try testing.expectEqual(@as(u16, 200), response.status);
    try testing.expectEqualStrings("application/json", response.headers.get("Content-Type").?);
    try testing.expect(std.mem.indexOf(u8, response.body.?, "\"url\": \"https://httpbin.org/get\"") != null);
}

test "concurrency futures and channels round-trip data" {
    const allocator = testing.allocator;

    var concurrency = try WasiConcurrency.WasiConcurrency.init(allocator);
    defer concurrency.deinit();

    const future_id = try concurrency.createFuture();
    try concurrency.completeFuture(future_id, "done");

    const future_value = (try concurrency.awaitFuture(future_id)).?;
    defer allocator.free(future_value);
    try testing.expectEqualStrings("done", future_value);

    const channel_id = try concurrency.createChannel(1);
    try concurrency.channelSend(channel_id, "ping");

    const message = (try concurrency.channelReceive(channel_id)).?;
    defer allocator.free(message);
    try testing.expectEqualStrings("ping", message);

    try concurrency.channelClose(channel_id);
    try testing.expect((try concurrency.channelReceive(channel_id)) == null);
}
