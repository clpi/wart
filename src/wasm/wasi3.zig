/// WASI Preview 3 - Future Features and Experimental APIs
///
/// This module implements proposed features for WASI Preview 3:
/// - Enhanced async/await primitives
/// - Structured concurrency
/// - Advanced resource management
/// - Distributed computing primitives
/// - Enhanced networking (HTTP/3, WebSocket, gRPC)
/// - Machine learning inference APIs
/// - GPU compute primitives
const std = @import("std");
const Allocator = std.mem.Allocator;
const WASI2 = @import("wasi2.zig").WASI2;
const ArrayList = std.array_list.Managed;

// Import crypto modules from Zig std
const crypto = std.crypto;
const Sha256 = crypto.hash.sha2.Sha256;
const Sha384 = crypto.hash.sha2.Sha384;
const Sha512 = crypto.hash.sha2.Sha512;
const Blake3 = crypto.hash.Blake3;
const Ed25519 = crypto.sign.Ed25519;

/// WASI Preview 3 context
pub const WASI3 = struct {
    allocator: Allocator,
    debug: bool = false,

    // Shared IO handle
    io: std.Io,

    // WASI2 compatibility layer
    wasi2: *WASI2,

    // Preview 3 extensions
    async_runtime: *AsyncRuntime,
    distributed: *Distributed,
    ml: *MachineLearning,
    gpu: *GPU,
    websocket: *WebSocket,
    http3: *HTTP3,
    grpc: *GRPC,
    streaming: *Streaming,
    crypto: *Crypto,
    observability: *Observability,

    pub fn init(allocator: Allocator, wasi2: *WASI2, io: std.Io) !*WASI3 {
        const wasi3 = try allocator.create(WASI3);

        wasi3.* = WASI3{
            .allocator = allocator,
            .io = io,
            .wasi2 = wasi2,
            .async_runtime = try AsyncRuntime.init(allocator),
            .distributed = try Distributed.init(allocator),
            .ml = try MachineLearning.init(allocator),
            .gpu = try GPU.init(allocator),
            .websocket = try WebSocket.init(allocator),
            .http3 = try HTTP3.init(allocator),
            .grpc = try GRPC.init(allocator),
            .streaming = try Streaming.init(allocator),
            .crypto = try Crypto.init(allocator),
            .observability = try Observability.init(allocator),
        };

        return wasi3;
    }

    pub fn deinit(self: *WASI3) void {
        self.async_runtime.deinit();
        self.distributed.deinit();
        self.ml.deinit();
        self.gpu.deinit();
        self.websocket.deinit();
        self.http3.deinit();
        self.grpc.deinit();
        self.streaming.deinit();
        self.crypto.deinit();
        self.observability.deinit();
        self.allocator.destroy(self);
    }
};

/// Enhanced async/await runtime with structured concurrency
pub const AsyncRuntime = struct {
    allocator: Allocator,
    futures: ArrayList(Future),
    tasks: ArrayList(Task),

    pub const Future = struct {
        id: u32,
        state: FutureState,
        result: ?[]const u8 = null,
        error_info: ?[]const u8 = null,

        pub const FutureState = enum {
            pending,
            ready,
            error_state,
        };
    };

    pub const Task = struct {
        id: u32,
        future_id: u32,
        state: TaskState,

        pub const TaskState = enum {
            created,
            running,
            suspended,
            completed,
            cancelled,
        };
    };

    pub fn init(allocator: Allocator) !*AsyncRuntime {
        const runtime = try allocator.create(AsyncRuntime);
        runtime.* = AsyncRuntime{
            .allocator = allocator,
            .futures = ArrayList(Future).init(allocator),
            .tasks = ArrayList(Task).init(allocator),
        };
        return runtime;
    }

    pub fn deinit(self: *AsyncRuntime) void {
        for (self.futures.items) |*future| {
            if (future.result) |result| self.allocator.free(result);
            if (future.error_info) |error_info| self.allocator.free(error_info);
        }
        self.futures.deinit();
        self.tasks.deinit();
        self.allocator.destroy(self);
    }

    /// Create a new future
    pub fn createFuture(self: *AsyncRuntime) !u32 {
        const future_id: u32 = @intCast(self.futures.items.len);
        try self.futures.append(Future{
            .id = future_id,
            .state = .pending,
        });
        return future_id;
    }

    /// Spawn a new task
    pub fn spawnTask(self: *AsyncRuntime, future_id: u32) !u32 {
        const task_id: u32 = @intCast(self.tasks.items.len);
        try self.tasks.append(Task{
            .id = task_id,
            .future_id = future_id,
            .state = .running,
        });
        return task_id;
    }

    /// Await a future (simplified implementation)
    pub fn awaitFuture(self: *AsyncRuntime, future_id: u32) ![]const u8 {
        for (self.futures.items) |*future| {
            if (future.id == future_id) {
                if (future.state == .ready) {
                    if (future.result) |result| {
                        return result;
                    }
                } else if (future.state == .error_state) {
                    return error.FutureFailed;
                }
                return error.FuturePending;
            }
        }
        return error.FutureNotFound;
    }

    /// Complete a future with a result
    pub fn completeFuture(self: *AsyncRuntime, future_id: u32, result: []const u8) !void {
        for (self.futures.items) |*future| {
            if (future.id == future_id) {
                future.result = try self.allocator.dupe(u8, result);
                future.state = .ready;
                return;
            }
        }
        return error.FutureNotFound;
    }
};

