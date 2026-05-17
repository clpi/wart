# Multi-stage build for wart WebAssembly runtime
FROM nixos/nix:latest AS builder

# Enable flakes and install dependencies
RUN echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf

# Copy source
WORKDIR /build
COPY . .

# Build wart with nix
RUN nix build .#foreign --no-sandbox

# Runtime stage - minimal Alpine
FROM alpine:latest AS runtime

# Install runtime dependencies
RUN apk add --no-cache \
    libc6-compat \
    libgcc \
    libstdc++

# Copy binary from builder
COPY --from=builder /build/result/bin/wart /usr/local/bin/wart

# Create workspace
WORKDIR /workspace
VOLUME ["/workspace"]

# Set up user
RUN adduser -D -s /bin/sh wart
USER wart

ENTRYPOINT ["wart"]
CMD ["--help"]

# Development stage
FROM nixos/nix:latest AS dev

RUN echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf

WORKDIR /workspace
COPY . .

# Enter development shell by default
CMD ["nix", "develop"]

FROM runtime
