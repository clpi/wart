const std = @import("std");
const WASI3 = @import("../../src/wasm/wasi3.zig").WASI3;
const WASI2 = @import("../../src/wasm/wasi2.zig").WASI2;
const Crypto = @import("../../src/wasm/wasi3.zig").Crypto;
const crypto = std.crypto;

test "WASI3 Crypto - Ed25519 key generation" {
    var io_provider = std.Io.Threaded.init(std.testing.allocator, .{});
    defer io_provider.deinit();
    var wasi2 = try WASI2.init(std.testing.allocator, io_provider.io());
    defer wasi2.deinit();
    
    var wasi3 = try WASI3.init(std.testing.allocator, wasi2, io_provider.io());
    defer wasi3.deinit();
    
    // Generate a private key
    const private_key_id = try wasi3.crypto.generateKey(.ed25519, true);
    try std.testing.expect(private_key_id == 0);
    
    // Generate a public key
    const public_key_id = try wasi3.crypto.generateKey(.ed25519, false);
    try std.testing.expect(public_key_id == 1);
    
    // Verify keys were stored
    try std.testing.expect(wasi3.crypto.keys.items.len == 2);
    try std.testing.expect(wasi3.crypto.keys.items[0].algorithm == .ed25519);
    try std.testing.expect(wasi3.crypto.keys.items[0].is_private == true);
    try std.testing.expect(wasi3.crypto.keys.items[1].is_private == false);
}

test "WASI3 Crypto - Ed25519 signing and verification" {
    var io_provider = std.Io.Threaded.init(std.testing.allocator, .{});
    defer io_provider.deinit();
    var wasi2 = try WASI2.init(std.testing.allocator, io_provider.io());
    defer wasi2.deinit();
    
    var wasi3 = try WASI3.init(std.testing.allocator, wasi2, io_provider.io());
    defer wasi3.deinit();
    
    // Generate a key pair
    const key_pair = try crypto.sign.Ed25519.KeyPair.create(null);
    
    // Store the private key
    const private_key_id: u32 = @intCast(wasi3.crypto.keys.items.len);
    const private_key_data = try std.testing.allocator.alloc(u8, crypto.sign.Ed25519.SecretKey.encoded_length);
    @memcpy(private_key_data, &key_pair.secret_key.bytes);
    try wasi3.crypto.keys.append(.{
        .id = private_key_id,
        .algorithm = .ed25519,
        .key_data = private_key_data,
        .is_private = true,
    });
    
    // Store the public key
    const public_key_id: u32 = @intCast(wasi3.crypto.keys.items.len);
    const public_key_data = try std.testing.allocator.alloc(u8, crypto.sign.Ed25519.PublicKey.encoded_length);
    @memcpy(public_key_data, &key_pair.public_key.bytes);
    try wasi3.crypto.keys.append(.{
        .id = public_key_id,
        .algorithm = .ed25519,
        .key_data = public_key_data,
        .is_private = false,
    });
    
    // Sign a message
    const message = "Hello, WASI3 Crypto!";
    const signature_id = try wasi3.crypto.sign(private_key_id, message);
    try std.testing.expect(signature_id == 0);
    
    // Verify the signature
    try std.testing.expect(wasi3.crypto.signatures.items.len > 0);
    const signature = wasi3.crypto.signatures.items[0].signature;
    const verified = try wasi3.crypto.verify(public_key_id, message, signature);
    try std.testing.expect(verified == true);
    
    // Verify with wrong message should fail
    const wrong_verified = try wasi3.crypto.verify(public_key_id, "Wrong message", signature);
    try std.testing.expect(wrong_verified == false);
}