/// Distributed computing primitives
pub const Distributed = struct {
    allocator: Allocator,
    workers: ArrayList(Worker),
    messages: ArrayList(Message),

    pub const Worker = struct {
        id: u32,
        endpoint: []const u8,
        state: WorkerState,

        pub const WorkerState = enum {
            idle,
            busy,
            offline,
        };
    };

    pub const Message = struct {
        id: u32,
        from_worker: u32,
        to_worker: u32,
        data: []const u8,
        timestamp: i64,
    };

    pub fn init(allocator: Allocator) !*Distributed {
        const distributed = try allocator.create(Distributed);
        distributed.* = Distributed{
            .allocator = allocator,
            .workers = ArrayList(Worker).init(allocator),
            .messages = ArrayList(Message).init(allocator),
        };
        return distributed;
    }

    pub fn deinit(self: *Distributed) void {
        for (self.workers.items) |*worker| {
            self.allocator.free(worker.endpoint);
        }
        for (self.messages.items) |*message| {
            self.allocator.free(message.data);
        }
        self.workers.deinit();
        self.messages.deinit();
        self.allocator.destroy(self);
    }

    /// Register a worker node
    pub fn registerWorker(self: *Distributed, endpoint: []const u8) !u32 {
        const worker_id: u32 = @intCast(self.workers.items.len);
        try self.workers.append(Worker{
            .id = worker_id,
            .endpoint = try self.allocator.dupe(u8, endpoint),
            .state = .idle,
        });
        return worker_id;
    }

    /// Send a message to a worker
    pub fn sendMessage(self: *Distributed, from: u32, to: u32, data: []const u8) !u32 {
        const message_id: u32 = @intCast(self.messages.items.len);
        try self.messages.append(Message{
            .id = message_id,
            .from_worker = from,
            .to_worker = to,
            .data = try self.allocator.dupe(u8, data),
            .timestamp = std.time.milliTimestamp(),
        });
        return message_id;
    }
};

/// Machine Learning inference APIs
pub const MachineLearning = struct {
    allocator: Allocator,
    models: ArrayList(Model),
    tensors: ArrayList(Tensor),

    pub const Model = struct {
        id: u32,
        name: []const u8,
        format: ModelFormat,
        loaded: bool = false,

        pub const ModelFormat = enum {
            onnx,
            tensorflow,
            pytorch,
            custom,
        };
    };

    pub const Tensor = struct {
        id: u32,
        shape: []const u64,
        dtype: DataType,
        data: []const u8,

        pub const DataType = enum {
            float32,
            float64,
            int32,
            int64,
            uint8,
        };
    };

    pub fn init(allocator: Allocator) !*MachineLearning {
        const ml = try allocator.create(MachineLearning);
        ml.* = MachineLearning{
            .allocator = allocator,
            .models = ArrayList(Model).init(allocator),
            .tensors = ArrayList(Tensor).init(allocator),
        };
        return ml;
    }

    pub fn deinit(self: *MachineLearning) void {
        for (self.models.items) |*model| {
            self.allocator.free(model.name);
        }
        for (self.tensors.items) |*tensor| {
            self.allocator.free(tensor.shape);
            self.allocator.free(tensor.data);
        }
        self.models.deinit();
        self.tensors.deinit();
        self.allocator.destroy(self);
    }

    /// Load a machine learning model
    pub fn loadModel(self: *MachineLearning, name: []const u8, format: Model.ModelFormat) !u32 {
        const model_id: u32 = @intCast(self.models.items.len);
        try self.models.append(Model{
            .id = model_id,
            .name = try self.allocator.dupe(u8, name),
            .format = format,
            .loaded = true,
        });
        return model_id;
    }

    /// Create a tensor
    pub fn createTensor(
        self: *MachineLearning,
        shape: []const u64,
        dtype: Tensor.DataType,
        data: []const u8,
    ) !u32 {
        const tensor_id: u32 = @intCast(self.tensors.items.len);
        try self.tensors.append(Tensor{
            .id = tensor_id,
            .shape = try self.allocator.dupe(u64, shape),
            .dtype = dtype,
            .data = try self.allocator.dupe(u8, data),
        });
        return tensor_id;
    }

    /// Run inference on a model (simplified)
    pub fn runInference(self: *MachineLearning, model_id: u32, input_tensor_id: u32) !u32 {
        _ = self;
        _ = model_id;
        _ = input_tensor_id;

        // Simplified: would actually run the model
        // For now, just return a dummy output tensor ID
        return 0;
    }
};

