# Installation

## From Source

### Prerequisites

- [Zig](https://ziglang.org/) 0.16 or later
- Git (for cloning)

### Build Steps

```bash
# Clone the repository
git clone https://github.com/clpi/wart.git
cd wart

# Build release binary
zig build -Drelease=true

# The binary will be at:
# ./zig-out/bin/wart
```

### Build Options

| Option | Description |
|--------|-------------|
| `-Drelease=true` | Build with optimizations |
| `-Duse-llvm=true` | Use LLVM backend (recommended for performance) |
| `-Dsmall=true` | Optimize for binary size |
| `-Ddebug=true` | Include debug symbols |

### Nix

If you use Nix:
```bash
nix build
# or for debug build:
nix build .#debug
```

## Verification

Verify the installation:
```bash
./zig-out/bin/wart --version
```