test "WASI3 Crypto - SHA256 hash" {
    var io_provider = std.Io.Threaded.init(std.testing.allocator, .{});
    defer io_provider.deinit();
    var wasi2 = try WASI2.init(std.testing.allocator, io_provider.io());
    defer wasi2.deinit();
    
    var wasi3 = try WASI3.init(std.testing.allocator, wasi2, io_provider.io());
    defer wasi3.deinit();
    
    const data = "Hello, World!";
    const hash = try wasi3.crypto.hash(.sha256, data);
    defer std.testing.allocator.free(hash);
    
    // Verify hash length
    try std.testing.expect(hash.len == crypto.hash.sha2.Sha256.digest_length);
    
    // Compute expected hash for comparison
    var expected: [crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    crypto.hash.sha2.Sha256.hash(data, &expected, .{});
    
    // Verify hash matches
    try std.testing.expectEqualSlices(u8, &expected, hash);
}

test "WASI3 Crypto - SHA384 hash" {
    var io_provider = std.Io.Threaded.init(std.testing.allocator, .{});
    defer io_provider.deinit();
    var wasi2 = try WASI2.init(std.testing.allocator, io_provider.io());
    defer wasi2.deinit();
    
    var wasi3 = try WASI3.init(std.testing.allocator, wasi2, io_provider.io());
    defer wasi3.deinit();
    
    const data = "Test data for SHA384";
    const hash = try wasi3.crypto.hash(.sha384, data);
    defer std.testing.allocator.free(hash);
    
    // Verify hash length
    try std.testing.expect(hash.len == crypto.hash.sha2.Sha384.digest_length);
    
    // Compute expected hash for comparison
    var expected: [crypto.hash.sha2.Sha384.digest_length]u8 = undefined;
    crypto.hash.sha2.Sha384.hash(data, &expected, .{});
    
    // Verify hash matches
    try std.testing.expectEqualSlices(u8, &expected, hash);
}

test "WASI3 Crypto - SHA512 hash" {
    var io_provider = std.Io.Threaded.init(std.testing.allocator, .{});
    defer io_provider.deinit();
    var wasi2 = try WASI2.init(std.testing.allocator, io_provider.io());
    defer wasi2.deinit();
    
    var wasi3 = try WASI3.init(std.testing.allocator, wasi2, io_provider.io());
    defer wasi3.deinit();
    
    const data = "Test data for SHA512";
    const hash = try wasi3.crypto.hash(.sha512, data);
    defer std.testing.allocator.free(hash);
    
    // Verify hash length
    try std.testing.expect(hash.len == crypto.hash.sha2.Sha512.digest_length);
    
    // Compute expected hash for comparison
    var expected: [crypto.hash.sha2.Sha512.digest_length]u8 = undefined;
    crypto.hash.sha2.Sha512.hash(data, &expected, .{});
    
    // Verify hash matches
    try std.testing.expectEqualSlices(u8, &expected, hash);
}

test "WASI3 Crypto - BLAKE3 hash" {
    var io_provider = std.Io.Threaded.init(std.testing.allocator, .{});
    defer io_provider.deinit();
    var wasi2 = try WASI2.init(std.testing.allocator, io_provider.io());
    defer wasi2.deinit();
    
    var wasi3 = try WASI3.init(std.testing.allocator, wasi2, io_provider.io());
    defer wasi3.deinit();
    
    const data = "Test data for BLAKE3";
    const hash = try wasi3.crypto.hash(.blake3, data);
    defer std.testing.allocator.free(hash);
    
    // Verify hash length
    try std.testing.expect(hash.len == crypto.hash.Blake3.digest_length);
    
    // Compute expected hash for comparison
    var expected: [crypto.hash.Blake3.digest_length]u8 = undefined;
    crypto.hash.Blake3.hash(data, &expected, .{});
    
    // Verify hash matches
    try std.testing.expectEqualSlices(u8, &expected, hash);
}

test "WASI3 Crypto - AES-256-GCM key generation" {
    var io_provider = std.Io.Threaded.init(std.testing.allocator, .{});
    defer io_provider.deinit();
    var wasi2 = try WASI2.init(std.testing.allocator, io_provider.io());
    defer wasi2.deinit();
    
    var wasi3 = try WASI3.init(std.testing.allocator, wasi2, io_provider.io());
    defer wasi3.deinit();
    
    const key_id = try wasi3.crypto.generateKey(.aes_256_gcm, true);
    try std.testing.expect(key_id == 0);
    
    // Verify key size
    const key = &wasi3.crypto.keys.items[0];
    try std.testing.expect(key.key_data.len == 32); // 256 bits
    try std.testing.expect(key.algorithm == .aes_256_gcm);
    
    // Verify key is not all zeros (random)
    var all_zeros = true;
    for (key.key_data) |byte| {
        if (byte != 0) {
            all_zeros = false;
            break;
        }
    }
    try std.testing.expect(!all_zeros);
}

test "WASI3 Crypto - ChaCha20-Poly1305 key generation" {
    var io_provider = std.Io.Threaded.init(std.testing.allocator, .{});
    defer io_provider.deinit();
    var wasi2 = try WASI2.init(std.testing.allocator, io_provider.io());
    defer wasi2.deinit();
    
    var wasi3 = try WASI3.init(std.testing.allocator, wasi2, io_provider.io());
    defer wasi3.deinit();
    
    const key_id = try wasi3.crypto.generateKey(.chacha20_poly1305, true);
    try std.testing.expect(key_id == 0);
    
    // Verify key size
    const key = &wasi3.crypto.keys.items[0];
    try std.testing.expect(key.key_data.len == 32); // 256 bits
    try std.testing.expect(key.algorithm == .chacha20_poly1305);
    
    // Verify key is not all zeros (random)
    var all_zeros = true;
    for (key.key_data) |byte| {
        if (byte != 0) {
            all_zeros = false;
            break;
        }
    }
    try std.testing.expect(!all_zeros);
}
