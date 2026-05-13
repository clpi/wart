const std = @import("std");
const wasi3 = @import("wart").wasi3;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("=== WASI Preview 3 Demo ===\n\n", .{});

    // HTTP/3 Demo
    std.debug.print("1. HTTP/3 Client:\n", .{});
    var http3_client = try wasi3.HTTP3.init(allocator);
    defer http3_client.deinit();
    const conn = try http3_client.connect("api.example.com", 443);
    const req = try http3_client.request(conn, .GET, "/data", null);
    std.debug.print("   Connected to server, request ID: {d}\n\n", .{req});

    // gRPC Demo
    std.debug.print("2. gRPC Service:\n", .{});
    var grpc = try wasi3.GRPC.init(allocator);
    defer grpc.deinit();
    const service = try grpc.registerService("DataService");
    const stream = try grpc.openStream(service, "StreamData");
    try grpc.sendMessage(stream, "Hello from gRPC");
    std.debug.print("   Service registered, stream ID: {d}\n\n", .{stream});

    // Streaming with backpressure
    std.debug.print("3. Streaming with Backpressure:\n", .{});
    var streaming = try wasi3.Streaming.init(allocator);
    defer streaming.deinit();
    const data_stream = try streaming.createStream(1000);
    try streaming.write(data_stream, "chunk 1");
    try streaming.write(data_stream, "chunk 2");
    std.debug.print("   Stream created with capacity: 1000\n\n", .{});

    // Crypto operations
    std.debug.print("4. Cryptography:\n", .{});
    var crypto = try wasi3.Crypto.init(allocator);
    defer crypto.deinit();
    const key = try crypto.generateKey(.ed25519, true);
    const signature = try crypto.sign(key, "important data");
    std.debug.print("   Generated Ed25519 key, signature ID: {d}\n\n", .{signature});

    // Observability
    std.debug.print("5. Observability:\n", .{});
    var obs = try wasi3.Observability.init(allocator);
    defer obs.deinit();
    try obs.recordMetric("requests.total", 42.0, .counter);
    const span = try obs.startSpan("process_request", null);
    try obs.log(.info, "Processing request");
    try obs.endSpan(span);
    std.debug.print("   Recorded metrics, traces, and logs\n\n", .{});

    // Async Runtime
    std.debug.print("6. Async Runtime:\n", .{});
    var async_rt = try wasi3.AsyncRuntime.init(allocator);
    defer async_rt.deinit();
    const future = try async_rt.createFuture();
    const task = try async_rt.spawnTask(future);
    try async_rt.completeFuture(future, "completed");
    std.debug.print("   Created future and task, task ID: {d}\n\n", .{task});

    std.debug.print("Demo completed.\n", .{});
}