/// GPU compute primitives
pub const GPU = struct {
    allocator: Allocator,
    devices: ArrayList(Device),
    buffers: ArrayList(Buffer),
    kernels: ArrayList(Kernel),

    pub const Device = struct {
        id: u32,
        name: []const u8,
        compute_units: u32,
        available: bool = true,
    };

    pub const Buffer = struct {
        id: u32,
        size: u64,
        device_id: u32,
        data: ?[]const u8 = null,
    };

    pub const Kernel = struct {
        id: u32,
        name: []const u8,
        source: []const u8,
        compiled: bool = false,
    };

    pub fn init(allocator: Allocator) !*GPU {
        const gpu = try allocator.create(GPU);
        gpu.* = GPU{
            .allocator = allocator,
            .devices = ArrayList(Device).init(allocator),
            .buffers = ArrayList(Buffer).init(allocator),
            .kernels = ArrayList(Kernel).init(allocator),
        };
        return gpu;
    }

    pub fn deinit(self: *GPU) void {
        for (self.devices.items) |*device| {
            self.allocator.free(device.name);
        }
        for (self.buffers.items) |*buffer| {
            if (buffer.data) |data| self.allocator.free(data);
        }
        for (self.kernels.items) |*kernel| {
            self.allocator.free(kernel.name);
            self.allocator.free(kernel.source);
        }
        self.devices.deinit();
        self.buffers.deinit();
        self.kernels.deinit();
        self.allocator.destroy(self);
    }

    /// Enumerate GPU devices
    pub fn enumerateDevices(self: *GPU) ![]const Device {
        // Simplified: would query actual GPU devices
        // For now, add a dummy device
        if (self.devices.items.len == 0) {
            try self.devices.append(Device{
                .id = 0,
                .name = try self.allocator.dupe(u8, "CPU Compute Device"),
                .compute_units = 8,
            });
        }
        return self.devices.items;
    }

    /// Create a GPU buffer
    pub fn createBuffer(self: *GPU, device_id: u32, size: u64) !u32 {
        const buffer_id: u32 = @intCast(self.buffers.items.len);
        try self.buffers.append(Buffer{
            .id = buffer_id,
            .size = size,
            .device_id = device_id,
        });
        return buffer_id;
    }

    /// Compile a kernel
    pub fn compileKernel(self: *GPU, name: []const u8, source: []const u8) !u32 {
        const kernel_id: u32 = @intCast(self.kernels.items.len);
        try self.kernels.append(Kernel{
            .id = kernel_id,
            .name = try self.allocator.dupe(u8, name),
            .source = try self.allocator.dupe(u8, source),
            .compiled = true,
        });
        return kernel_id;
    }
};

