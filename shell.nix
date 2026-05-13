{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  name = "wart-dev-shell";

  packages = with pkgs; [
    zig
    git
    jq
    python3
    wabt
    wasm-tools
    binaryen
    hyperfine
    wasmer
    wasmtime
  ];

  shellHook = ''
    echo "wart development shell"
    echo "  zig build"
    echo "  zig build test"
    echo "  bash scripts/fetch-spec-suites.sh"
    echo "  bash scripts/run-spec-tests.sh --profile all"
    echo "  bash scripts/run-benchmarks.sh --profile core-universal"
  '';
}
