const std = @import("std");
const testing = std.testing;
const WasiHttp = @import("wasi_http");
const WasiConcurrency = @import("wasi_concurrency");
const WasiNn = @import("wasi_nn");

test "http headers replace existing values in place" {
    const allocator = testing.allocator;
    var headers = WasiHttp.Headers.init(allocator);
    defer headers.deinit();

    try headers.set("Content-Type", "text/plain");
    try headers.set("Content-Type", "application/json");

    try testing.expectEqual(@as(usize, 1), headers.map.count());
    try testing.expectEqualStrings("application/json", headers.get("Content-Type").?);
}

test "http client preserves custom headers and request body" {
    const allocator = testing.allocator;

    var client = try WasiHttp.HttpClient.init(allocator);
    defer client.deinit();

    var request = try WasiHttp.Request.init(allocator, .POST, "https://httpbin.org/post");
    defer request.deinit(allocator);

    try request.headers.set("Content-Type", "application/json");
    try request.headers.set("Content-Type", "application/merge-patch+json");
    try request.setBody(allocator, "{\"op\":\"test\"}");

    var response = try client.send(&request);
    defer response.deinit(allocator);

    try testing.expectEqualStrings("application/merge-patch+json", request.headers.get("Content-Type").?);
    try testing.expectEqualStrings("13", request.headers.get("Content-Length").?);
    try testing.expectEqual(@as(u16, 200), response.status);
    try testing.expect(std.mem.indexOf(u8, response.body.?, "\"url\": \"https://httpbin.org/post\"") != null);
}

test "concurrency task transitions to completion" {
    const allocator = testing.allocator;

    var concurrency = try WasiConcurrency.WasiConcurrency.init(allocator);
    defer concurrency.deinit();

    const task_id = try concurrency.spawnTask(.normal);
    const initial_status = try concurrency.getTaskStatus(task_id);
    try testing.expect(initial_status == .pending or initial_status == .running);

    const result = (try concurrency.awaitTask(task_id)).?;
    defer allocator.free(result);

    try testing.expectEqualStrings("Task completed successfully", result);

    const final_status = try concurrency.getTaskStatus(task_id);
    try testing.expectEqual(WasiConcurrency.TaskStatus.completed, final_status);
}

test "wasi nn lifecycle supports load compute output" {
    const allocator = testing.allocator;

    var nn = try WasiNn.WasiNn.init(allocator);
    defer nn.deinit();

    const model = try nn.loadModel("tiny-model");
    const context = try nn.initExecutionContext(model);
    try nn.setInput(context, 0, "input-bytes");
    try nn.compute(context);

    var output: [64]u8 = undefined;
    const written = try nn.getOutput(context, 0, output[0..]);
    try testing.expect(written >= 16);
}