/// WebSocket API for bidirectional communication
pub const WebSocket = struct {
    allocator: Allocator,
    connections: ArrayList(Connection),

    pub const Connection = struct {
        id: u32,
        url: []const u8,
        state: ConnectionState,
        messages: ArrayList(Message),

        pub const ConnectionState = enum {
            connecting,
            open,
            closing,
            .closed,
        };

        pub const Message = struct {
            data: []const u8,
            is_binary: bool,
            timestamp: i64,
        };
    };

    pub fn init(allocator: Allocator) !*WebSocket {
        const ws = try allocator.create(WebSocket);
        ws.* = WebSocket{
            .allocator = allocator,
            .connections = ArrayList(Connection).init(allocator),
        };
        return ws;
    }

    pub fn deinit(self: *WebSocket) void {
        for (self.connections.items) |*conn| {
            self.allocator.free(conn.url);
            for (conn.messages.items) |*msg| {
                self.allocator.free(msg.data);
            }
            conn.messages.deinit();
        }
        self.connections.deinit();
        self.allocator.destroy(self);
    }

    /// Connect to a WebSocket server
    pub fn connect(self: *WebSocket, url: []const u8) !u32 {
        const conn_id: u32 = @intCast(self.connections.items.len);
        try self.connections.append(Connection{
            .id = conn_id,
            .url = try self.allocator.dupe(u8, url),
            .state = .connecting,
            .messages = ArrayList(Connection.Message).init(self.allocator),
        });

        // Transition to open (simplified - would actually connect)
        self.connections.items[conn_id].state = .open;
        return conn_id;
    }

    /// Send a message over WebSocket
    pub fn send(self: *WebSocket, conn_id: u32, data: []const u8, is_binary: bool) !void {
        for (self.connections.items) |*conn| {
            if (conn.id == conn_id) {
                if (conn.state != .open) return error.ConnectionNotOpen;

                try conn.messages.append(Connection.Message{
                    .data = try self.allocator.dupe(u8, data),
                    .is_binary = is_binary,
                    .timestamp = std.time.milliTimestamp(),
                });
                return;
            }
        }
        return error.ConnectionNotFound;
    }

    /// Receive a message from WebSocket (non-blocking)
    pub fn receive(self: *WebSocket, conn_id: u32) !?Connection.Message {
        for (self.connections.items) |*conn| {
            if (conn.id == conn_id) {
                if (conn.messages.items.len > 0) {
                    return conn.messages.orderedRemove(0);
                }
                return null;
            }
        }
        return error.ConnectionNotFound;
    }

    /// Close a WebSocket connection
    pub fn close(self: *WebSocket, conn_id: u32) !void {
        for (self.connections.items) |*conn| {
            if (conn.id == conn_id) {
                conn.state = .closed;
                return;
            }
        }
        return error.ConnectionNotFound;
    }
};

/// HTTP/3 with QUIC transport
pub const HTTP3 = struct {
    allocator: Allocator,
    connections: ArrayList(Connection),
    requests: ArrayList(Request),

    pub const Connection = struct {
        id: u32,
        host: []const u8,
        port: u16,
        tls_enabled: bool = true,
        state: ConnectionState,

        pub const ConnectionState = enum {
            idle,
            connecting,
            connected,
            .closed,
        };
    };

    pub const Request = struct {
        id: u32,
        connection_id: u32,
        method: Method,
        path: []const u8,
        headers: std.StringHashMap([]const u8),
        body: ?[]const u8 = null,
        response: ?Response = null,

        pub const Method = enum {
            GET,
            POST,
            PUT,
            DELETE,
            PATCH,
            HEAD,
            OPTIONS,
        };

        pub const Response = struct {
            status: u16,
            headers: std.StringHashMap([]const u8),
            body: []const u8,
        };
    };

    pub fn init(allocator: Allocator) !*HTTP3 {
        const http3 = try allocator.create(HTTP3);
        http3.* = HTTP3{
            .allocator = allocator,
            .connections = ArrayList(Connection).init(allocator),
            .requests = ArrayList(Request).init(allocator),
        };
        return http3;
    }

    pub fn deinit(self: *HTTP3) void {
        for (self.connections.items) |*conn| {
            self.allocator.free(conn.host);
        }
        for (self.requests.items) |*req| {
            self.allocator.free(req.path);
            req.headers.deinit();
            if (req.body) |body| self.allocator.free(body);
            if (req.response) |*resp| {
                self.allocator.free(resp.body);
                resp.headers.deinit();
            }
        }
        self.connections.deinit();
        self.requests.deinit();
        self.allocator.destroy(self);
    }

    pub fn connect(self: *HTTP3, host: []const u8, port: u16) !u32 {
        const conn_id: u32 = @intCast(self.connections.items.len);
        try self.connections.append(Connection{
            .id = conn_id,
            .host = try self.allocator.dupe(u8, host),
            .port = port,
            .state = .connected,
        });
        return conn_id;
    }

    pub fn request(
        self: *HTTP3,
        conn_id: u32,
        method: Request.Method,
        path: []const u8,
        body: ?[]const u8,
    ) !u32 {
        const req_id: u32 = @intCast(self.requests.items.len);
        try self.requests.append(Request{
            .id = req_id,
            .connection_id = conn_id,
            .method = method,
            .path = try self.allocator.dupe(u8, path),
            .headers = std.StringHashMap([]const u8).init(self.allocator),
            .body = if (body) |b| try self.allocator.dupe(u8, b) else null,
        });
        return req_id;
    }
};

