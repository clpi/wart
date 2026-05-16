const std = @import("std");
const testing = std.testing;
const wasi3_mod = @import("../../src/wasm/wasi3.zig");
const WASI3 = wasi3_mod.WASI3;
const AsyncRuntime = wasi3_mod.AsyncRuntime;
const HTTP3 = wasi3_mod.HTTP3;
const GRPC = wasi3_mod.GRPC;
const Streaming = wasi3_mod.Streaming;
const Crypto = wasi3_mod.Crypto;
const Observability = wasi3_mod.Observability;

// AsyncRuntime tests
test "async runtime - create future" {
    const allocator = testing.allocator;
    var runtime = try AsyncRuntime.init(allocator);
    defer runtime.deinit();

    const future_id = try runtime.createFuture();
    try testing.expectEqual(@as(u32, 0), future_id);
}

test "async runtime - spawn task" {
    const allocator = testing.allocator;
    var runtime = try AsyncRuntime.init(allocator);
    defer runtime.deinit();

    const future_id = try runtime.createFuture();
    const task_id = try runtime.spawnTask(future_id);
    try testing.expectEqual(@as(u32, 0), task_id);
}

test "async runtime - complete future" {
    const allocator = testing.allocator;
    var runtime = try AsyncRuntime.init(allocator);
    defer runtime.deinit();

    const future_id = try runtime.createFuture();
    try runtime.completeFuture(future_id, "test result");

    const result = try runtime.awaitFuture(future_id);
    try testing.expectEqualStrings("test result", result);
}

// HTTP3 tests
test "http3 - connect to host" {
    const allocator = testing.allocator;
    var http3 = try HTTP3.init(allocator);
    defer http3.deinit();

    const conn_id = try http3.connect("example.com", 443);
    try testing.expectEqual(@as(u32, 0), conn_id);
    try testing.expectEqual(@as(usize, 1), http3.connections.items.len);
}

test "http3 - make request" {
    const allocator = testing.allocator;
    var http3 = try HTTP3.init(allocator);
    defer http3.deinit();

    const conn_id = try http3.connect("example.com", 443);
    const req_id = try http3.request(conn_id, .GET, "/api/test", null);

    try testing.expectEqual(@as(u32, 0), req_id);
    try testing.expectEqual(@as(usize, 1), http3.requests.items.len);
}

// GRPC tests
test "grpc - register service" {
    const allocator = testing.allocator;
    var grpc = try GRPC.init(allocator);
    defer grpc.deinit();

    const service_id = try grpc.registerService("MyService");
    try testing.expectEqual(@as(u32, 0), service_id);
    try testing.expectEqual(@as(usize, 1), grpc.services.items.len);
}

test "grpc - open stream" {
    const allocator = testing.allocator;
    var grpc = try GRPC.init(allocator);
    defer grpc.deinit();

    const service_id = try grpc.registerService("MyService");
    const stream_id = try grpc.openStream(service_id, "MyMethod");

    try testing.expectEqual(@as(u32, 0), stream_id);
    try testing.expectEqual(@as(usize, 1), grpc.streams.items.len);
}

test "grpc - send message" {
    const allocator = testing.allocator;
    var grpc = try GRPC.init(allocator);
    defer grpc.deinit();

    const service_id = try grpc.registerService("MyService");
    const stream_id = try grpc.openStream(service_id, "MyMethod");
    try grpc.sendMessage(stream_id, "test message");

    try testing.expectEqual(@as(usize, 1), grpc.streams.items[0].messages.items.len);
}

// Streaming tests
test "streaming - create stream" {
    const allocator = testing.allocator;
    var streaming = try Streaming.init(allocator);
    defer streaming.deinit();

    const stream_id = try streaming.createStream(100);
    try testing.expectEqual(@as(u32, 0), stream_id);
    try testing.expectEqual(@as(usize, 1), streaming.streams.items.len);
}

test "streaming - write and read" {
    const allocator = testing.allocator;
    var streaming = try Streaming.init(allocator);
    defer streaming.deinit();

    const stream_id = try streaming.createStream(100);
    try streaming.write(stream_id, "test data");

    const data = try streaming.read(stream_id);
    try testing.expect(data != null);
    try testing.expectEqualStrings("test data", data.?);
}

test "streaming - backpressure" {
    const allocator = testing.allocator;
    var streaming = try Streaming.init(allocator);
    defer streaming.deinit();

    const stream_id = try streaming.createStream(10);

    var i: usize = 0;
    while (i < 9) : (i += 1) {
        try streaming.write(stream_id, "data");
    }

    const result = streaming.write(stream_id, "data");
    try testing.expectError(error.Backpressure, result);
}

// Crypto tests
test "crypto - generate key" {
    const allocator = testing.allocator;
    var crypto = try Crypto.init(allocator);
    defer crypto.deinit();

    const key_id = try crypto.generateKey(.ed25519, true);
    try testing.expectEqual(@as(u32, 0), key_id);
    try testing.expectEqual(@as(usize, 1), crypto.keys.items.len);
}

test "crypto - sign data" {
    const allocator = testing.allocator;
    var crypto = try Crypto.init(allocator);
    defer crypto.deinit();

    const key_id = try crypto.generateKey(.ed25519, true);
    const sig_id = try crypto.sign(key_id, "test data");

    try testing.expectEqual(@as(u32, 0), sig_id);
    try testing.expectEqual(@as(usize, 1), crypto.signatures.items.len);
}

test "crypto - verify signature" {
    const allocator = testing.allocator;
    var crypto = try Crypto.init(allocator);
    defer crypto.deinit();

    const key_id = try crypto.generateKey(.ed25519, false);
    const valid = try crypto.verify(key_id, "test data", &[_]u8{0} **64);
    try testing.expect(valid);
}

// Observability tests
test "observability - record metric" {
    const allocator = testing.allocator;
    var obs = try Observability.init(allocator);
    defer obs.deinit();

    try obs.recordMetric("test.counter", 42.0, .counter);
    try testing.expectEqual(@as(usize, 1), obs.metrics.items.len);
    try testing.expectEqual(@as(f64, 42.0), obs.metrics.items[0].value);
}

test "observability - start and end span" {
    const allocator = testing.allocator;
    var obs = try Observability.init(allocator);
    defer obs.deinit();

    const span_id = try obs.startSpan("test_operation", null);
    try testing.expectEqual(@as(u64, 0), span_id);
    try testing.expect(obs.spans.items[0].end_time == null);

    try obs.endSpan(span_id);
    try testing.expect(obs.spans.items[0].end_time != null);
}

test "observability - log message" {
    const allocator = testing.allocator;
    var obs = try Observability.init(allocator);
    defer obs.deinit();

    try obs.log(.info, "Test log message");
    try testing.expectEqual(@as(usize, 1), obs.logs.items.len);
    try testing.expectEqualStrings("Test log message", obs.logs.items[0].message);
}