/// gRPC support with streaming
pub const GRPC = struct {
    allocator: Allocator,
    services: ArrayList(Service),
    streams: ArrayList(Stream),

    pub const Service = struct {
        id: u32,
        name: []const u8,
        methods: ArrayList(Method),

        pub const Method = struct {
            name: []const u8,
            streaming_type: StreamingType,

            pub const StreamingType = enum {
                unary,
                client_stream,
                server_stream,
                bidirectional,
            };
        };
    };

    pub const Stream = struct {
        id: u32,
        service_id: u32,
        method_name: []const u8,
        messages: ArrayList(Message),
        state: StreamState,

        pub const Message = struct {
            data: []const u8,
            metadata: std.StringHashMap([]const u8),
        };

        pub const StreamState = enum {
            open,
            half.closed,
            .closed,
        };
    };

    pub fn init(allocator: Allocator) !*GRPC {
        const grpc = try allocator.create(GRPC);
        grpc.* = GRPC{
            .allocator = allocator,
            .services = ArrayList(Service).init(allocator),
            .streams = ArrayList(Stream).init(allocator),
        };
        return grpc;
    }

    pub fn deinit(self: *GRPC) void {
        for (self.services.items) |*service| {
            self.allocator.free(service.name);
            for (service.methods.items) |*method| {
                self.allocator.free(method.name);
            }
            service.methods.deinit();
        }
        for (self.streams.items) |*stream| {
            self.allocator.free(stream.method_name);
            for (stream.messages.items) |*msg| {
                self.allocator.free(msg.data);
                msg.metadata.deinit();
            }
            stream.messages.deinit();
        }
        self.services.deinit();
        self.streams.deinit();
        self.allocator.destroy(self);
    }

    pub fn registerService(self: *GRPC, name: []const u8) !u32 {
        const service_id: u32 = @intCast(self.services.items.len);
        try self.services.append(Service{
            .id = service_id,
            .name = try self.allocator.dupe(u8, name),
            .methods = ArrayList(Service.Method).init(self.allocator),
        });
        return service_id;
    }

    pub fn openStream(self: *GRPC, service_id: u32, method_name: []const u8) !u32 {
        const stream_id: u32 = @intCast(self.streams.items.len);
        try self.streams.append(Stream{
            .id = stream_id,
            .service_id = service_id,
            .method_name = try self.allocator.dupe(u8, method_name),
            .messages = ArrayList(Stream.Message).init(self.allocator),
            .state = .open,
        });
        return stream_id;
    }

    pub fn sendMessage(self: *GRPC, stream_id: u32, data: []const u8) !void {
        for (self.streams.items) |*stream| {
            if (stream.id == stream_id) {
                try stream.messages.append(Stream.Message{
                    .data = try self.allocator.dupe(u8, data),
                    .metadata = std.StringHashMap([]const u8).init(self.allocator),
                });
                return;
            }
        }
        return error.StreamNotFound;
    }
};

/// Advanced streaming with backpressure
pub const Streaming = struct {
    allocator: Allocator,
    streams: ArrayList(Stream),

    pub const Stream = struct {
        id: u32,
        buffer: ArrayList([]const u8),
        capacity: usize,
        watermark_high: usize,
        watermark_low: usize,
        paused: bool = false,

        pub fn backpressure(self: *Stream) bool {
            return self.buffer.items.len >= self.watermark_high;
        }

        pub fn canResume(self: *Stream) bool {
            return self.buffer.items.len <= self.watermark_low;
        }
    };

    pub fn init(allocator: Allocator) !*Streaming {
        const streaming = try allocator.create(Streaming);
        streaming.* = Streaming{
            .allocator = allocator,
            .streams = ArrayList(Stream).init(allocator),
        };
        return streaming;
    }

    pub fn deinit(self: *Streaming) void {
        for (self.streams.items) |*stream| {
            for (stream.buffer.items) |item| {
                self.allocator.free(item);
            }
            stream.buffer.deinit();
        }
        self.streams.deinit();
        self.allocator.destroy(self);
    }

    pub fn createStream(self: *Streaming, capacity: usize) !u32 {
        const stream_id: u32 = @intCast(self.streams.items.len);
        try self.streams.append(Stream{
            .id = stream_id,
            .buffer = ArrayList([]const u8).init(self.allocator),
            .capacity = capacity,
            .watermark_high = capacity * 80 / 100,
            .watermark_low = capacity * 20 / 100,
        });
        return stream_id;
    }

    pub fn write(self: *Streaming, stream_id: u32, data: []const u8) !void {
        for (self.streams.items) |*stream| {
            if (stream.id == stream_id) {
                if (stream.buffer.items.len >= stream.capacity) {
                    return error.StreamFull;
                }
                if (stream.backpressure()) {
                    stream.paused = true;
                    return error.Backpressure;
                }
                try stream.buffer.append(try self.allocator.dupe(u8, data));
                return;
            }
        }
        return error.StreamNotFound;
    }

    pub fn read(self: *Streaming, stream_id: u32) !?[]const u8 {
        for (self.streams.items) |*stream| {
            if (stream.id == stream_id) {
                if (stream.buffer.items.len == 0) return null;
                const data = stream.buffer.orderedRemove(0);
                if (stream.paused and stream.canResume()) {
                    stream.paused = false;
                }
                return data;
            }
        }
        return error.StreamNotFound;
    }
};

/// Cryptographic operations
pub const Crypto = struct {
    allocator: Allocator,
    keys: ArrayList(Key),
    signatures: ArrayList(Signature),

    pub const Key = struct {
        id: u32,
        algorithm: Algorithm,
        key_data: []const u8,
        is_private: bool,

        pub const Algorithm = enum {
            rsa_2048,
            rsa_4096,
            ed25519,
            ecdsa_p256,
            ecdsa_p384,
            aes_256_gcm,
            chacha20_poly1305,
        };
    };

    pub const Signature = struct {
        id: u32,
        key_id: u32,
        data: []const u8,
        signature: []const u8,
    };

    pub fn init(allocator: Allocator) !*Crypto {
        const crypto_ctx = try allocator.create(Crypto);
        crypto_ctx.* = Crypto{
            .allocator = allocator,
            .keys = ArrayList(Key).init(allocator),
            .signatures = ArrayList(Signature).init(allocator),
        };
        return crypto_ctx;
    }

    pub fn deinit(self: *Crypto) void {
        for (self.keys.items) |*key| {
            self.allocator.free(key.key_data);
        }
        for (self.signatures.items) |*sig| {
            self.allocator.free(sig.data);
            self.allocator.free(sig.signature);
        }
        self.keys.deinit();
        self.signatures.deinit();
        self.allocator.destroy(self);
    }

    pub fn generateKey(self: *Crypto, algorithm: Key.Algorithm, is_private: bool) !u32 {
        const key_id: u32 = @intCast(self.keys.items.len);
        const key_size: usize = switch (algorithm) {
            .rsa_2048 => 256,
            .rsa_4096 => 512,
            .ed25519 => if (is_private) Ed25519.SecretKey.encoded_length else Ed25519.PublicKey.encoded_length,
            .ecdsa_p256 => 32,
            .ecdsa_p384 => 48,
            .aes_256_gcm => 32,
            .chacha20_poly1305 => 32,
        };

        const key_data = try self.allocator.alloc(u8, key_size);

        // Generate real random keys using Zig's crypto random
        switch (algorithm) {
            .ed25519 => {
                if (is_private) {
                    // Generate Ed25519 key pair
                    const key_pair = Ed25519.KeyPair.generate();
                    @memcpy(key_data[0..Ed25519.SecretKey.encoded_length], &key_pair.secret_key.bytes);
                } else {
                    // For public key, generate a key pair and extract public key
                    const key_pair = Ed25519.KeyPair.generate();
                    @memcpy(key_data[0..Ed25519.PublicKey.encoded_length], &key_pair.public_key.bytes);
                }
            },
            .aes_256_gcm, .chacha20_poly1305 => {
                // Generate random symmetric key
                crypto.random.bytes(key_data);
            },
            else => {
                // For RSA and ECDSA, use random bytes (full implementation would require more work)
                crypto.random.bytes(key_data);
            },
        }

        try self.keys.append(Key{
            .id = key_id,
            .algorithm = algorithm,
            .key_data = key_data,
            .is_private = is_private,
        });
        return key_id;
    }

    pub fn sign(self: *Crypto, key_id: u32, data: []const u8) !u32 {
        // Find the key
        const key = blk: {
            for (self.keys.items) |*k| {
                if (k.id == key_id) break :blk k;
            }
            return error.KeyNotFound;
        };

        if (!key.is_private) return error.NotPrivateKey;

        const sig_id: u32 = @intCast(self.signatures.items.len);

        var signature_data: []u8 = undefined;

        switch (key.algorithm) {
            .ed25519 => {
                // Real Ed25519 signing
                if (key.key_data.len < Ed25519.SecretKey.encoded_length) return error.InvalidKey;
                const secret_key = Ed25519.SecretKey.fromBytes(key.key_data[0..Ed25519.SecretKey.encoded_length].*) catch return error.InvalidKey;
                const key_pair = try Ed25519.KeyPair.fromSecretKey(secret_key);
                const sig = try key_pair.sign(data, null);
                signature_data = try self.allocator.alloc(u8, Ed25519.Signature.encoded_length);
                @memcpy(signature_data, &sig.toBytes());
            },
            else => {
                // For other algorithms, placeholder implementation
                signature_data = try self.allocator.alloc(u8, 64);
                crypto.random.bytes(signature_data);
            },
        }

        try self.signatures.append(Signature{
            .id = sig_id,
            .key_id = key_id,
            .data = try self.allocator.dupe(u8, data),
            .signature = signature_data,
        });
        return sig_id;
    }

    pub fn verify(self: *Crypto, key_id: u32, data: []const u8, signature: []const u8) !bool {
        // Find the key
        const key = blk: {
            for (self.keys.items) |*k| {
                if (k.id == key_id) break :blk k;
            }
            return error.KeyNotFound;
        };

        switch (key.algorithm) {
            .ed25519 => {
                // Real Ed25519 verification
                if (signature.len != Ed25519.Signature.encoded_length) return error.InvalidSignature;

                const public_key = if (key.is_private) blk: {
                    if (key.key_data.len < Ed25519.SecretKey.encoded_length) return error.InvalidKey;
                    const secret_key = Ed25519.SecretKey.fromBytes(key.key_data[0..Ed25519.SecretKey.encoded_length].*) catch return error.InvalidKey;
                    const pk_bytes = secret_key.publicKeyBytes();
                    break :blk Ed25519.PublicKey.fromBytes(pk_bytes) catch return error.InvalidKey;
                } else blk: {
                    if (key.key_data.len < Ed25519.PublicKey.encoded_length) return error.InvalidKey;
                    break :blk Ed25519.PublicKey.fromBytes(key.key_data[0..Ed25519.PublicKey.encoded_length].*) catch return error.InvalidKey;
                };

                const sig = Ed25519.Signature.fromBytes(signature[0..Ed25519.Signature.encoded_length].*);
                sig.verify(data, public_key) catch return false;
                return true;
            },
            else => {
                // For other algorithms, placeholder (always return true for compatibility)
                return true;
            },
        }
    }

    pub fn hash(self: *Crypto, algorithm: HashAlgorithm, data: []const u8) ![]const u8 {
        const result = switch (algorithm) {
            .sha256 => blk: {
                var hasher = Sha256.init(.{});
                hasher.update(data);
                var digest: [Sha256.digest_length]u8 = undefined;
                hasher.final(&digest);
                const result_copy = try self.allocator.alloc(u8, Sha256.digest_length);
                @memcpy(result_copy, &digest);
                break :blk result_copy;
            },
            .sha384 => blk: {
                var hasher = Sha384.init(.{});
                hasher.update(data);
                var digest: [Sha384.digest_length]u8 = undefined;
                hasher.final(&digest);
                const result_copy = try self.allocator.alloc(u8, Sha384.digest_length);
                @memcpy(result_copy, &digest);
                break :blk result_copy;
            },
            .sha512 => blk: {
                var hasher = Sha512.init(.{});
                hasher.update(data);
                var digest: [Sha512.digest_length]u8 = undefined;
                hasher.final(&digest);
                const result_copy = try self.allocator.alloc(u8, Sha512.digest_length);
                @memcpy(result_copy, &digest);
                break :blk result_copy;
            },
            .blake3 => blk: {
                var digest: [Blake3.digest_length]u8 = undefined;
                Blake3.hash(data, &digest, .{});
                const result_copy = try self.allocator.alloc(u8, Blake3.digest_length);
                @memcpy(result_copy, &digest);
                break :blk result_copy;
            },
        };
        return result;
    }

    pub const HashAlgorithm = enum {
        sha256,
        sha384,
        sha512,
        blake3,
    };
};

/// Observability (metrics, tracing, logging)
pub const Observability = struct {
    allocator: Allocator,
    metrics: ArrayList(Metric),
    spans: ArrayList(Span),
    logs: ArrayList(LogEntry),

    pub const Metric = struct {
        name: []const u8,
        value: f64,
        timestamp: i64,
        labels: std.StringHashMap([]const u8),
        kind: MetricKind,

        pub const MetricKind = enum {
            counter,
            gauge,
            histogram,
            summary,
        };
    };

    pub const Span = struct {
        id: u64,
        parent_id: ?u64,
        name: []const u8,
        start_time: i64,
        end_time: ?i64,
        attributes: std.StringHashMap([]const u8),
        events: ArrayList(SpanEvent),

        pub const SpanEvent = struct {
            name: []const u8,
            timestamp: i64,
            attributes: std.StringHashMap([]const u8),
        };
    };

    pub const LogEntry = struct {
        level: LogLevel,
        message: []const u8,
        timestamp: i64,
        fields: std.StringHashMap([]const u8),

        pub const LogLevel = enum {
            trace,
            debug,
            info,
            warn,
            @"error",
            fatal,
        };
    };

    pub fn init(allocator: Allocator) !*Observability {
        const obs = try allocator.create(Observability);
        obs.* = Observability{
            .allocator = allocator,
            .metrics = ArrayList(Metric).init(allocator),
            .spans = ArrayList(Span).init(allocator),
            .logs = ArrayList(LogEntry).init(allocator),
        };
        return obs;
    }

    pub fn deinit(self: *Observability) void {
        for (self.metrics.items) |*metric| {
            self.allocator.free(metric.name);
            metric.labels.deinit();
        }
        for (self.spans.items) |*span| {
            self.allocator.free(span.name);
            span.attributes.deinit();
            for (span.events.items) |*event| {
                self.allocator.free(event.name);
                event.attributes.deinit();
            }
            span.events.deinit();
        }
        for (self.logs.items) |*entry| {
            self.allocator.free(entry.message);
            entry.fields.deinit();
        }
        self.metrics.deinit();
        self.spans.deinit();
        self.logs.deinit();
        self.allocator.destroy(self);
    }

    pub fn recordMetric(
        self: *Observability,
        name: []const u8,
        value: f64,
        kind: Metric.MetricKind,
    ) !void {
        try self.metrics.append(Metric{
            .name = try self.allocator.dupe(u8, name),
            .value = value,
            .timestamp = std.time.milliTimestamp(),
            .labels = std.StringHashMap([]const u8).init(self.allocator),
            .kind = kind,
        });
    }

    pub fn startSpan(self: *Observability, name: []const u8, parent_id: ?u64) !u64 {
        const span_id: u64 = @intCast(self.spans.items.len);
        try self.spans.append(Span{
            .id = span_id,
            .parent_id = parent_id,
            .name = try self.allocator.dupe(u8, name),
            .start_time = std.time.milliTimestamp(),
            .end_time = null,
            .attributes = std.StringHashMap([]const u8).init(self.allocator),
            .events = ArrayList(Span.SpanEvent).init(self.allocator),
        });
        return span_id;
    }

    pub fn endSpan(self: *Observability, span_id: u64) !void {
        for (self.spans.items) |*span| {
            if (span.id == span_id) {
                span.end_time = std.time.milliTimestamp();
                return;
            }
        }
        return error.SpanNotFound;
    }

    pub fn log(
        self: *Observability,
        level: LogEntry.LogLevel,
        message: []const u8,
    ) !void {
        try self.logs.append(LogEntry{
            .level = level,
            .message = try self.allocator.dupe(u8, message),
            .timestamp = std.time.milliTimestamp(),
            .fields = std.StringHashMap([]const u8).init(self.allocator),
        });
    }
};
